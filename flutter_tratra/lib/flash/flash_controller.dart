// lib/flash/flash_controller.dart
//
// Réception Tratra Flash dans l'application :
//  * push « new_mission » reçu application OUVERTE → écran Tratra Flash (une seule fois par proposition, une à la fois) avec la
//    sonnerie et la vibration synchronisées (réglages Son / Vibration respectés, mode du téléphone respecté) ;
//  * push « flash_closed » → l'alerte s'arrête et l'écran affiche que la mission n'est plus disponible ;
//  * action touchée sur l'alerte système (Accepter / Refuser / Voir) → exécutée avec la session de l'application ;
//  * application fermée : c'est le code natif qui affiche l'alerte (FlashMessageReceiver) — jamais deux sons pour un même message.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_native.dart';
import 'package:flutter_tratra/flash/flash_offer_screen.dart';

class FlashController extends ChangeNotifier {
  FlashController({required this.api, required this.native, required this.navigatorKey, required this.isAuthenticated});

  final FlashApi api;
  final FlashNative native;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool Function() isAuthenticated;

  bool soundOn = true;
  bool vibrationOn = true;
  int? _showing;
  final List<int> _queue = [];
  final Set<int> _seen = {};
  final Set<String> _handled = {};

  /// Propositions fermées par le serveur (attribuées à un autre, expirées, annulées) : l'écran ouvert se met à jour.
  final ValueNotifier<Set<int>> closedOffers = ValueNotifier<Set<int>>(<int>{});
  StreamSubscription<FlashAction>? _actions;
  bool _started = false;

  int? get showing => _showing;

  /// Au démarrage (session connue) : réglages, actions des alertes, action qui a lancé l'application.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final p = await native.prefs();
    soundOn = p.sound;
    vibrationOn = p.vibration;
    _actions = native.actions.listen(handleAction);
    final launch = await native.takeLaunchAction();
    if (launch != null) await handleAction(launch);
    notifyListeners();
  }

  Future<void> setPrefs({bool? sound, bool? vibration}) async {
    soundOn = sound ?? soundOn;
    vibrationOn = vibration ?? vibrationOn;
    await native.setPrefs(sound: soundOn, vibration: vibrationOn);
    notifyListeners();
  }

  /// Message reçu application ouverte. Vrai s'il relève de Tratra Flash (le bandeau générique n'est alors pas affiché).
  bool handlePush(Map<String, dynamic> data) {
    final t = '${data['t'] ?? ''}';
    if (t == 'flash_closed') {
      final id = int.tryParse('${data['offer'] ?? ''}');
      if (id != null) markClosed(id);
      return true;
    }
    if (t != 'new_mission') return false;
    final id = int.tryParse('${data['id'] ?? ''}');
    if (id == null || !isAuthenticated()) return true;
    unawaited(present(id, ring: true));
    return true;
  }

  void markClosed(int offerId) {
    closedOffers.value = {...closedOffers.value, offerId};
    _queue.remove(offerId);
    if (_showing == offerId) unawaited(native.stop());
    unawaited(native.cancel(offerId));
  }

  /// Action touchée sur l'alerte système.
  Future<void> handleAction(FlashAction a) async {
    if (!isAuthenticated()) return;
    if (!_handled.add('${a.action}:${a.offerId}')) return;   // même action remise deux fois (lancement à froid) : une seule exécution
    await native.cancel(a.offerId);
    if (a.action == 'decline') {
      String text;
      try {
        await api.decline(a.offerId);
        text = 'Refus enregistré. Aucune conséquence sur votre réputation.';
      } on FlashApiError catch (e) {
        text = e.message;
      } catch (_) {
        text = 'Connexion impossible : le refus n’a pas été envoyé.';
      }
      _snack(text);
      return;
    }
    await present(a.offerId, initialAction: a.action == 'accept' ? 'accept' : null);
  }

  void _snack(String text) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  /// Ouvre l'écran Tratra Flash d'une proposition (sans doublon ; une proposition à la fois, les suivantes attendent).
  Future<void> present(int offerId, {bool ring = false, String? initialAction}) async {
    if (_showing == offerId) return;
    if (_showing != null) {
      if (!_queue.contains(offerId)) _queue.add(offerId);
      return;
    }
    if (ring && _seen.contains(offerId)) return;   // même push reçu deux fois : une seule alerte
    _seen.add(offerId);
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _showing = offerId;
    notifyListeners();
    try {
      await nav.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        settings: RouteSettings(name: 'flash-offer-$offerId'),
        builder: (_) => FlashOfferScreen(offerId: offerId, controller: this, ring: ring, initialAction: initialAction),
      ));
    } finally {
      await native.stop();
      _showing = null;
      notifyListeners();
      if (_queue.isNotEmpty) unawaited(present(_queue.removeAt(0), ring: true));
    }
  }

  /// Sonnerie + vibration de l'écran Tratra Flash (réglages et mode du téléphone respectés).
  Future<FlashPlayback> ring() => native.play('tratra_flash', withSound: soundOn, withVibration: vibrationOn);

  Future<void> silence(int offerId) async {
    await native.stop();
    await native.cancel(offerId);
  }

  @override
  void dispose() {
    _actions?.cancel();
    closedOffers.dispose();
    super.dispose();
  }
}
