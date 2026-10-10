// Liens profonds des notifications : le serveur désigne l'objet, l'application ne plante jamais sur une donnée inattendue.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/deep_links.dart';

void main() {
  test('lien tratra:// avec identifiant', () {
    expect(parseDeepLink({'deeplink': 'tratra://booking/12'}), const DeepLink(DeepLinkKind.booking, id: 12));
    expect(parseDeepLink({'deeplink': 'tratra://mission/7'}), const DeepLink(DeepLinkKind.mission, id: 7));
    expect(parseDeepLink({'deeplink': 'tratra://conversation/5'}), const DeepLink(DeepLinkKind.conversation, id: 5));
  });

  test('liens sans identifiant', () {
    expect(parseDeepLink({'deeplink': 'tratra://reviews'}), const DeepLink(DeepLinkKind.reviews));
    expect(parseDeepLink({'deeplink': 'tratra://kyc'}).kind, DeepLinkKind.kyc);
    expect(parseDeepLink({'deeplink': 'tratra://notifications'}).kind, DeepLinkKind.notifications);
  });

  test('repli sur kind + id quand le lien est absent (valeurs textuelles FCM)', () {
    expect(parseDeepLink({'kind': 'booking', 'id': '33'}), const DeepLink(DeepLinkKind.booking, id: 33));
    expect(parseDeepLink({'kind': 'business_request', 'id': '4'}).kind, DeepLinkKind.businessRequest);
    expect(parseDeepLink({'kind': 'announcement', 'id': 9}), const DeepLink(DeepLinkKind.announcement, id: 9));
  });

  test('donnée vide, inconnue ou incohérente : centre de notifications, jamais d\'exception', () {
    const fallback = DeepLink(DeepLinkKind.notifications);
    expect(parseDeepLink(null), fallback);
    expect(parseDeepLink({}), fallback);
    expect(parseDeepLink({'deeplink': 'https://evil.example/booking/1'}), fallback); // lien externe ignoré
    expect(parseDeepLink({'deeplink': 'tratra://inconnu/3'}), fallback);
    expect(parseDeepLink({'deeplink': 'tratra://booking'}), fallback); // identifiant exigé
    expect(parseDeepLink({'deeplink': 'tratra://booking/abc'}), fallback);
    expect(parseDeepLink({'kind': 'mission'}), fallback);
  });

  test('le lien profond prime sur kind/id', () {
    expect(parseDeepLink({'deeplink': 'tratra://mission/8', 'kind': 'booking', 'id': '99'}), const DeepLink(DeepLinkKind.mission, id: 8));
  });
}
