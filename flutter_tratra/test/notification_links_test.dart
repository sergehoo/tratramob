// Notifications construites par l'application (annonces avec image) : seul un lien tratra:// bien formé est remis à la navigation ;
// titre et texte d'un message de DONNÉES repris pour le bandeau affiché application ouverte.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/notification_links.dart';
import 'package:flutter_tratra/services/push_service.dart';

void main() {
  test('lien touché : tratra:// uniquement, identifiant d\'annonce facultatif', () {
    expect(NotificationTap.fromMap({'link': 'tratra://service/40', 'announcement': 7, 'nid': 3}),
        const NotificationTap('tratra://service/40', announcementId: 7));
    expect(NotificationTap.fromMap({'link': 'tratra://flash_order', 'announcement': 0}), const NotificationTap('tratra://flash_order'));
    for (final bad in ['https://evil.example', 'javascript:alert(1)', 'tratra://service/40?x=1', 'tratra://../kyc', 'tratra://', '']) {
      expect(NotificationTap.fromMap({'link': bad, 'announcement': 1}), isNull, reason: bad);
    }
    expect(NotificationTap.fromMap(null), isNull);
    expect(NotificationTap.fromMap('tratra://home'), isNull);
  });

  test('message de données : titre et texte pris dans les données ; notification classique inchangée', () {
    final data = pushMessageFrom(data: {'t': 'announcement', 'title': 'Une réparation ?', 'body': 'Publiez votre besoin.'});
    expect(data.title, 'Une réparation ?');
    expect(data.body, 'Publiez votre besoin.');
    final classic = pushMessageFrom(title: 'Réservation', body: 'Confirmée', data: {'title': 'autre'});
    expect(classic.title, 'Réservation');
    expect(classic.body, 'Confirmée');
    expect(pushCapabilities, ['flash1', 'rich1']);
  });
}
