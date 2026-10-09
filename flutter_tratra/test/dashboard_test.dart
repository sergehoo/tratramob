// Espace utilisateur unifié : modèle du tableau de bord, accueil et navigation « Plus »
// pour un compte client seul et pour un compte client + artisan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_home.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_screen.dart';
import 'package:flutter_tratra/screens/worker/dashboard/worker_ui.dart' show formatFcfa;

Map<String, dynamic> _item(int id, String role, {String status = 'confirmed'}) => {
      'id': id,
      'role': role,
      'title': role == 'client' ? 'Plomberie à domicile' : 'Installation électrique',
      'category': 'Plomberie',
      'status': status,
      'booking_date': '2026-10-12T09:00:00Z',
      'city': 'Abidjan',
      'counterpart': 'Awa K.',
    };

Map<String, dynamic> _payload({bool provider = false}) => {
      'user': {'id': 9, 'first_name': 'Serge', 'display_name': 'Serge O.', 'is_verified': true, 'user_type': 'client'},
      'capabilities': {'client': true, 'provider': provider, 'publishable': false, 'company': false},
      'client': {
        'bookings': {'pending': 1, 'confirmed': 1, 'in_progress': 0, 'completed': 2, 'cancelled': 0, 'total': 4},
        'next_bookings': [_item(1, 'client')],
        'recent_bookings': [_item(1, 'client'), _item(2, 'client', status: 'completed')],
        'reviews_to_write': 1,
      },
      'provider': provider
          ? {
              'profile_id': 5,
              'online': false,
              'publishable': false,
              'completion': {
                'percent': 29,
                'done': 2,
                'total': 7,
                'items': [
                  {'key': 'bio', 'label': 'Présentation', 'done': true},
                  {'key': 'kyc', 'label': 'Pièce d’identité vérifiée', 'done': false},
                ],
              },
              'kyc': {'status': 'none', 'rejection_reason': null},
              'services': {'active': 1, 'total': 2},
              'missions': {'pending': 2, 'confirmed': 1, 'in_progress': 1, 'completed': 3, 'cancelled': 0, 'total': 7},
              'earnings': {'available': '13350.00', 'currency': 'XOF'},
              'next_missions': [_item(7, 'handyman')],
              'recent_missions': [_item(7, 'handyman')],
            }
          : null,
      'upcoming': [_item(1, 'client'), if (provider) _item(7, 'handyman')],
      'reviews': {'received_count': 0, 'received_average': null, 'to_write': 1},
      'unread': {'notifications': 3, 'messages': 2},
      'actions': [
        {'key': 'reviews_to_write', 'severity': 'info', 'target': 'reviews', 'title': 'Donnez votre avis sur 1 prestation', 'description': 'Votre retour aide.'},
        {'key': 'weird', 'severity': 'warning', 'target': 'inconnu-futur', 'title': 'Action future', 'description': ''},
      ],
    };

class _FakeController extends DashboardController {
  _FakeController(DashData d) : super(DashboardApi(BaseApi())) {
    data = d;
  }
}

Widget _host(DashData d, Widget child) => ChangeNotifierProvider<DashboardController>.value(
      value: _FakeController(d),
      child: MaterialApp(theme: TratraTheme.light(), home: child),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  group('DashData', () {
    test('compte client seul : aucun bloc artisan', () {
      final d = DashData(_payload());
      expect(d.isProvider, isFalse);
      expect(d.provider, isNull);
      expect(d.greeting, 'Serge');
      expect(d.bookingsActive, 2);
      expect(d.bookingsCompleted, 2);
      expect(d.unreadMessages, 2);
      expect(d.unreadNotifications, 3);
    });

    test('compte mixte : bloc artisan, gains et progression réels', () {
      final d = DashData(_payload(provider: true));
      final p = d.provider!;
      expect(d.isProvider, isTrue);
      expect(p.pending, 2);
      expect(p.earnings, 13350);
      expect(p.done, 2);
      expect(p.total, 7);
      expect(p.kycStatus, 'none');
      expect(p.checklist.where((i) => !i.done).map((i) => i.key), ['kyc']);
      expect(d.upcoming.where((i) => i.isMission), hasLength(1));
    });

    test('cible d’action inconnue → unknown (pas de plantage)', () {
      final d = DashData(_payload());
      expect(d.actions.map((a) => a.target), [DashTarget.reviews, DashTarget.unknown]);
    });

    test('tolère un payload partiel', () {
      final d = DashData(<String, dynamic>{});
      expect(d.displayName, 'Membre Tratra');
      expect(d.upcoming, isEmpty);
      expect(d.provider, isNull);
    });
  });

  test('le contrôleur est vidé quand le compte change', () async {
    final c = _FakeController(DashData(_payload()));
    c.bindUser('9');
    c.bindUser('9');
    expect(c.data, isNull);
  });

  group('Accueil', () {
    testWidgets('client seul : invitation à devenir artisan, pas de gains', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload()), Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))));
      expect(find.textContaining('Bonjour, '), findsOneWidget);
      expect(find.text('Trouver un artisan'), findsOneWidget);
      expect(find.text('Proposer mes services'), findsOneWidget);
      expect(find.text('Réservations en cours'), findsOneWidget);
      expect(find.text('Avis à rédiger'), findsOneWidget);
      expect(find.text('Gains disponibles'), findsNothing);
      expect(find.text('Devenir artisan sur Tratra'), findsOneWidget);
      expect(find.text('Donnez votre avis sur 1 prestation'), findsOneWidget);
    });

    testWidgets('compte mixte : indicateurs artisan, progression du profil et onglets', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload(provider: true)), Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))));
      expect(find.text('Gérer mes services'), findsOneWidget);
      expect(find.text('Missions à traiter'), findsOneWidget);
      expect(find.text('Gains disponibles'), findsOneWidget);
      expect(find.text(formatFcfa(13350)), findsOneWidget);
      expect(find.text('Profil professionnel'), findsOneWidget);
      expect(find.text('Aucun document déposé'), findsOneWidget);
      expect(find.text('Devenir artisan sur Tratra'), findsNothing);
      await t.tap(find.text('Missions'));
      await t.pump();
      expect(find.text('Installation électrique'), findsWidgets);
    });
  });

  group('Navigation', () {
    testWidgets('client seul : « Plus » propose Proposer un service, sans fonctions artisan', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload()), const DashboardScreen()));
      await t.tap(find.text('Plus'));
      await t.pumpAndSettle();
      expect(find.text('Proposer un service'), findsOneWidget);
      expect(find.text('Portefeuille'), findsOneWidget);
      expect(find.text('Avis'), findsOneWidget);
      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('Mes prestations'), findsNothing);
      expect(find.text('Vérification d’identité (KYC)'), findsNothing);
    });

    testWidgets('compte mixte : « Plus » ajoute Mes prestations, profil pro et KYC', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload(provider: true)), const DashboardScreen()));
      await t.tap(find.text('Plus'));
      await t.pumpAndSettle();
      expect(find.text('Mes prestations'), findsOneWidget);
      expect(find.text('Proposer un service'), findsNothing);
      expect(find.text('Profil professionnel'), findsOneWidget);
      expect(find.text('Vérification d’identité (KYC)'), findsOneWidget);
    });
  });
}
