// Tratra Trust : badges cumulables, score expliqué et passeport — affichage fidèle à l'API, rien d'inventé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/artisan.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/screens/trust/passport_screen.dart';
import 'package:flutter_tratra/screens/trust/trust_widgets.dart';

Map<String, dynamic> _passport({int? score, List<String> badges = const ['VERIFIE']}) => {
      'profile_id': 3,
      'display_name': 'Awa K.',
      'photo': null,
      'commune': 'Cocody',
      'member_since': '2026-10-01T10:00:00Z',
      'identity': {'verified': true, 'verified_on': '2026-10-08T10:00:00Z', 'source': 'vérifié'},
      'badges': [for (final c in badges) {'code': c, 'label': c, 'since': '2026-10-08T10:00:00Z'}],
      'score': {
        'value': score,
        'confidence': score == null ? null : 'moyenne',
        'reason': score == null ? 'Pas encore assez d’activité mesurée pour publier un score (aucune pénalité).' : '',
        'note': 'Seules les composantes mesurables comptent : une donnée manquante n’est jamais comptée comme un zéro.',
        'components': [
          {'key': 'identity', 'label': 'Identité vérifiée (KYC)', 'available': true, 'ratio': 1.0, 'detail': 'Pièce d’identité contrôlée', 'source': 'vérifié', 'points': score == null ? null : 55.6, 'max_points': score == null ? null : 55.6},
          {'key': 'satisfaction', 'label': 'Satisfaction des clients', 'available': false, 'ratio': null, 'detail': 'Pas encore assez d’avis (1/3)', 'source': 'plateforme', 'points': null, 'max_points': null},
        ],
      },
      'skills': {
        'declared': [{'id': 1, 'name': 'Plomberie', 'slug': 'plomberie', 'source': 'déclaré'}],
        'certified': <dynamic>[],
      },
      'experience': {'years': 7, 'source': 'déclaré'},
      'missions': {'completed': 1, 'completed_window': 1, 'window_days': 365, 'source': 'plateforme'},
      'satisfaction': {'count': 1, 'average': 5.0, 'response_rate': 0.0, 'source': 'plateforme'},
      'punctuality': {'rate': null, 'sample': 1, 'on_time': 0, 'tolerance_minutes': 15, 'min_sample': 3, 'source': 'plateforme'},
      'reactivity': {'median_minutes': 0.0, 'sample': 4, 'min_sample': 3, 'source': 'plateforme'},
      'history': [
        {'code': 'VERIFIE', 'label': 'Vérifié', 'started_at': '2026-10-08T10:00:00Z', 'ended_at': null},
      ],
    };

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 4200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Widget _host(Widget child) => MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: child));

void main() {
  group('badges', () {
    test('codes connus uniquement, dans l’ordre d’affichage, sans doublon', () {
      expect(trustBadgeCodes([{'code': 'SUR'}, {'code': 'VERIFIE'}, {'code': 'INVENTE'}, {'code': 'EXPERT'}, {'code': 'SUR'}]),
          ['VERIFIE', 'EXPERT', 'SUR']);
      expect(trustBadgeCodes(null), isEmpty);
      expect(trustBadgeCodes('x'), isEmpty);
    });

    test('Artisan.fromJson lit badges et score ; absents = rien d’affiché', () {
      final a = Artisan.fromJson({'id': 3, 'display_name': 'Awa K.', 'badges': [{'code': 'VERIFIE'}, {'code': 'SUR'}], 'trust_score': 87.0});
      expect(a.trustBadges, ['VERIFIE', 'SUR']);
      expect(a.trustScore, 87);
      final b = Artisan.fromJson({'id': 4});
      expect(b.trustBadges, isEmpty);
      expect(b.trustScore, isNull);
    });

    test('Booking.fromJson : artisan et badges ACTUELS issus de l’API, jamais déduits', () {
      final b = Booking.fromJson({
        'id': 5,
        'status': 'confirmed',
        'client': 1,
        'handyman': 2,
        'service': 7,
        'service_detail': {
          'id': 7,
          'title': 'Plomberie',
          'artisan': {
            'id': 3,
            'display_name': 'Awa K.',
            'badges': [{'code': 'VERIFIE'}, {'code': 'SUR'}, {'code': 'INVENTE'}],
          },
        },
      });
      expect(b.artisanName, 'Awa K.');
      expect(b.artisanProfileId, '3');
      expect(b.artisanBadges, ['VERIFIE', 'SUR']);
      final none = Booking.fromJson({'id': 6, 'status': 'pending', 'client': 1, 'handyman': 2, 'service': 7});
      expect(none.artisanName, isNull);
      expect(none.artisanBadges, isEmpty);
    });

    testWidgets('score absent : aucune pastille ; présent : valeur exacte', (t) async {
      await t.pumpWidget(_host(const TratraTrustScorePill(null)));
      expect(find.textContaining('Confiance'), findsNothing);
      await t.pumpWidget(_host(const TratraTrustScorePill(79)));
      expect(find.text('Confiance 79/100'), findsOneWidget);
    });
  });

  group('formats', () {
    test('minutes, pourcentages et décimales françaises', () {
      expect(fmtMinutes(0.0), '< 1 min');
      expect(fmtMinutes(12.4), '12 min');
      expect(fmtMinutes(65), '1 h 05');
      expect(fmtMinutes(null), '—');
      expect(fmtPercent(0.923), '92 %');
      expect(fmtPercent(null), '—');
      expect(fmtDecimal(4.5), '4,5');
    });
  });

  group('passeport', () {
    testWidgets('sans score : motif honnête, composantes manquantes « sans pénalité », pas de 0 % inventé', (t) async {
      _tall(t);
      await t.pumpWidget(_host(PassportBody(passport: _passport())));
      expect(find.text('Awa K.'), findsOneWidget);
      expect(find.text('Vérifié'), findsWidgets);
      expect(find.textContaining('aucune pénalité'), findsOneWidget);
      expect(find.textContaining('non comptée, sans pénalité'), findsOneWidget);
      expect(find.text('0 %'), findsNothing); // 1 seule mission mesurée : le taux n'est pas publié
      expect(find.textContaining('Pas encore assez de missions mesurées (1/3)'), findsOneWidget);
      expect(find.text('< 1 min'), findsOneWidget);
    });

    testWidgets('avec score : anneau et points expliqués', (t) async {
      _tall(t);
      await t.pumpWidget(_host(PassportBody(passport: _passport(score: 79, badges: const ['VERIFIE', 'EXPERT', 'SUR']))));
      expect(find.byType(ScoreRing), findsOneWidget);
      expect(find.text('79'), findsOneWidget);
      expect(find.textContaining('55,6 / 55,6 pts'), findsOneWidget);
      expect(find.text('Expert'), findsOneWidget);
      expect(find.text('Sûr'), findsOneWidget);
    });
  });
}
