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

  test('destinations des annonces (registre central) : toutes reconnues, identifiant exigé pour une offre ou un métier', () {
    expect(parseDeepLink({'deeplink': 'tratra://service/40'}), const DeepLink(DeepLinkKind.service, id: 40));
    expect(parseDeepLink({'deeplink': 'tratra://category/3'}), const DeepLink(DeepLinkKind.category, id: 3));
    expect(parseDeepLink({'deeplink': 'tratra://service'}).kind, DeepLinkKind.notifications);
    expect(parseDeepLink({'deeplink': 'tratra://flash_order'}).kind, DeepLinkKind.flashOrder);
    expect(parseDeepLink({'deeplink': 'tratra://home'}).kind, DeepLinkKind.home);
    // Même liste que le serveur (handy/destinations.py, announcements/test_destinations_push.py : APP_KEYS).
    const serverKeys = {
      'home', 'explore', 'categories', 'category', 'services', 'service', 'search', 'urgent', 'flash_order', 'favorites', 'bookings',
      'messages', 'notifications', 'announcement', 'reviews', 'engagements', 'profile', 'addresses', 'kyc', 'pro', 'reputation', 'badge',
      'availability', 'replacements', 'business', 'booking', 'mission', 'conversation', 'contract', 'posting', 'business_request',
      'flash_offer', 'flash_request', 'trust_penalty',
    };
    expect(knownLinkKeys, serverKeys);
    for (final key in knownLinkKeys) {
      final link = parseDeepLink({'deeplink': 'tratra://$key/1'});
      expect(link.kind == DeepLinkKind.notifications, key == 'notifications', reason: key);
    }
  });

  test('écrans réservés : professionnels ou entreprises seulement', () {
    for (final k in [DeepLinkKind.mission, DeepLinkKind.availability, DeepLinkKind.flashOffer, DeepLinkKind.reputation, DeepLinkKind.badge,
      DeepLinkKind.replacements, DeepLinkKind.trustPenalty]) {
      expect(requiredRole(k), LinkRole.provider, reason: '$k');
    }
    expect(requiredRole(DeepLinkKind.business), LinkRole.business);
    expect(requiredRole(DeepLinkKind.businessRequest), LinkRole.business);
    for (final k in [DeepLinkKind.home, DeepLinkKind.service, DeepLinkKind.flashOrder, DeepLinkKind.kyc, DeepLinkKind.pro, DeepLinkKind.profile]) {
      expect(requiredRole(k), isNull, reason: '$k');
    }
  });
}
