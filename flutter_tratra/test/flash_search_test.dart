// Tratra Flash, recherche façon VTC (application) : carte et rayon courant, phases explicites, compteurs exacts, accord pour élargir
// au-delà de 30 km, propositions (choix confirmé, contre-offre), annulation toujours accessible, état en direct par WebSocket (doublons et
// messages en retard ignorés), reprise par l'API, délai maximal (jamais de chargement infini), contre-offre côté professionnel.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_client.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_native.dart';
import 'package:flutter_tratra/flash/flash_search.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

class _Native implements FlashNative {
  @override
  Future<FlashAction?> takeLaunchAction() async => null;
  @override
  Stream<FlashAction> get actions => const Stream.empty();
  @override
  Future<({bool sound, bool vibration})> prefs() async => (sound: true, vibration: true);
  @override
  Future<void> setPrefs({required bool sound, required bool vibration}) async {}
  @override
  Future<FlashPlayback> play(String sound, {bool withSound = true, bool withVibration = true}) async => const FlashPlayback();
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel(int offerId) async {}
}

Map<String, dynamic> search({String phase = 'search', int seq = 10, int radius = 5000, int contacted = 3, int responses = 1, int proposals = 0,
        bool consent = false}) =>
    {
      'seq': seq, 'phase': phase, 'phase_label': {'search': 'Recherche en cours', 'extension': 'Élargir la recherche ?', 'proposals': 'Propositions reçues',
          'selection': 'Choisissez une proposition', 'confirmed': 'Confirmé', 'cancelled': 'Annulée'}[phase], 'progressive': true,
      'radius_m': radius, 'radius_label': radius >= 1000 ? '${radius ~/ 1000} km' : '$radius m',
      'steps_m': [100, 500, 1000, 5000, 10000, 30000], 'next_step_in': 12,
      'far': {'threshold_km': 30, 'allowed': false, 'needs_consent': consent, 'possible': true, 'available_beyond': consent ? 2 : null},
      'counts': {'eligible': 4, 'contacted': contacted, 'pending': contacted - responses, 'responses': responses, 'proposals': proposals,
          'declined': 0, 'no_answer': 0},
    };

Map<String, dynamic> request({String status = 'searching', String mode = 'firm', Map<String, dynamic>? s, List<Map<String, dynamic>> quotes = const [],
        int version = 1}) =>
    {
      'id': 9, 'status': status, 'status_label': {'searching': 'Recherche en cours', 'quoting': 'Devis à choisir', 'assigned': 'Attribuée',
          'cancelled': 'Annulée par le client'}[status], 'mode': mode, 'matching': 'auto', 'category': {'id': 3, 'name': 'Peinture'},
      'commune': 'Cocody', 'when_label': 'Maintenant', 'amount_label': mode == 'firm' ? '15 000 FCFA' : 'Sur devis', 'version': version,
      'search': s ?? search(), 'center': {'lat': 5.36, 'lng': -3.99}, 'can_cancel': const {'searching', 'quoting'}.contains(status),
      'can_switch': false, 'can_relaunch': false, 'can_extend': (s ?? search())['far']['needs_consent'],
      if (mode == 'quote') 'quotes': quotes,
    };

Map<String, dynamic> quote(int offer, int amount, {String status = 'quoted'}) => {
      'offer': offer, 'amount': amount, 'amount_label': '$amount FCFA', 'message': '', 'status': status, 'status_label': status,
      'distance_km': 1.2, 'counter_amount': status == 'countered' ? 20000 : null, 'counter_label': status == 'countered' ? '20 000 FCFA' : null,
      'can_choose': true, 'can_counter': status == 'quoted', 'pro': {'id': offer + 100, 'name': 'Pro $offer', 'rating': 4.5, 'reviews': 8, 'trust_score': 80},
    };

class Server {
  Server(this.current);
  Map<String, dynamic> current;
  final posts = <String, Map<String, dynamic>>{};
  final keys = <String>[];
  int gets = 0;
  Completer<void>? hang;
  late final client = MockClient((r) async {
    if (hang != null) await hang!.future;
    if (r.method == 'GET' && r.url.path.endsWith('/flash/requests/9/')) {
      gets++;
      return _json(current);
    }
    if (r.method == 'POST') {
      posts[r.url.path] = r.body.isEmpty ? {} : (jsonDecode(r.body) as Map).cast<String, dynamic>();
      keys.add(r.headers['Idempotency-Key'] ?? '');
      if (r.url.path.endsWith('/cancel/')) return _json(current = request(status: 'cancelled', s: search(phase: 'cancelled')));
      if (r.url.path.endsWith('/extend/')) return _json(current = request(s: search(radius: 50000)));
      if (r.url.path.contains('/counter/')) {
        return _json(current = request(status: 'quoting', mode: 'quote', s: search(phase: 'selection', proposals: 2),
            quotes: [quote(31, 25000, status: 'countered'), quote(32, 28000)]));
      }
      if (r.url.path.endsWith('/accept/')) return _json(current = request(status: 'assigned', s: search(phase: 'confirmed'), version: 3));
    }
    return _json({}, 404);
  });
}

Future<Server> pump(WidgetTester t, Server s, {Duration timeout = const Duration(seconds: 15)}) async {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final base = BaseApi(client: s.client);
  final c = FlashController(api: FlashApi(base, timeout: timeout), native: _Native(), navigatorKey: GlobalKey<NavigatorState>(),
      isAuthenticated: () => true);
  await t.pumpWidget(MultiProvider(
    providers: [Provider<BaseApi>.value(value: base), ChangeNotifierProvider<FlashController>.value(value: c)],
    child: MaterialApp(theme: TratraTheme.light(), home: const FlashRequestScreen(requestId: 9)),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  return s;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'acc'});
    FlashSearchMap.tiles = false;
  });

  testWidgets('recherche : carte et rayon courant, phase explicite, compteurs exacts, annulation confirmée toujours accessible', (t) async {
    final s = await pump(t, Server(request()));
    expect(find.byKey(const ValueKey('flash-map')), findsOneWidget);
    expect(find.text('Rayon 5 km'), findsOneWidget);
    expect(find.text('Recherche en cours'), findsWidgets);
    expect(t.widget<Text>(find.byKey(const ValueKey('flash-count-eligible'))).data, '4');
    expect(t.widget<Text>(find.byKey(const ValueKey('flash-count-contacted'))).data, '3');
    expect(t.widget<Text>(find.byKey(const ValueKey('flash-count-responses'))).data, '1');
    expect(find.byKey(const ValueKey('flash-count-proposals')), findsNothing);              // mode Immédiat
    await t.tap(find.byKey(const ValueKey('flash-request-cancel')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Annuler la demande ?'), findsOneWidget);                             // confirmation exigée
    await t.tap(find.text('Annuler la demande'));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.posts.keys, contains('/handy/flash/requests/9/cancel/'));
    expect(s.keys.last, 'flash-cancel-9');
    expect(find.byKey(const ValueKey('flash-request-cancel')), findsNothing);
    expect(find.text('Annulée'), findsWidgets);
  });

  testWidgets('au-delà de 30 km : rien sans l’accord du client, puis la recherche reprend plus loin', (t) async {
    final s = await pump(t, Server(request(s: search(phase: 'extension', radius: 30000, consent: true))));
    expect(find.text('Élargir au-delà de 30 km ?'), findsOneWidget);
    expect(find.textContaining('2 professionnels disponibles plus loin'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flash-extend')));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.posts.keys, contains('/handy/flash/requests/9/extend/'));
    expect(find.byKey(const ValueKey('flash-extend-card')), findsNothing);
    expect(find.text('Rayon 50 km'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-extension-banner')), findsOneWidget);           // extension visible
    await t.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('flash-extension-banner')), findsNothing);
  });

  testWidgets('propositions : contre-offre plus basse (contrôlée), puis choix confirmé explicitement', (t) async {
    final s = await pump(t, Server(request(status: 'quoting', mode: 'quote', s: search(phase: 'selection', proposals: 2),
        quotes: [quote(31, 30000), quote(32, 28000)])));
    expect(find.text('Choisissez une proposition'), findsWidgets);
    expect(t.widget<Text>(find.byKey(const ValueKey('flash-count-proposals'))).data, '2');
    await t.tap(find.byKey(const ValueKey('flash-counter-31')));
    await t.pumpAndSettle();
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('flash-counter-amount')), matching: find.byType(TextField)), '30000');
    await t.tap(find.byKey(const ValueKey('flash-counter-send')));
    await t.pumpAndSettle();
    expect(find.textContaining('Proposez moins de'), findsOneWidget);                       // pas une contre-offre : refusée sur place
    expect(s.posts, isEmpty);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('flash-counter-amount')), matching: find.byType(TextField)), '25000');
    await t.tap(find.byKey(const ValueKey('flash-counter-send')));
    await t.pumpAndSettle();
    expect(s.posts['/handy/flash/requests/9/quotes/31/counter/'], {'amount': 25000});
    expect(find.byKey(const ValueKey('flash-countered-31')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flash-choose-32')));
    await t.pumpAndSettle();
    expect(find.text('Choisir Pro 32 ?'), findsOneWidget);                                // choix explicite, confirmé
    await t.tap(find.text('Confirmer ce choix'));
    await t.pumpAndSettle();
    expect(s.posts.keys, contains('/handy/flash/requests/9/quotes/32/accept/'));
    expect(find.text('Confirmé'), findsWidgets);
  });

  testWidgets('temps réel : état et compteurs par WebSocket, doublons ignorés, nouvelle version relue par l’API', (t) async {
    final s = Server(request());
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: s.client)), requestId: 9, events: events.stream, observeLifecycle: false);
    addTearDown(live.dispose);
    await live.start();
    expect(s.gets, 1);
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'searching', 'version': 1,
        'search': search(seq: 12, radius: 10000, contacted: 5, responses: 1)}));
    await t.pump();
    expect(live.search.radiusM, 10000);
    expect(live.search.count('contacted'), 5);
    expect(s.gets, 1, reason: 'mêmes réponses, même version : rien à relire');
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'searching', 'version': 1,
        'search': search(seq: 11, radius: 5000)}));                                         // arrivé en retard
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 8, 'search': search(seq: 99)}));   // autre demande
    await t.pump();
    expect(live.search.radiusM, 10000);
    expect(s.gets, 1);
    s.current = request(status: 'assigned', s: search(phase: 'confirmed', seq: 20), version: 2);
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'assigned', 'version': 2,
        'search': search(phase: 'confirmed', seq: 20)}));
    await t.pump();
    await t.pump();
    expect(s.gets, 2);                                                                     // professionnel retenu : détail relu
    expect(live.status, 'assigned');
    expect(live.isOpen, isFalse);
  });

  testWidgets('réseau bloqué : délai maximal puis message et « Réessayer », jamais de chargement infini', (t) async {
    final server = Server(request())..hang = Completer<void>();
    await pump(t, server, timeout: const Duration(milliseconds: 200));
    expect(find.text('Chargement de votre demande…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('flash-load-error')), findsOneWidget);
    server.hang!.complete();
    server.hang = null;
    await t.tap(find.byKey(const ValueKey('flash-retry')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('flash-map')), findsOneWidget);
  });

  testWidgets('professionnel : la contre-offre du client s’accepte (mission confirmée) avec une clé stable', (t) async {
    final posts = <String>[];
    Map<String, dynamic> offer(String status) => {
          'kind': 'flash_offer', 'id': 7, 'request': 3, 'mode': 'quote', 'category': 'Peinture', 'zone': 'Cocody', 'when_label': 'Maintenant',
          'immediate': '1', 'amount': '', 'amount_label': 'Sur devis', 'expires_at': '2026-11-10T20:00:00+00:00', 'distance_km': '1.2',
          'status': status, 'seconds_left': 0, 'description': '', 'why': const [], 'quote_amount': 30000,
          'client_reputation': const {'count': 0, 'average': null, 'public': false}, 'decline_reasons': const [],
          if (status == 'countered') 'counter': {'amount': 25000, 'amount_label': '25 000 FCFA', 'seconds_left': 240},
          if (status == 'accepted') ...{'address': 'Rue 1', 'client_name': 'Awa', 'booking': 55},
        };
    var current = offer('countered');
    final client = MockClient((r) async {
      if (r.method == 'POST') {
        posts.add('${r.url.path} ${r.headers['Idempotency-Key']}');
        return _json(current = offer('accepted'));
      }
      return _json(current);
    });
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final key = GlobalKey<NavigatorState>();
    final c = FlashController(api: FlashApi(BaseApi(client: client)), native: _Native(), navigatorKey: key, isAuthenticated: () => true);
    await t.pumpWidget(ChangeNotifierProvider<FlashController>.value(
        value: c, child: MaterialApp(navigatorKey: key, theme: TratraTheme.light(), home: const Scaffold())));
    unawaited(c.present(7));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Contre-offre du client : 25 000 FCFA'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-counter-decline')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flash-counter-accept')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(posts, ['/handy/flash/offers/7/counter/accept/ flash-counter-accept-7']);
    expect(find.byKey(const ValueKey('flash-accepted')), findsOneWidget);
  });
}
