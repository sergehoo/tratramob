// Espace utilisateur unifié : modèle du tableau de bord, accueil et navigation « Plus »
// pour un compte client seul et pour un compte client + artisan.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/route_observer.dart';
import 'package:flutter_tratra/screens/dashboard/pro_status.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/continuity/activities_controller.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/continuity/offline_queue.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
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
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

/// Messagerie et statuts : serveur injoignable dans ces scénarios (la barre des statuts reste masquée, l'accueil n'est pas dégradé).
final _offlineBase = BaseApi(client: MockClient((_) async => http.Response('{}', 503)));

Widget _host(DashData d, Widget child, {_FakeController? controller}) => MultiProvider(
      providers: [
        Provider<StatusApi>.value(value: StatusApi(_offlineBase)),
        Provider<MessagingApi>.value(value: MessagingApi(_offlineBase)),
        ChangeNotifierProvider<InboxController>.value(value: InboxController(_offlineBase, MessagingApi(_offlineBase))),
        ChangeNotifierProvider<DashboardController>.value(value: controller ?? _FakeController(d)),
        // Continuité : aucune activité en cours dans ces scénarios (le bandeau reste masqué).
        ChangeNotifierProvider<ActivitiesController>.value(value: ActivitiesController(fetch: (_) async => {})),
        ChangeNotifierProvider<OfflineQueue>.value(value: OfflineQueue(send: (_) async => 200)),
      ],
      child: MaterialApp(theme: TratraTheme.light(), navigatorObservers: [appRouteObserver], home: child),
    );

/// Synthèse d'éligibilité du serveur (handy/eligibility.py) pour un compte artisan.
Map<String, dynamic> _elig({
  bool authorized = false,
  bool complete = true,
  String kyc = 'approved',
  bool approved = false,
  int offers = 1,
  String? reason,
  List<Map<String, dynamic>> blockers = const [],
}) =>
    {
      'profile': {'complete': complete, 'done': complete ? 5 : 3, 'total': 5, 'items': []},
      'kyc': {'status': kyc, 'label': kyc, 'reason': reason, 'approved': kyc == 'approved'},
      'approval': {'approved': approved, 'label': ''},
      'publication': {'authorized': authorized, 'label': '', 'blockers': blockers},
      'offers': {'total': offers, 'active': offers, 'published': authorized ? offers : 0, 'inactive': 0, 'label': ''},
      'next_action': null,
    };

/// Compte artisan dont la liste de contrôle est à 7/7 (ou non), avec la synthèse d'éligibilité donnée.
DashData _pro(Map<String, dynamic> eligibility, {bool sevenOfSeven = true}) {
  final p = _payload(provider: true);
  final provider = Map<String, dynamic>.from(p['provider'] as Map);
  provider['publishable'] = eligibility['publication']['authorized'];
  provider['completion'] = {'percent': sevenOfSeven ? 100 : 71, 'done': sevenOfSeven ? 7 : 5, 'total': 7, 'items': [
    {'key': 'bio', 'label': 'Présentation', 'done': true},
    {'key': 'photo', 'label': 'Photo de profil', 'done': sevenOfSeven},
  ]};
  provider['eligibility'] = eligibility;
  return DashData({...p, 'provider': provider});
}

Future<void> _home(WidgetTester t, DashData d) async {
  t.view.physicalSize = const Size(900, 6000); // toute la liste de l'accueil construite (la carte est en bas)
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(_host(d, Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))));
  await t.pump();
}

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
    testWidgets('client seul : invitation à proposer un service, pas de gains', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload()), Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))));
      expect(find.textContaining('Bonjour, '), findsOneWidget);
      expect(find.text('Trouver un artisan'), findsOneWidget);
      expect(find.text('Proposer mes services'), findsOneWidget);
      expect(find.text('Réservations en cours'), findsOneWidget);
      expect(find.text('Avis à rédiger'), findsOneWidget);
      expect(find.text('Gains disponibles'), findsNothing);
      expect(find.text('Proposer un service'), findsOneWidget);
      expect(find.text('Donnez votre avis sur 1 prestation'), findsOneWidget);
    });

    testWidgets('compte mixte : indicateurs artisan, progression du profil et onglets', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload(provider: true)), Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))));
      expect(find.text('Gérer mes offres'), findsOneWidget);
      expect(find.text('Missions à traiter'), findsOneWidget);
      expect(find.text('Gains disponibles'), findsNothing); // fonctions financières désactivées (version Google Play)
      expect(find.text(formatFcfa(13350)), findsNothing);
      expect(find.text('Profil professionnel'), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-continue')), findsOneWidget);
      expect(find.text('Proposer un service'), findsNothing);
      await t.tap(find.text('Missions'));
      await t.pump();
      expect(find.text('Installation électrique'), findsWidgets);
    });
  });

  group('Accueil : carte du profil professionnel (statuts réels du serveur)', () {
    testWidgets('vérifié (publication autorisée) : plus de carte 7/7, badge « Vérifié » près du nom', (t) async {
      await _home(t, _pro(_elig(authorized: true, approved: true)));
      expect(find.byKey(const ValueKey('pro-card-hidden')), findsOneWidget);
      expect(find.text('7/7'), findsNothing);
      expect(find.text('Profil professionnel'), findsNothing);
      expect(find.byKey(const ValueKey('hero-verified')), findsOneWidget);
      expect(find.text('Vérifié'), findsOneWidget);
    });

    testWidgets('vérifié sans prestation : « Créer ma première prestation », sans la carte 7/7', (t) async {
      await _home(t, _pro(_elig(authorized: true, approved: true, offers: 0)));
      expect(find.text('Créer ma première prestation'), findsOneWidget);
      expect(find.text('7/7'), findsNothing);
      expect(find.byKey(const ValueKey('hero-verified')), findsOneWidget);
    });

    testWidgets('7/7 sans autorisation de publication : jamais « Vérifié » (la validation n’est pas déduite du 7/7)', (t) async {
      await _home(t, _pro(_elig(approved: true, blockers: [
        {'code': 'experience_minimum', 'label': 'Expérience minimale non atteinte : Nounou demande 2 ans', 'hint': 'Votre déclaration est conservée.',
          'action': {'code': 'edit_profile', 'label': 'Compléter mon profil'}},
      ])));
      expect(find.byKey(const ValueKey('hero-verified')), findsNothing);
      expect(find.text('7/7'), findsNothing);
      expect(find.text('Expérience minimale non atteinte : Nounou demande 2 ans'), findsOneWidget);
      expect(find.text('Compléter mon profil'), findsOneWidget);
    });

    testWidgets('pièce en revue : statut compact, aucun bouton d’action inutile', (t) async {
      await _home(t, _pro(_elig(kyc: 'pending'), sevenOfSeven: false));
      final card = find.byKey(const ValueKey('pro-status-kycPending'));
      expect(card, findsOneWidget);
      expect(find.text('Identité en cours de vérification'), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(TratraButton)), findsNothing);
      expect(find.byKey(const ValueKey('pro-progress')), findsNothing);
    });

    testWidgets('validation finale de l’équipe en attente : statut compact, sans bouton', (t) async {
      await _home(t, _pro(_elig(blockers: [{'code': 'approval_pending', 'label': 'Validation finale', 'hint': '', 'action': null}])));
      final card = find.byKey(const ValueKey('pro-status-approvalPending'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(TratraButton)), findsNothing);
      expect(find.byKey(const ValueKey('hero-verified')), findsNothing);
    });

    testWidgets('pièce refusée : la correction demandée et « Reprendre ma pièce »', (t) async {
      await _home(t, _pro(_elig(kyc: 'rejected', reason: 'Photo floue : reprenez le recto sans reflet.'), sevenOfSeven: false));
      expect(find.byKey(const ValueKey('pro-kyc-rejected')), findsOneWidget);
      expect(find.text('Photo floue : reprenez le recto sans reflet.'), findsOneWidget);
      expect(find.text('Reprendre ma pièce'), findsOneWidget);
    });

    testWidgets('profil incomplet : carte avec progression et « Continuer »', (t) async {
      await _home(t, _pro(_elig(complete: false, kyc: 'draft', blockers: [
        {'code': 'profile_incomplete', 'label': 'Profil incomplet : photo de profil', 'hint': '', 'action': {'code': 'edit_profile', 'label': 'Compléter mon profil'}},
      ]), sevenOfSeven: false));
      expect(find.byKey(const ValueKey('pro-progress')), findsOneWidget);
      expect(find.text('5/7'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
      expect(find.byKey(const ValueKey('hero-verified')), findsNothing);
    });

    test('même logique que le site : priorités des statuts', () {
      ProHomeKind kind(Map<String, dynamic> e) => proHomeState(_pro(e).provider!).kind;
      expect(kind(_elig(authorized: true, approved: true)), ProHomeKind.verified);
      expect(kind(_elig(authorized: true, approved: true, offers: 0)), ProHomeKind.firstOffer);
      expect(kind(_elig(kyc: 'rejected', complete: false)), ProHomeKind.kycRejected);
      expect(kind(_elig(complete: false, kyc: 'pending')), ProHomeKind.progress, reason: 'profil incomplet : il y a quelque chose à faire');
      expect(kind(_elig(kyc: 'draft')), ProHomeKind.progress);
      expect(kind(_elig(kyc: 'pending')), ProHomeKind.kycPending);
      expect(kind(_elig()), ProHomeKind.approvalPending);
    });

    testWidgets('retour sur l’accueil (identité, publication, profil) : statuts relus auprès du serveur', (t) async {
      _tall(t);
      final controller = _FakeController(_pro(_elig(kyc: 'pending')));
      await t.pumpWidget(_host(controller.data!, const DashboardScreen(), controller: controller));
      await t.pumpAndSettle();
      final before = controller.loads;
      t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Vérifier mon identité'))));
      await t.pumpAndSettle();
      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();
      expect(controller.loads, before + 1);
    });
  });

  group('Hors ligne au démarrage', () {
    testWidgets('tableau de bord indisponible : la dernière activité connue reste accessible, signalée hors ligne', (t) async {
      FlutterSecureStorage.setMockInitialValues({});
      _tall(t);
      var offline = false;
      final activities = ActivitiesController(
        retryBase: const Duration(hours: 1),
        fetch: (_) async {
          if (offline) throw Exception('réseau coupé');
          return {
            'server_time': '2026-10-10T10:30:00Z',
            'activities': [
              {'kind': 'contract', 'id': 1, 'role': 'client', 'status': 'active', 'status_label': 'En cours', 'version': 3, 'title': 'Gardiennage de nuit', 'counterpart': 'Moussa A.', 'city': 'Abidjan', 'active': true, 'deeplink': 'tratra://contract/1', 'resume_label': 'Voir mon contrat'}
            ],
            'primary': null,
          };
        },
      );
      await activities.bindUser('9');
      offline = true;
      await activities.refresh(force: true);
      final failing = _FakeController(DashData(_payload()))
        ..data = null
        ..error = 'Connexion impossible.';
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<DashboardController>.value(value: failing),
          ChangeNotifierProvider<ActivitiesController>.value(value: activities),
          ChangeNotifierProvider<OfflineQueue>.value(value: OfflineQueue(send: (_) async => 200)),
        ],
        child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))),
      ));
      expect(find.text('Tableau de bord indisponible'), findsOneWidget);
      expect(find.text('Gardiennage de nuit'), findsOneWidget);
      expect(find.text('Voir mon contrat'), findsOneWidget);
      expect(find.textContaining('Hors ligne'), findsWidgets);
      expect(find.text('Réessayer'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      activities.dispose(); // arrête la relance automatique programmée
    });

    test('session refusée par le serveur (401) : « session expirée », pas une panne à réessayer', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final c = DashboardController(DashboardApi(BaseApi(client: MockClient((_) async => http.Response('{"detail":"Token invalide"}', 401)))))..bindUser('9');
      await c.load();
      expect(c.sessionExpired, isTrue);
      expect(c.error, contains('session a expiré'));
      final down = DashboardController(DashboardApi(BaseApi(client: MockClient((_) async => http.Response('{}', 503)))))..bindUser('9');
      await down.load();
      expect(down.sessionExpired, isFalse);
    });

    testWidgets('session expirée : bouton « Se reconnecter » au lieu de l’impasse « Réessayer »', (t) async {
      final expired = _FakeController(DashData(_payload()))
        ..data = null
        ..sessionExpired = true
        ..error = 'Votre session a expiré. Reconnectez-vous pour retrouver votre espace.';
      final activities = ActivitiesController(fetch: (_) async => {});
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<DashboardController>.value(value: expired),
          ChangeNotifierProvider<ActivitiesController>.value(value: activities),
          ChangeNotifierProvider<OfflineQueue>.value(value: OfflineQueue(send: (_) async => 200)),
        ],
        child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: DashboardHome(onExplore: () {}, onMessages: () {}))),
      ));
      expect(find.text('Session expirée'), findsOneWidget);
      expect(find.byKey(const ValueKey('relogin')), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      activities.dispose();
    });
  });

  group('Navigation', () {
    testWidgets('raccourci ou widget : l’onglet demandé s’ouvre (Messages)', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload(provider: true)), const DashboardScreen()));
      await t.pump();
      dashboardTabRequest.value = 3;
      await t.pumpAndSettle();
      expect(dashboardTabRequest.value, isNull);                      // demande consommée
      expect(find.text('Messages'), findsWidgets);
      expect(find.text('Plus'), findsWidgets);
    });

    testWidgets('client seul : « Plus » propose Proposer un service, sans fonctions artisan', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload()), const DashboardScreen()));
      await t.tap(find.text('Plus'));
      await t.pumpAndSettle();
      expect(find.text('Proposer un service'), findsOneWidget);
      expect(find.text('Portefeuille'), findsNothing); // fonctions financières désactivées (version Google Play)
      expect(find.text('Avis'), findsOneWidget);
      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('Mes offres et missions'), findsNothing);
      expect(find.text('Vérifier mon identité'), findsNothing);
    });

    testWidgets('compte mixte : « Plus » ajoute Mes offres et missions, profil pro, identité et justificatifs', (t) async {
      _tall(t);
      await t.pumpWidget(_host(DashData(_payload(provider: true)), const DashboardScreen()));
      await t.tap(find.text('Plus'));
      await t.pumpAndSettle();
      expect(find.text('Mes offres et missions'), findsOneWidget);
      expect(find.text('Proposer un service'), findsNothing);
      expect(find.text('Profil professionnel'), findsOneWidget);
      expect(find.text('Vérifier mon identité'), findsOneWidget);       // une seule entrée : pièce d'identité + vérification faciale
      expect(find.text('Documents et justificatifs'), findsOneWidget);
    });
  });
}
