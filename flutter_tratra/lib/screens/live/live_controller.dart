// lib/screens/live/live_controller.dart
//
// Suivi en direct d'une mission côté mobile : WebSocket (billet signé de 60 s, reconnexion progressive) avec repli sur la
// lecture périodique de GET /live/, actions (consentement, en route, arrivé) et partage de position (une mesure toutes
// les 5 s au plus, uniquement tant que le serveur l'autorise). Mêmes règles que le web ; le serveur reste l'autorité.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;
import 'package:flutter_tratra/screens/live/live_state.dart';

enum GeoStatus { idle, waiting, sharing, denied, unavailable }

class LiveController extends ChangeNotifier {
  LiveController(this._base, this.bookingId);
  final BaseApi _base;
  final int bookingId;

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
  bool _disposed = false;

  StreamSubscription<Position>? _geoSub;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  Uri _uri(String path) => Uri.parse('${_base.baseUrl}/bookings/$bookingId/live/$path');

  void start() {
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final s = state;
      if (s != null && !s.isOpen) return; // mission close : plus de suivi
      if (!realtime) refresh();
    });
    _openSocket();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _retry?.cancel();
    _socketSub?.cancel();
    _socket?.sink.close();
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
      _syncGeo();
      _notify();
    }
  }

  Future<void> refresh() async {
    try {
      final r = await _base.client.get(_uri(''), headers: await _base.headers);
      if (r.statusCode != 200) _base.handleError(r);
      _apply(_base.decodeBody(r));
    } catch (e) {
      offline = true;
      error = friendlyError(e);
      _notify();
    }
  }

  Future<void> _openSocket() async {
    try {
      final r = await _base.client.post(_uri('ticket/'), headers: await _base.headers, body: '{}');
      if (r.statusCode != 200) _base.handleError(r);
      final t = (_base.decodeBody(r) as Map).cast<String, dynamic>();
      final base = Uri.parse(_base.baseUrl);
      final ws = Uri(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: '${t['path']}',
        queryParameters: {'ticket': '${t['ticket']}'},
      );
      final channel = WebSocketChannel.connect(ws);
      _socket = channel;
      await channel.ready;
      if (_disposed) {
        channel.sink.close();
        return;
      }
      _attempt = 0;
      realtime = true;
      _notify();
      _socketSub = channel.stream.listen(
        (msg) {
          try {
            final d = json.decode('$msg');
            if (d is Map && d['type'] == 'state') _apply(d['state']);
          } catch (_) {/* message illisible : ignoré */}
        },
        onDone: _socketClosed,
        onError: (_) => _socketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _socketClosed();
    }
  }

  void _socketClosed() {
    realtime = false;
    _notify();
    if (_disposed) return;
    _attempt += 1;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: (1 << _attempt).clamp(1, 30)), _openSocket); // reconnexion progressive
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
      if (_geoSub == null) _startGeo();
    } else if (_geoSub != null) {
      _geoSub?.cancel();
      _geoSub = null;
      geo = GeoStatus.idle;
    }
  }

  Future<void> _startGeo() async {
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
      _geoSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen(
        _onPosition,
        onError: (_) {
          geo = GeoStatus.unavailable;
          geoNote = 'Signal GPS indisponible.';
          _notify();
        },
      );
    } catch (_) {
      geo = GeoStatus.unavailable;
      geoNote = 'Signal GPS indisponible.';
      _notify();
    }
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
