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
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_client.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_native.dart';
import 'package:flutter_tratra/flash/flash_search.dart';
import 'package:flutter_tratra/flash/flash_worker_pin.dart';
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
    expect(find.text('Oui, annuler'), findsOneWidget);                                     // libellés courts : jamais tronqués
    await t.tap(find.text('Oui, annuler'));
    await t.pump(const Duration(milliseconds: 400));
    expect(s.posts.keys, contains('/handy/flash/requests/9/cancel/'));
    expect(s.keys.last, 'flash-cancel-9');
    expect(find.byKey(const ValueKey('flash-request-cancel')), findsNothing);
    expect(find.text('Annulée'), findsWidgets);
  });

  testWidgets('carte : les professionnels sollicités apparaissent au fil des vagues — travailleuse, travailleur, casque si non indiqué', (t) async {
    Map<String, dynamic> pro(int id, String state, {String? gender, double dy = 0.002}) =>
        {'id': id, 'lat': 5.36 + dy, 'lng': -3.99 + dy / 2, 'gender': gender, 'state': state};
    final s = await pump(t, Server(request(s: {...search(), 'pros': [pro(41, 'contacted', gender: 'F')]})));
    await t.pump(const Duration(milliseconds: 600));
    FlashWorkerPin pin(int id) =>
        t.widget<FlashWorkerPin>(find.descendant(of: find.byKey(ValueKey('flash-pro-$id')), matching: find.byType(FlashWorkerPin)));
    expect(find.byType(FlashWorkerPin), findsOneWidget);                                    // 1re vague : une seule professionnelle
    expect(find.byKey(const ValueKey('flash-pros-approx')), findsOneWidget);                // dit clairement : positions approximatives
    expect(pin(41).pro.label, 'Professionnelle sollicitée');
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Professionnelle sollicitée'), findsOneWidget);
    // 2e vague : un travailleur et une personne qui n'a pas indiqué son genre (casque seul) ; la 1re a décliné, son repère s'estompe.
    s.current = request(s: {...search(seq: 12), 'pros': [pro(41, 'declined', gender: 'F'), pro(42, 'contacted', gender: 'M', dy: -0.003),
        pro(43, 'proposal', dy: 0.004)]});
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(FlashWorkerPin), findsNWidgets(3));
    expect(pin(41).pro.out, isTrue);
    expect(pin(42).pro.label, 'Professionnel sollicité');
    expect(pin(43).pro.label, 'Professionnel : proposition reçue');
    expect(pin(43).pro.gender, '');
    // Mission attribuée : seul le professionnel retenu reste sur la carte.
    s.current = request(status: 'assigned', s: {...search(phase: 'confirmed', seq: 20), 'pros': [pro(42, 'selected', gender: 'M', dy: -0.003)]},
        version: 2);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(FlashWorkerPin), findsOneWidget);
    expect(pin(42).pro.label, 'Professionnel retenu');
  });

  test('carte : à grande échelle les repères ne se cachent ni sous le lieu de l’intervention ni les uns sous les autres', () {
    const c = LatLng(5.36, -3.99);
    FlashProPoint pro(int id, double dLat, double dLng) => FlashProPoint(id: id, point: LatLng(5.36 + dLat, -3.99 + dLng), gender: '', state: 'contacted');
    Offset px(LatLng p, double mpp) => Offset((p.longitude + 3.99) * 111320 * 0.9956 / mpp, (p.latitude - 5.36) * 110540 / mpp);
    // Rayon 30 km : ~290 m par pixel. Trois professionnels à moins d'un kilomètre, dont deux au même endroit et un sur le lieu même.
    final pros = [pro(7, 0.004, 0.004), pro(8, 0.004, 0.004), pro(9, 0, 0), pro(10, 0.09, -0.12)];
    final wide = spreadPros(c, pros, 290);
    for (final p in pros.take(3)) {
      expect(px(wide[p.id]!, 290).distance, greaterThanOrEqualTo(37), reason: 'repère ${p.id} sous le lieu');
    }
    for (final a in pros) {
      for (final b in pros.where((b) => b.id > a.id)) {
        expect((px(wide[a.id]!, 290) - px(wide[b.id]!, 290)).distance, greaterThanOrEqualTo(35), reason: '${a.id} et ${b.id} superposés');
      }
    }
    final d = px(wide[7]!, 290);                                                            // direction réelle conservée (nord-est)
    expect(d.dx > 0 && d.dy > 0, isTrue);
    expect(wide[10], pros[3].point);                                                        // assez loin : non déplacé
    expect(spreadPros(c, pros, 290), wide);                                                 // stable d'un affichage à l'autre
    expect(spreadPros(c, [...pros, pro(11, 0.004, 0.004)], 290)[7], wide[7]);               // une nouvelle vague ne déplace pas les anciens
    // Vue rapprochée (rayon 1 km, ~10 m par pixel) : un professionnel à 600 m est déjà lisible, il reste à sa place.
    final near = [pro(7, 0.004, 0.004)];
    expect(spreadPros(c, near, 10)[7], near.first.point);
  });

  testWidgets('carte en direct : les repères arrivent avec l’évènement WebSocket ; réponse sans repères tolérée', (t) async {
    final s = Server(request());
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: s.client)), requestId: 9, events: events.stream, observeLifecycle: false);
    await live.start();
    expect(live.search.pros, isEmpty);                                                     // serveur sans repères : carte sans professionnel
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'searching', 'version': 1,
        'search': {...search(seq: 12), 'pros': [{'id': 7, 'lat': 5.361, 'lng': -3.991, 'gender': 'M', 'state': 'contacted'},
            {'id': 8, 'lat': null, 'lng': -3.99, 'gender': null, 'state': 'contacted'}]}}));
    await t.pump();
    expect(live.search.pros.map((p) => (p.id, p.gender, p.state, p.point.latitude)), [(7, 'M', 'contacted', 5.361)]);   // repère sans position : ignoré
    expect(s.gets, 1);
    live.dispose();
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
    await t.tap(find.text('Confirmer'));
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

  testWidgets('course : une lecture API partie avant un évènement WebSocket plus récent ne l’écrase jamais', (t) async {
    final s = Server(request(s: search(seq: 56, radius: 1000, contacted: 1)));
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: s.client)), requestId: 9, events: events.stream, observeLifecycle: false);
    await live.start();
    s.hang = Completer<void>();                                                          // la lecture suivante tarde (réseau)
    final slow = live.refresh();
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'searching', 'version': 1,
        'search': search(seq: 60, radius: 5000, contacted: 3)}));                          // vague suivante reçue en direct
    await t.pump();
    expect(live.search.radiusM, 5000);
    s.current = request(s: search(seq: 60, radius: 5000, contacted: 3));
    final stale = request(s: search(seq: 56, radius: 1000, contacted: 1));
    final fresh = s.current;
    s.current = stale;                                                                   // la lecture en vol renvoie l'état ANCIEN
    s.hang!.complete();
    s.hang = null;
    await slow;
    expect(live.search.radiusM, 5000, reason: 'état plus récent conservé');
    s.current = fresh;
    await t.pump(const Duration(milliseconds: 800));                                     // relecture de rattrapage
    await t.pump();
    expect(live.search.seq, 60);
    expect(live.search.count('contacted'), 3);
    live.dispose();                                                                      // minuteries arrêtées avant la fin du test
  });

  testWidgets('synchronisation : messages en double, en retard ou dans le désordre ; une demande annulée ne redevient jamais active', (t) async {
    final s = Server(request(s: search(seq: 10, radius: 500)));
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: s.client)), requestId: 9, events: events.stream, observeLifecycle: false);
    await live.start();
    InboxEvent ws(int seq, int radius, {String status = 'searching', String phase = 'search'}) => InboxEvent('flash_request',
        raw: {'type': 'flash_request', 'id': 9, 'status': status, 'version': 1, 'search': search(seq: seq, radius: radius, phase: phase)});
    for (final e in [ws(13, 5000), ws(12, 1000), ws(13, 5000), ws(11, 500)]) {             // désordre, doublon, retard
      events.add(e);
    }
    await t.pump();
    expect(live.search.seq, 13);
    expect(live.search.radiusM, 5000);
    // Réponse d'une action arrivée APRÈS un état plus récent : jamais appliquée, l'état complet est relu.
    s.current = request(s: search(seq: 13, radius: 5000));
    final before = s.gets;
    live.apply(request(s: search(seq: 12, radius: 1000)));
    await t.pump();
    await t.pump();
    expect(live.search.radiusM, 5000);
    expect(s.gets, before + 1);
    // Annulation confirmée par le serveur, puis tout ce qui traîne encore sur le réseau.
    live.apply(request(status: 'cancelled', s: search(phase: 'cancelled', seq: 14)));
    expect(live.status, 'cancelled');
    events.add(ws(13, 5000));                                                             // message d'avant l'annulation
    events.add(ws(15, 10000));                                                            // même « plus récent », il ne rouvre rien
    await t.pump();
    expect(live.status, 'cancelled');
    expect(live.isOpen, isFalse);
    s.current = request(s: search(seq: 13, radius: 5000));                                // lecture périmée (cache, réplique en retard)
    await live.refresh();
    expect(live.status, 'cancelled');
    expect(live.search.phase, 'cancelled');
    s.current = request(status: 'cancelled', s: search(phase: 'cancelled', seq: 14));
    await live.refresh();                                                                 // le même état, relu : accepté
    expect(live.status, 'cancelled');
    expect(live.offline, isFalse);
    live.dispose();
  });

  testWidgets('coupure puis reconnexion : l’état affiché est conservé et signalé, puis l’état complet du serveur est relu', (t) async {
    var down = false;
    var gets = 0;
    var current = request(s: search(seq: 10, radius: 1000));
    final client = MockClient((r) async {
      if (down) throw http.ClientException('réseau coupé');
      gets++;
      return _json(current);
    });
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: client)), requestId: 9, events: events.stream, observeLifecycle: false);
    await live.start();
    down = true;                                                                          // réseau coupé pendant la recherche
    await live.refresh();
    expect(live.offline, isTrue);
    expect(live.error, isNull, reason: 'l’état connu reste affiché');
    expect(live.search.seq, 10);
    // Pendant la coupure, un professionnel a été retenu. Le réseau revient : la WebSocket se rétablit (`resync`).
    current = request(status: 'assigned', s: search(phase: 'confirmed', seq: 31), version: 4);
    down = false;
    final before = gets;
    events.add(InboxEvent('resync'));
    await t.pump();
    await t.pump();
    expect(gets, before + 1);
    expect(live.status, 'assigned');
    expect(live.search.seq, 31);
    expect(live.offline, isFalse);
    // Application rouverte ou revenue au premier plan : même règle, l'état du serveur est relu.
    current = request(status: 'searching', s: search(seq: 40, radius: 5000), version: 5);  // désistement : la recherche a repris
    live.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
    expect(live.status, 'searching');
    expect(live.search.seq, 40);
    expect(live.isOpen, isTrue, reason: 'reprise légitime après un désistement (numéro plus récent)');
    live.dispose();
  });

  testWidgets('attribution reçue en direct pendant une panne de lecture : relue toute seule jusqu’à l’état complet', (t) async {
    var down = false;
    var gets = 0;
    var current = request(s: search(seq: 10, radius: 1000));
    final client = MockClient((r) async {
      if (down) throw http.ClientException('réseau coupé');
      gets++;
      return _json(current);
    });
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: client)), requestId: 9, events: events.stream, socketLive: () => true,
        observeLifecycle: false);
    await live.start();
    // La WebSocket annonce l'attribution, mais la lecture du détail échoue (API injoignable à cet instant) — constaté sur téléphone.
    down = true;
    current = {...request(status: 'assigned', s: search(phase: 'confirmed', seq: 31), version: 4), 'booking': 77};
    events.add(InboxEvent('flash_request',
        raw: {'type': 'flash_request', 'id': 9, 'status': 'assigned', 'version': 4, 'search': search(phase: 'confirmed', seq: 31)}));
    await t.pump();
    await t.pump();
    expect(live.status, 'assigned');
    expect(live.offline, isTrue);
    expect(live.data!['booking'], isNull, reason: 'le détail n’a pas encore pu être lu');
    // Demande close mais état incomplet : la lecture est retentée sans action de l'utilisateur, au rythme court.
    down = false;
    final before = gets;
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 100));
    expect(gets, before + 1);
    expect(live.offline, isFalse);
    expect(live.data!['booking'], 77);
    await t.pump(const Duration(seconds: 40));                                            // état complet, demande close : plus de lecture
    expect(gets, before + 1);
    live.dispose();
  });

  testWidgets('demande attribuée : « Annuler ma demande » n’est plus proposé, même si le détail affiché date d’avant', (t) async {
    await pump(t, Server({...request(status: 'assigned', s: search(phase: 'confirmed')), 'can_cancel': true}));
    expect(find.byKey(const ValueKey('flash-request-cancel')), findsNothing);
  });

  testWidgets('accord demandé en direct : la carte « Élargir » apparaît sans attendre une lecture, étapes conservées', (t) async {
    final s = await pump(t, Server(request(mode: 'quote', s: search(proposals: 1), quotes: [quote(31, 18000)])));
    expect(find.byKey(const ValueKey('flash-extend-card')), findsNothing);
    final live = Server(request(mode: 'quote', s: search(phase: 'extension', radius: 30000, consent: true, proposals: 1), quotes: [quote(31, 18000)]));
    s.current = live.current;
    await t.pump(const Duration(seconds: 6));                                            // lecture périodique (pas de WebSocket ici)
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('flash-extend-card')), findsOneWidget);
    expect(find.textContaining('Aucun autre professionnel'), findsOneWidget);
  });

  testWidgets('désistement : la reprise est annoncée ; prix convenu affiché après une contre-offre acceptée', (t) async {
    final s = await pump(t, Server({...request(), 'reopened': {'pro': 'Ibrahim T.'}}));
    expect(find.byKey(const ValueKey('flash-reopened')), findsOneWidget);
    expect(find.textContaining('Ibrahim T. s’est désisté'), findsOneWidget);
    s.current = {
      ...request(status: 'assigned', mode: 'quote', s: search(phase: 'confirmed', proposals: 2), quotes: [quote(31, 18000, status: 'accepted')], version: 3),
      'assigned_to': {'id': 131, 'name': 'Koffi T.'}, 'booking': 2, 'agreed_label': '15 000 FCFA',
    };
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Prix convenu : 15 000 FCFA'), findsOneWidget);
    expect(find.textContaining('Proposé : 18000 FCFA · contre-offre acceptée'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-reopened')), findsNothing);
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
          if (status == 'accepted') ...{'address': 'Rue 1', 'client_name': 'Awa', 'booking': 55, 'agreed_label': '25 000 FCFA'},
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
    // La barre de délai de la contre-offre est une animation continue : `pumpAndSettle` n'aboutirait pas tant qu'elle court.
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Contre-offre du client : 25 000 FCFA'), findsOneWidget);
    expect(find.text('CONTRE-OFFRE DU CLIENT'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-counter-decline')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flash-counter-accept')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(posts, ['/handy/flash/offers/7/counter/accept/ flash-counter-accept-7']);
    expect(find.byKey(const ValueKey('flash-accepted')), findsOneWidget);
    expect(find.text('Prix convenu : 25 000 FCFA'), findsOneWidget);                    // montant de la contre-offre, pas la proposition
  });
}
