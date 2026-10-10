// lib/screens/live/live_controller.dart
//
// Suivi en direct d'une mission côté mobile : WebSocket (billet signé de 60 s, reconnexion progressive) avec repli sur la
// lecture périodique de GET /live/, actions (consentement, en route, arrivé) et partage de position (une mesure toutes
// les 5 s au plus, uniquement tant que le serveur l'autorise). Mêmes règles que le web ; le serveur reste l'autorité.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;
import 'package:flutter_tratra/screens/live/live_socket.dart';
import 'package:flutter_tratra/screens/live/live_state.dart';

enum GeoStatus { idle, waiting, sharing, denied, unavailable }

/// Délai avant la n-ième reconnexion : progressif et plafonné (2 s, 4 s, 8 s, 16 s, 30 s…), sans débordement.
Duration liveReconnectDelay(int attempt) => Duration(seconds: (1 << attempt.clamp(1, 6)).clamp(1, 30));

/// Ouvre la WebSocket du suivi (remplacée dans les tests).
typedef LiveSocketConnector = WebSocketChannel Function(Uri uri);

class LiveController extends ChangeNotifier with WidgetsBindingObserver {
  LiveController(
    this._base,
    this.bookingId, {
    LiveSocketConnector? connect,
    Duration pollEvery = const Duration(seconds: 5),
    Duration watchdogAfter = const Duration(seconds: 45),
    Duration Function(int attempt)? backoff,
    Duration requestTimeout = const Duration(seconds: 10),
  })  : _requestTimeout = requestTimeout,
        _connect = connect ?? connectLiveSocket,
        _pollEvery = pollEvery,
        _watchdogAfter = watchdogAfter,
        _backoff = backoff ?? liveReconnectDelay;
  final BaseApi _base;
  final int bookingId;
  final LiveSocketConnector _connect;
  final Duration _pollEvery;
  final Duration _watchdogAfter;
  final Duration Function(int attempt) _backoff;
  final Duration _requestTimeout;

  LiveSnapshot? state;
  String? error;
  bool realtime = false;
  bool offline = false;
  GeoStatus geo = GeoStatus.idle;
  String? geoNote;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _poll;
  Timer? _retry;
  int _attempt = 0;
  int _gen = 0; // génération de la connexion : les événements d'une connexion remplacée sont ignorés
  bool _disposed = false;
  DateTime _lastSync = DateTime.now();

  StreamSubscription<Position>? _geoSub;
  bool _geoStarting = false;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  Uri _uri(String path) => Uri.parse('${_base.baseUrl}/bookings/$bookingId/live/$path');

  void start() {
    WidgetsBinding.instance.addObserver(this);
    refresh();
    _poll = Timer.periodic(_pollEvery, (_) {
      final s = state;
      if (s != null && !s.isOpen) return; // mission close : plus de suivi
      if (!realtime) {
        refresh();
      } else if (DateTime.now().difference(_lastSync) > _watchdogAfter) {
        _watchdog();
      }
    });
    _openSocket();
  }

  /// Le serveur ne pousse que les changements : après un long silence, on vérifie par une lecture directe ; si elle
  /// échoue (réseau changé ou coupé), la connexion temps réel est rouverte.
  Future<void> _watchdog() async {
    if (!await refresh()) _openSocket();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resume();
  }

  /// Retour au premier plan : Android a pu couper la connexion et le GPS pendant la veille → on repart de zéro.
  void _resume() {
    if (_disposed) return;
    _attempt = 0;
    refresh();
    _openSocket();
    _flushPosition();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _retry?.cancel();
    _closeSocket();
    _geoSub?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _apply(dynamic body) {
    if (body is Map) {
      state = LiveSnapshot.fromJson(body.cast<String, dynamic>());
      error = null;
      offline = false;
      _lastSync = DateTime.now();
      _syncGeo();
      _notify();
    }
  }

  /// Lecture directe de l'état. Vrai si le serveur a répondu ; au retour du réseau, la connexion temps réel est
  /// rouverte tout de suite (sans attendre la fin du délai de reconnexion) et la position est renvoyée.
  bool _refreshing = false;

  Future<bool> refresh() async {
    if (_refreshing) return !offline; // une lecture est déjà en cours : jamais de requêtes empilées sur un réseau lent
    _refreshing = true;
    try {
      final r = await _base.client.get(_uri(''), headers: await _base.headers).timeout(_requestTimeout);
      if (r.statusCode != 200) _base.handleError(r);
      final wasOffline = offline;
      _apply(_base.decodeBody(r));
      if (wasOffline && !_disposed) {
        if (!realtime) {
          _attempt = 0;
          _openSocket();
        }
        _flushPosition();
      }
      return true;
    } catch (e) {
      offline = true;
      error = friendlyError(e);
      _notify();
      return false;
    } finally {
      _refreshing = false;
    }
  }

  void _closeSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    realtime = false;
  }

  Future<void> _openSocket() async {
    if (_disposed) return;
    _retry?.cancel();
    _closeSocket();
    final gen = ++_gen;
    try {
      final r = await _base.client.post(_uri('ticket/'), headers: await _base.headers, body: '{}').timeout(_requestTimeout);
      if (r.statusCode != 200) _base.handleError(r);
      if (_disposed || gen != _gen) return;
      final t = (_base.decodeBody(r) as Map).cast<String, dynamic>();
      final base = Uri.parse(_base.baseUrl);
      final ws = Uri(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '${t['path']}',
        queryParameters: {'ticket': '${t['ticket']}'},
      );
      final channel = _connect(ws);
      _socket = channel;
      await channel.ready;
      if (_disposed || gen != _gen) {
        channel.sink.close();
        return;
      }
      _attempt = 0;
      realtime = true;
      _lastSync = DateTime.now();
      _notify();
      _socketSub = channel.stream.listen(
        (msg) {
          try {
            final d = json.decode('$msg');
            if (d is Map && d['type'] == 'state') _apply(d['state']);
          } catch (_) {/* message illisible : ignoré */}
        },
        onDone: () => _socketClosed(gen),
        onError: (_) => _socketClosed(gen),
        cancelOnError: true,
      );
    } catch (_) {
      _socketClosed(gen);
    }
  }

  void _socketClosed(int gen) {
    if (gen != _gen) return; // connexion déjà remplacée
    realtime = false;
    _notify();
    if (_disposed) return;
    _attempt = (_attempt + 1).clamp(1, 6); // reconnexion progressive, plafonnée (2 s … 30 s)
    _retry?.cancel();
    _retry = Timer(_backoff(_attempt), _openSocket);
  }

  // ---- Actions ----------------------------------------------------------------------------------------------

  Future<bool> _act(String path, [Map<String, dynamic>? body]) async {
    try {
      final r = await _base.client.post(_uri(path), headers: await _base.headers, body: json.encode(body ?? const {}));
      final d = _base.decodeBody(r);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        error = d is Map && d['detail'] != null ? '${d['detail']}' : 'L’action a échoué. Réessayez dans un instant.';
        _notify();
        return false;
      }
      _apply(d);
      return true;
    } catch (e) {
      error = friendlyError(e, 'L’action a échoué. Réessayez dans un instant.');
      _notify();
      return false;
    }
  }

  Future<bool> setConsent(bool share) => _act('consent/', {'share': share});
  Future<bool> startRoute() => _act('en-route/', {'consent': true});
  Future<bool> arrive() => _act('arrived/');

  // ---- Partage de position ------------------------------------------------------------------------------------

  bool get _shouldShare {
    final s = state;
    if (s == null) return false;
    return s.isArtisan ? (s.phase == 'en_route' && s.artisanSharing) : (s.clientSharing && (s.phase == 'confirmed' || s.phase == 'en_route'));
  }

  void _syncGeo() {
    if (_shouldShare) {
      if (_geoSub == null && !_geoStarting) _startGeo();
    } else if (_geoSub != null) {
      _geoSub?.cancel();
      _geoSub = null;
      geo = GeoStatus.idle;
    }
  }

  Future<void> _startGeo() async {
    _geoStarting = true;
    geo = GeoStatus.waiting;
    _notify();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        geo = GeoStatus.unavailable;
        geoNote = 'Activez la localisation de votre téléphone.';
        _notify();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        geo = GeoStatus.denied;
        geoNote = 'L’accès à votre position est refusé : autorisez-le dans les réglages de l’application.';
        _notify();
        return;
      }
      if (_disposed || !_shouldShare) return; // le partage a été suspendu pendant la demande d'autorisation
      _geoSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen(
        _onPosition,
        onError: (_) {
          // Flux interrompu (GPS coupé…) : on libère l'abonnement ; il sera relancé dès que le service revient.
          _geoSub?.cancel();
          _geoSub = null;
          geo = GeoStatus.unavailable;
          geoNote = 'Signal GPS indisponible.';
          _notify();
        },
      );
    } catch (_) {
      geo = GeoStatus.unavailable;
      geoNote = 'Signal GPS indisponible.';
      _notify();
    } finally {
      _geoStarting = false;
    }
  }

  /// Après une coupure ou un retour au premier plan : envoie tout de suite la position actuelle (un artisan immobile
  /// n'en émettrait pas avant d'avoir bougé de 5 m, et le client verrait une position périmée).
  Future<void> _flushPosition() async {
    if (_geoSub == null || !_shouldShare) return;
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
      await _onPosition(p);
    } catch (_) {/* sans position disponible : le flux normal reprendra */}
  }

  Future<void> _onPosition(Position p) async {
    final now = DateTime.now();
    if (now.difference(_lastSent).inSeconds < 5 || !_shouldShare) return;
    _lastSent = now;
    try {
      final r = await _base.client.post(
        _uri('position/'),
        headers: await _base.headers,
        body: json.encode({
          'lat': p.latitude,
          'lng': p.longitude,
          'accuracy': p.accuracy,
          'captured_at': p.timestamp.toUtc().toIso8601String(),
          if (p.speed >= 0) 'speed': p.speed,
          if (p.heading >= 0) 'heading': p.heading,
        }),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        geo = GeoStatus.sharing;
        geoNote = null;
        _apply(_base.decodeBody(r));
      } else {
        geoNote = 'Le serveur a refusé la position.';
        _notify();
      }
    } catch (_) {
      geoNote = 'Connexion perdue : la position reprendra automatiquement.';
      _notify();
    }
  }
}
