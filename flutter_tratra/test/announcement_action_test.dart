// Action d'une annonce : jamais d'URL autre que https, jamais d'écran inconnu, jamais d'exécution à l'aveugle.
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/announcement_action.dart';
import 'package:flutter_tratra/core/deep_links.dart';

void main() {
  test('aucune action : aucun bouton', () {
    expect(parseAnnouncementAction(null), isNull);
    expect(parseAnnouncementAction({'kind': 'none', 'value': ''}), isNull);
    expect(parseAnnouncementAction({'kind': 'link', 'value': ''}), isNull);
  });

  test('lien externe : https uniquement', () {
    final ok = parseAnnouncementAction({'kind': 'link', 'label': 'Découvrir', 'value': 'https://tratra.net/offre'});
    expect(ok, isA<OpenExternalLink>());
    expect((ok! as OpenExternalLink).uri.host, 'tratra.net');
    expect(ok.label, 'Découvrir');
    for (final bad in ['http://tratra.net', 'javascript:alert(1)', 'intent://scan#Intent;end', 'file:///etc/passwd', 'tel:+2250700000000', 'https://', '//tratra.net', 'tratra.net']) {
      expect(parseAnnouncementAction({'kind': 'link', 'value': bad}), isNull, reason: bad);
    }
  });

  test('libellé par défaut « Voir »', () {
    expect(parseAnnouncementAction({'kind': 'link', 'value': 'https://tratra.net'})!.label, 'Voir');
    expect(parseAnnouncementAction({'kind': 'link', 'label': '  ', 'value': 'https://tratra.net'})!.label, 'Voir');
  });

  test('écran de l’application : destinations connues uniquement', () {
    final reviews = parseAnnouncementAction({'kind': 'deeplink', 'label': 'Mes avis', 'value': 'reviews'});
    expect((reviews! as OpenAppScreen).link, const DeepLink(DeepLinkKind.reviews));
    final booking = parseAnnouncementAction({'kind': 'deeplink', 'value': 'booking/12'});
    expect((booking! as OpenAppScreen).link, const DeepLink(DeepLinkKind.booking, id: 12));
    final center = parseAnnouncementAction({'kind': 'deeplink', 'value': 'notifications'});
    expect((center! as OpenAppScreen).link.kind, DeepLinkKind.notifications);
    for (final bad in ['admin/1', 'settings', 'booking', '../secret']) {
      expect(parseAnnouncementAction({'kind': 'deeplink', 'value': bad}), isNull, reason: bad);
    }
  });

  test('type d’action inconnu : ignoré', () {
    expect(parseAnnouncementAction({'kind': 'script', 'value': 'https://tratra.net'}), isNull);
  });

  test('lien profond d’annonce : le push ouvre l’annonce désignée', () {
    expect(parseDeepLink({'deeplink': 'tratra://announcement/7'}), const DeepLink(DeepLinkKind.announcement, id: 7));
  });
}
