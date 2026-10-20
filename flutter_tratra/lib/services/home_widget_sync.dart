// lib/services/home_widget_sync.dart
//
// Widget d'accueil Android (android/app/src/main/kotlin/com/tratra/TratraWidgetProvider.kt) et raccourcis d'application (appui long
// sur l'icône, Android et iOS). Le widget n'affiche que des données MINIMALES et non sensibles : type et intitulé de la prochaine
// intervention avec sa date, nombres de missions et de notifications, disponibilité — jamais un nom, une adresse, un montant ni le texte
// d'un message. Déconnexion ou session expirée : tout est effacé et le widget invite à se connecter.
// Actualisation : à chaque synchronisation de l'espace (aucun appel réseau depuis le widget).
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:quick_actions/quick_actions.dart';

import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

const _provider = 'com.tratra.TratraWidgetProvider';

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _mobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];

String _two(int v) => v.toString().padLeft(2, '0');

/// Contenu du widget (pur, testable) : clé → texte.
Map<String, Object> widgetContent(DashData d, DateTime now) {
  final next = d.upcoming.isEmpty ? null : d.upcoming.first;
  String? when;
  final at = next?.bookingDate?.toLocal();
  if (at != null) when = '${_days[at.weekday - 1]} ${at.day} ${_months[at.month - 1]} à ${_two(at.hour)}h${_two(at.minute)}';
  final p = d.provider;
  final pending = p?.pending ?? 0;
  String plural(int n, String one, String many) => '$n ${n > 1 ? many : one}';
  return {
    'tw_signed_in': true,
    'tw_next': next == null
        ? 'Aucune intervention prévue.'
        : '${next.isMission ? 'Mission' : 'Réservation'} : ${next.title}${when == null ? '' : ' · $when'}',
    'tw_missions': p != null ? plural(pending, 'mission à traiter', 'missions à traiter') : plural(d.bookingsActive, 'réservation en cours', 'réservations en cours'),
    'tw_unread': plural(d.unreadNotifications, 'notification', 'notifications'),
    'tw_status': p == null ? '' : (p.online ? 'Disponible' : 'Indisponible'),
    'tw_updated': 'Mis à jour à ${_two(now.hour)}h${_two(now.minute)}',
  };
}

class HomeWidgetSync {
  HomeWidgetSync._();

  static Future<void> update(DashData d, {DateTime? now}) async {
    if (!_android) return;
    try {
      for (final e in widgetContent(d, now ?? DateTime.now()).entries) {
        await HomeWidget.saveWidgetData<Object>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (_) {
      // widget absent ou plateforme sans prise en charge : sans conséquence
    }
  }

  /// Déconnexion / session expirée : plus aucune donnée du compte sur l'écran d'accueil.
  static Future<void> clear() async {
    if (!_android) return;
    try {
      await HomeWidget.saveWidgetData<bool>('tw_signed_in', false);
      for (final k in const ['tw_next', 'tw_missions', 'tw_unread', 'tw_status', 'tw_updated']) {
        await HomeWidget.saveWidgetData<String>(k, null);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (_) {}
  }

  /// Liens ouverts depuis le widget (appli fermée puis lancée, ou déjà ouverte).
  static Future<Uri?> initialLink() async {
    if (!_android) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  static Stream<Uri?> get clicks => _android ? HomeWidget.widgetClicked : const Stream.empty();
}

/// Raccourcis d'application (appui long sur l'icône) : mêmes destinations que le site installé (PWA).
class AppShortcuts {
  AppShortcuts._();

  static const items = [
    ShortcutItem(type: 'tratra://explore', localizedTitle: 'Nouvelle demande', icon: 'ic_shortcut_request'),
    ShortcutItem(type: 'tratra://bookings', localizedTitle: 'Mes missions', icon: 'ic_shortcut_missions'),
    ShortcutItem(type: 'tratra://messages', localizedTitle: 'Messages', icon: 'ic_shortcut_messages'),
    ShortcutItem(type: 'tratra://pro', localizedTitle: 'Mon espace professionnel', icon: 'ic_shortcut_pro'),
  ];

  static void init(void Function(String link) onOpen) {
    if (!_mobile) return;
    try {
      const quick = QuickActions();
      quick.initialize(onOpen);
      quick.setShortcutItems(items);
    } catch (_) {}
  }
}
