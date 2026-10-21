// lib/services/push_service.dart
//
// Notifications push (Firebase Cloud Messaging) — Android et iOS (jamais le web).
//
//  * Configuration Firebase : valeurs `--dart-define` (lib/services/firebase_config.dart, rien dans Git) ou fichier natif. Sans aucune
//    des deux (android/app/google-services.json absent) l'initialisation échoue proprement :
//    l'application fonctionne, le statut passe à `unconfigured`, la notification in-app reste la source fiable.
//  * Le jeton de l'appareil est enregistré sur le compte COURANT (POST /devices/, idempotent côté serveur) et retiré à
//    la déconnexion (DELETE /devices/{id}/) : un téléphone ne reçoit jamais les notifications d'un autre compte.
//  * Jamais d'exception vers l'appelant, aucun jeton écrit dans les journaux.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/services/firebase_config.dart';

enum PushStatus {
  /// Pas encore démarré.
  idle,

  /// Plateforme non prise en charge (web).
  unsupported,

  /// Projet Firebase absent du build (google-services.json non fourni) ou refusé.
  unconfigured,

  /// Notifications refusées par l'utilisateur : le jeton est tout de même enregistré (réglable ensuite).
  denied,

  /// Appareil enregistré sur le compte courant.
  registered,

  /// Échec réseau/serveur à l'enregistrement : nouvel essai au prochain démarrage ou changement de jeton.
  error,
}

/// Message reçu, réduit à ce que l'application exploite.
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
}

/// Passerelle vers Firebase : isolée pour être remplacée dans les tests (aucun Firebase réel requis).
abstract class PushGateway {
  /// Initialise Firebase ; faux si le projet n'est pas configuré.
  Future<bool> init();

  /// Demande l'autorisation d'afficher des notifications (dialogue système sur Android 13+). Vrai si accordée.
  Future<bool> requestPermission();

  Future<String?> token();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onOpenedFromBackground;
  Future<PushMessage?> initialMessage();
}

PushMessage _fromRemote(RemoteMessage m) => PushMessage(
      title: m.notification?.title,
      body: m.notification?.body,
      data: Map<String, dynamic>.from(m.data),
    );

class FirebasePushGateway implements PushGateway {
  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  Future<bool> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        // Configuration injectée au build (--dart-define) en priorité ; sinon fichier natif (google-services.json / plist).
        final options = firebaseOptionsFor(defaultTargetPlatform);
        await (options != null ? Firebase.initializeApp(options: options) : Firebase.initializeApp());
      }
      // iOS : afficher aussi la notification quand l'application est ouverte (Android : bandeau dans l'application).
      await _fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      return true;
    } catch (_) {
      return false; // pas de google-services.json / GoogleService-Info.plist dans ce build
    }
  }

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS : le jeton APNs doit exister avant le jeton FCM (délivré par le système, quelques secondes au plus).
      for (var i = 0; i < 10 && await _fm.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (await _fm.getAPNSToken() == null) return null;
    }
    return _fm.getToken();
  }

  @override
  Future<void> deleteToken() => _fm.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage.map(_fromRemote);

  @override
  Stream<PushMessage> get onOpenedFromBackground => FirebaseMessaging.onMessageOpenedApp.map(_fromRemote);

  @override
  Future<PushMessage?> initialMessage() async {
    final m = await _fm.getInitialMessage();
    return m == null ? null : _fromRemote(m);
  }
}

class PushService extends ChangeNotifier {
  PushService(this._api, {PushGateway? gateway, bool? supported})
      : _gateway = gateway ?? FirebasePushGateway(),
        _supported = supported ?? (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS));

  final BaseApi _api;
  final PushGateway _gateway;
  final bool _supported;

  static const String deviceIdKey = 'push_device_id';
  static const String deviceTokenKey = AppConstants.fcmTokenKey;

  PushStatus _status = PushStatus.idle;
  PushStatus get status => _status;

  /// Message reçu application ouverte (bandeau in-app).
  void Function(PushMessage message)? onForeground;

  /// Notification touchée (application en arrière-plan ou fermée).
  void Function(PushMessage message)? onTap;

  bool _started = false;
  bool _ready = false;
  String? _userId;
  final List<StreamSubscription<dynamic>> _subs = [];

  void _set(PushStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  /// À appeler une fois au démarrage (après le premier écran) : initialise Firebase et branche les écoutes.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!_supported) {
      _set(PushStatus.unsupported);
      return;
    }
    try {
      _ready = await _gateway.init();
      if (!_ready) {
        _set(PushStatus.unconfigured);
        return;
      }
      _subs
        ..add(_gateway.onTokenRefresh.listen((t) => _register(t)))
        ..add(_gateway.onForegroundMessage.listen((m) => onForeground?.call(m)))
        ..add(_gateway.onOpenedFromBackground.listen((m) => onTap?.call(m)));
      final first = await _gateway.initialMessage(); // application lancée en touchant une notification
      if (first != null) onTap?.call(first);
      if (_userId != null) await _registerCurrent();
    } catch (_) {
      _set(PushStatus.unconfigured);
    }
  }

  /// Compte courant (null = déconnecté). Enregistre l'appareil dès qu'un compte est connecté.
  Future<void> bindUser(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    if (userId == null) {
      await _forgetDevice();
      return;
    }
    if (_ready) await _registerCurrent();
  }

  Future<void> _registerCurrent() async {
    try {
      final granted = await _gateway.requestPermission();
      final token = await _gateway.token();
      if (token == null || token.isEmpty) {
        _set(PushStatus.error);
        return;
      }
      final ok = await _register(token);
      if (ok && !granted) _set(PushStatus.denied);
    } catch (_) {
      _set(PushStatus.error);
    }
  }

  Future<bool> _register(String token) async {
    if (_userId == null) return false; // jeton renouvelé alors que personne n'est connecté : rien à rattacher
    try {
      // Jeton renouvelé : l'ancien est envoyé pour être retiré du compte (jamais de doublon d'appareil).
      final previous = await _api.storage.read(key: deviceTokenKey);
      final r = await _api.client.post(
        Uri.parse('${_api.baseUrl}/devices/'),
        headers: await _api.headers,
        body: jsonEncode({
          'device_token': token,
          'device_type': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          // Android : l'application construit elle-même l'alerte Tratra Flash (actions, compte à rebours, retrait à l'échéance).
          if (defaultTargetPlatform == TargetPlatform.android) 'capabilities': const ['flash1'],
          if (previous != null && previous.isNotEmpty && previous != token) 'previous_token': previous,
        }),
      );
      if (r.statusCode != 200 && r.statusCode != 201) {
        _set(PushStatus.error);
        return false;
      }
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final id = body is Map ? body['id'] : null;
      if (id != null) await _api.storage.write(key: deviceIdKey, value: '$id');
      await _api.storage.write(key: deviceTokenKey, value: token);
      _set(PushStatus.registered);
      return true;
    } catch (_) {
      _set(PushStatus.error);
      return false;
    }
  }

  /// Avant la déconnexion (jeton d'accès encore valide) : retire l'appareil du compte et invalide le jeton FCM, afin
  /// qu'aucune notification de ce compte n'arrive plus sur ce téléphone.
  Future<void> unregister() async {
    try {
      final id = await _api.storage.read(key: deviceIdKey);
      if (id != null && id.isNotEmpty) {
        await _api.client.delete(Uri.parse('${_api.baseUrl}/devices/$id/'), headers: await _api.headers);
      }
    } catch (_) {
      // hors ligne : le serveur rattachera le jeton au prochain compte connecté (enregistrement idempotent)
    }
    await _forgetDevice();
    if (_ready) {
      try {
        await _gateway.deleteToken();
      } catch (_) {}
    }
    _userId = null;
  }

  Future<void> _forgetDevice() async {
    try {
      await _api.storage.delete(key: deviceIdKey);
      await _api.storage.delete(key: deviceTokenKey);
    } catch (_) {}
    if (_ready) _set(PushStatus.idle);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}
