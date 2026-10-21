// lib/flash/flash_native.dart
//
// Pont vers le code natif Tratra Flash (canal « tratra/flash ») : lecture du son « Ta – Tra – Tra ! » et de la vibration rythmée en
// respectant le mode du téléphone (silencieux, vibreur, Ne pas déranger), réglages Son / Vibration, retrait d'une alerte, action
// touchée sur une alerte (Accepter / Refuser / Voir). Isolé derrière [FlashNative] pour les tests (aucun code natif requis).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Action touchée sur une alerte système de nouvelle mission.
class FlashAction {
  const FlashAction(this.action, this.offerId);
  final String action; // accept | decline | view
  final int offerId;

  static FlashAction? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse('${raw['offer'] ?? ''}');
    final action = '${raw['action'] ?? ''}';
    if (id == null || id <= 0 || !const {'accept', 'decline', 'view'}.contains(action)) return null;
    return FlashAction(action, id);
  }
}

/// Ce que le téléphone a réellement joué (le mode silencieux et « Ne pas déranger » sont respectés).
class FlashPlayback {
  const FlashPlayback({this.played = false, this.vibrated = false, this.ringer = 'normal', this.dnd = false});
  final bool played;
  final bool vibrated;
  final String ringer; // normal | vibrate | silent
  final bool dnd;

  static FlashPlayback fromMap(Object? raw) {
    if (raw is! Map) return const FlashPlayback();
    return FlashPlayback(played: raw['played'] == true, vibrated: raw['vibrated'] == true, ringer: '${raw['ringer'] ?? 'normal'}', dnd: raw['dnd'] == true);
  }

  /// Explication à afficher quand rien (ou seulement la vibration) n'a été entendu.
  String? get explanation {
    if (dnd) return 'Mode « Ne pas déranger » actif : le téléphone reste silencieux.';
    if (ringer == 'silent') return 'Téléphone en mode silencieux : aucun son ni vibration.';
    if (ringer == 'vibrate') return 'Téléphone en mode vibreur : vibration seule.';
    return null;
  }
}

abstract class FlashNative {
  Future<FlashAction?> takeLaunchAction();
  Stream<FlashAction> get actions;
  Future<({bool sound, bool vibration})> prefs();
  Future<void> setPrefs({required bool sound, required bool vibration});
  Future<FlashPlayback> play(String sound, {bool withSound = true, bool withVibration = true});
  Future<void> stop();
  Future<void> cancel(int offerId);
}

class MethodChannelFlashNative implements FlashNative {
  MethodChannelFlashNative() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final a = FlashAction.fromMap(call.arguments);
        if (a != null) _actions.add(a);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('tratra/flash');
  final _actions = StreamController<FlashAction>.broadcast();

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<FlashAction?> takeLaunchAction() async => FlashAction.fromMap(await _call<Object>('takeLaunchAction'));

  @override
  Stream<FlashAction> get actions => _actions.stream;

  @override
  Future<({bool sound, bool vibration})> prefs() async {
    final m = await _call<Map>('getPrefs');
    return (sound: m?['sound'] != false, vibration: m?['vibration'] != false);
  }

  @override
  Future<void> setPrefs({required bool sound, required bool vibration}) => _call('setPrefs', {'sound': sound, 'vibration': vibration});

  @override
  Future<FlashPlayback> play(String sound, {bool withSound = true, bool withVibration = true}) async =>
      FlashPlayback.fromMap(await _call<Map>('play', {'sound': sound, 'withSound': withSound, 'withVibration': withVibration}));

  @override
  Future<void> stop() => _call('stop');

  @override
  Future<void> cancel(int offerId) => _call('cancel', {'offer': offerId});
}
