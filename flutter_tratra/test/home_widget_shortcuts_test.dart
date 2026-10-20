// Widget d'accueil et raccourcis d'application : contenu MINIMAL et non sensible, destinations communes (liens profonds), sélection de
// l'onglet de l'espace à l'ouverture.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/services/home_widget_sync.dart';

Map<String, dynamic> _payload({bool provider = false, bool online = true, List<Map<String, dynamic>> upcoming = const []}) => {
      'user': {'id': 9, 'first_name': 'Serge', 'display_name': 'Serge O.'},
      'capabilities': {'client': true, 'provider': provider},
      'client': {'bookings': {'pending': 1, 'confirmed': 1, 'in_progress': 0, 'total': 3}},
      'provider': provider ? {'profile_id': 5, 'online': online, 'missions': {'pending': 3}} : null,
      'upcoming': upcoming,
      'unread': {'notifications': 1, 'messages': 4},
    };

void main() {
  test('contenu du widget : type, intitulé et date de la prochaine intervention, compteurs — rien de personnel', () {
    final d = DashData(_payload(provider: true, upcoming: [
      {'id': 7, 'role': 'handyman', 'title': 'Dépannage plomberie', 'status': 'confirmed', 'booking_date': '2026-10-21T09:30:00',
        'city': 'Cocody', 'counterpart': 'Awa K.'},
    ]));
    final c = widgetContent(d, DateTime(2026, 10, 20, 18, 5));
    expect(c['tw_signed_in'], true);
    expect(c['tw_next'], 'Mission : Dépannage plomberie · mer. 21 oct. à 09h30');
    expect(c['tw_missions'], '3 missions à traiter');
    expect(c['tw_unread'], '1 notification');
    expect(c['tw_status'], 'Disponible');
    expect(c['tw_updated'], 'Mis à jour à 18h05');
    final all = c.values.join(' ');
    expect(all, isNot(contains('Awa')));                // jamais le nom de l'autre partie
    expect(all, isNot(contains('Cocody')));             // ni le lieu
  });

  test('client sans intervention : texte neutre et réservations en cours', () {
    final c = widgetContent(DashData(_payload()), DateTime(2026, 10, 20, 8, 0));
    expect(c['tw_next'], 'Aucune intervention prévue.');
    expect(c['tw_missions'], '2 réservations en cours');
    expect(c['tw_status'], '');
  });

  test('raccourcis : quatre destinations, mêmes liens profonds que le widget et les notifications', () {
    expect(AppShortcuts.items.map((i) => i.localizedTitle), ['Nouvelle demande', 'Mes missions', 'Messages', 'Mon espace professionnel']);
    final kinds = [for (final i in AppShortcuts.items) parseDeepLink({'deeplink': i.type}).kind];
    expect(kinds, [DeepLinkKind.explore, DeepLinkKind.bookings, DeepLinkKind.messages, DeepLinkKind.pro]);
    expect(requiresSignIn(const DeepLink(DeepLinkKind.explore)), isFalse);       // explorer reste public
    expect(requiresSignIn(const DeepLink(DeepLinkKind.messages)), isTrue);
    expect(parseDeepLink({'deeplink': 'tratra://inconnu'}).kind, DeepLinkKind.notifications);
  });
}
