// Barres de délai Tratra Flash : échéance du serveur ramenée sur l'horloge du téléphone (jamais un compteur local), temps restant
// `01:30 → 00:00`, vert → orange → rouge, une seule pulsation pour toutes les barres, rien qui tourne après l'échéance ou la
// fermeture. Écrans : proposition du professionnel (mission, contre-offre), « Mes propositions », propositions reçues par le client.
// À 0 : les actions se ferment aussitôt, puis l'état réel est relu sur le serveur. Reprise après fermeture / réouverture,
// arrière-plan, reconnexion et évènements WebSocket.
//
// Le faux serveur vit à SON heure (3 h d'écart avec le téléphone) et recalcule `server_now` et `seconds_left` à chaque lecture.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_deadline.dart';
import 'package:flutter_tratra/flash/flash_pro.dart';
import 'package:flutter_tratra/flash/flash_search.dart';
import 'package:flutter_tratra/flash/flash_search_screen.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';

import 'flash_search_test.dart' as cli;
import 'flash_test.dart' as pro;

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Proposition telle que le serveur la connaît (dates à l'heure du serveur).
class TimedOffer {
  TimedOffer(this.id, {required this.sentAt, required this.expiresAt, this.status = 'pending', this.mode = 'firm'});
  final int id;
  String status;
  String mode;
  DateTime sentAt, expiresAt;
  DateTime? counterAt, counterExpiresAt;

  Map<String, dynamic> json(DateTime now) => {
        ...pro.offer(status: status, mode: mode),
        'id': id, 'sent_at': _iso(sentAt), 'expires_at': _iso(expiresAt), 'server_now': _iso(now),
        'seconds_left': status == 'pending' ? math.max(0, expiresAt.difference(now).inSeconds) : 0,
        if (status == 'quoted' || status == 'countered') 'quote_amount': 30000,
        'counter': status == 'countered'
            ? {'amount': 25000, 'amount_label': '25 000 FCFA', 'at': _iso(counterAt!), 'expires_at': _iso(counterExpiresAt!),
                'seconds_left': math.max(0, counterExpiresAt!.difference(now).inSeconds)}
            : null,
      };
}

/// Faux serveur des propositions, à l'heure du serveur : `skew` = heure du serveur − heure du téléphone.
class TimedServer {
  TimedServer({this.skew = const Duration(hours: -3)});
  final Duration skew;
  DateTime get now => clock.now().toUtc().add(skew);

  final offers = <int, TimedOffer>{};
  int offerGets = 0, listGets = 0;
  Completer<void>? hang;          // lectures retenues (réseau lent) tant qu'il n'est pas complété
  final posts = <String>[];

  late final client = MockClient((r) async {
    final path = r.url.path;
    if (r.method == 'GET') {
      final one = RegExp(r'/flash/offers/(\d+)/$').firstMatch(path);
      if (one != null) offerGets++;
      if (path.endsWith('/flash/offers/')) listGets++;
      if (hang != null) await hang!.future;
      if (one != null) {
        final o = offers[int.parse(one.group(1)!)];
        return o == null ? _json({}, 404) : _json(o.json(now));
      }
      if (path.endsWith('/flash/offers/')) return _json({'results': [for (final o in offers.values) o.json(now)]});
    }
    if (r.method == 'POST') posts.add(path);
    return _json({}, 404);
  });
}

/// Faux serveur d'une demande du client : même outillage que `flash_search_test.dart`, mais l'état est recalculé à l'heure du serveur.
class TimedRequests extends cli.Server {
  TimedRequests(this.build, {this.skew = const Duration(hours: -3)}) : super(const {});
  final Map<String, dynamic> Function(DateTime now) build;
  final Duration skew;
  DateTime get now => clock.now().toUtc().add(skew);

  @override
  Map<String, dynamic> get current => {...build(now), 'server_now': _iso(now)};
  @override
  set current(Map<String, dynamic> _) {}
}

/// Une barre en cours est une animation continue : `pumpAndSettle` n'aboutirait pas. Avance d'une demi-seconde, image par image.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Temps affiché par la barre `key`.
String timeOf(WidgetTester t, String key) =>
    t.widget<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byKey(const ValueKey('flash-countdown-time')))).data!;

bool disabled(WidgetTester t, String key) => t.widget<TratraButton>(find.byKey(ValueKey(key))).onPressed == null;

/// Application du professionnel sur le faux serveur ; `events` = liaison temps réel (WebSocket) du membre.
Future<(FlashController, pro.FakeNative, GlobalKey<NavigatorState>, StreamController<InboxEvent>)> pumpPro(WidgetTester t, TimedServer s,
    {Widget home = const Scaffold()}) async {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final native = pro.FakeNative();
  final key = GlobalKey<NavigatorState>();
  final events = StreamController<InboxEvent>.broadcast();
  addTearDown(events.close);
  final c = FlashController(api: FlashApi(BaseApi(client: s.client)), native: native, navigatorKey: key, isAuthenticated: () => true)
    ..attachLive(events.stream);
  await t.pumpWidget(ChangeNotifierProvider<FlashController>.value(
      value: c, child: MaterialApp(navigatorKey: key, theme: TratraTheme.light(), home: home)));
  await c.start();
  return (c, native, key, events);
}

Future<void> pumpBar(WidgetTester t, Widget bar) => t.pumpWidget(MaterialApp(
    theme: TratraTheme.light(), home: Scaffold(body: Center(child: SizedBox(width: 300, child: bar)))));

Finder get _barPaint => find.descendant(of: find.byType(FlashCountdownBar), matching: find.byType(CustomPaint));

RRect _pill(double width) => RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, 6), const Radius.circular(3));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'acc'});
    FlashSearchMap.tiles = false;
  });

  // ── Échéance : heure du serveur, jamais l'horloge du téléphone ────────────────────────────────────────────────────────────────

  test('échéance : située par l’heure du serveur, quelle que soit l’horloge du téléphone', () {
    final phone = DateTime(2031, 5, 1, 3);           // téléphone déréglé : des années d'écart avec le serveur
    final d = FlashDeadline.from(
        expiresAt: '2026-11-11T20:00:00+00:00', startedAt: '2026-11-11T19:58:30+00:00', serverNow: '2026-11-11T19:59:00+00:00',
        secondsLeft: 999, receivedAt: phone)!;
    expect(d.endsAt, phone.add(const Duration(seconds: 60)));       // 60 s restantes à l'heure du serveur (et non les 999 du repli)
    expect(d.total, const Duration(seconds: 90));
    expect(d.fraction(phone), closeTo(60 / 90, 1e-9));
    expect(d.left(phone.add(const Duration(seconds: 45))), const Duration(seconds: 15));
    expect(d.over(phone.add(const Duration(seconds: 59, milliseconds: 999))), isFalse);
    expect(d.over(phone.add(const Duration(seconds: 60))), isTrue);
    expect(d.left(phone.add(const Duration(hours: 1))), Duration.zero);                // jamais négatif
    expect(d.fraction(phone.add(const Duration(hours: 1))), 0);
  });

  test('échéance : repli sur `seconds_left`, rien d’inventé sans donnée du serveur, délai déjà écoulé', () {
    final phone = DateTime(2026, 11, 11, 12);
    final old = FlashDeadline.from(expiresAt: '2026-11-11T20:00:00+00:00', secondsLeft: 45, receivedAt: phone)!;   // serveur sans `server_now`
    expect(old.endsAt, phone.add(const Duration(seconds: 45)));
    expect(old.total, const Duration(seconds: 45));                                    // durée complète inconnue : barre pleine à la réception
    // Échéance connue mais ni l'heure du serveur ni le temps restant : aucune barre, l'horloge du téléphone ne sert jamais de repli.
    expect(FlashDeadline.from(expiresAt: '2026-11-11T20:00:00+00:00', startedAt: '2026-11-11T19:58:30+00:00', receivedAt: phone), isNull);
    expect(FlashDeadline.from(receivedAt: phone), isNull);
    final past = FlashDeadline.from(expiresAt: '2026-11-11T20:00:00+00:00', startedAt: '2026-11-11T19:58:30+00:00',
        serverNow: '2026-11-11T20:00:07+00:00', receivedAt: phone)!;
    expect(past.over(phone), isTrue);
    expect(past.left(phone), Duration.zero);
    // Durée annoncée plus courte que le temps restant (données incohérentes) : la barre ne dépasse jamais 100 %.
    final odd = FlashDeadline.from(expiresAt: '2026-11-11T20:00:00+00:00', startedAt: '2026-11-11T19:59:50+00:00',
        serverNow: '2026-11-11T19:59:00+00:00', receivedAt: phone)!;
    expect(odd.fraction(phone), 1);
  });

  test('temps restant `01:30 → 00:00` et couleurs vert → orange → rouge', () {
    expect(flashCountdownText(const Duration(seconds: 90)), '01:30');
    expect(flashCountdownText(const Duration(seconds: 89, milliseconds: 200)), '01:30');   // arrondi vers le haut
    expect(flashCountdownText(const Duration(seconds: 60)), '01:00');
    expect(flashCountdownText(const Duration(milliseconds: 400)), '00:01');                // « 00:00 » seulement à l'échéance
    expect(flashCountdownText(Duration.zero), '00:00');
    expect(flashCountdownText(const Duration(seconds: -4)), '00:00');
    expect(flashCountdownText(const Duration(minutes: 30)), '30:00');
    expect(flashCountdownText(const Duration(hours: 1, minutes: 2, seconds: 5)), '1:02:05');

    expect(flashCountdownColor(1), TtColors.primary);
    expect(flashCountdownColor(0.6), TtColors.primary);
    expect(flashCountdownColor(0.35), TtColors.warning);
    expect(flashCountdownColor(0.1), TtColors.danger);
    expect(flashCountdownColor(0), TtColors.danger);
    final mid = flashCountdownColor(0.5);                                                   // fondu, sans saut de couleur
    expect(mid, isNot(TtColors.primary));
    expect(mid, isNot(TtColors.warning));
    expect([flashCountdownTone(0.9), flashCountdownTone(0.4), flashCountdownTone(0.1)], [0, 1, 2]);
  });

  // ── La barre ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  testWidgets('barre : pleine au départ, se décharge jusqu’à 0, verte puis orange puis rouge, échéance signalée une seule fois', (t) async {
    var expired = 0;
    final d = FlashDeadline.from(secondsLeft: 80, receivedAt: clock.now())!;
    await pumpBar(t, FlashCountdownBar(deadline: d, label: 'Temps pour répondre', onExpired: () => expired++));
    expect(find.text('01:20'), findsOneWidget);
    expect(find.text('Temps pour répondre'), findsOneWidget);
    expect(_barPaint, paints..rrect(rrect: _pill(300), color: TtColors.line)..rrect(rrect: _pill(300), color: TtColors.primary));   // 100 %

    await t.pump(const Duration(seconds: 20));
    expect(find.text('01:00'), findsOneWidget);
    expect(_barPaint, paints..rrect(rrect: _pill(300))..rrect(rrect: _pill(225), color: TtColors.primary));                         // 75 % : vert

    await t.pump(const Duration(seconds: 40));
    expect(find.text('00:20'), findsOneWidget);
    expect(_barPaint, paints..rrect(rrect: _pill(300))..rrect(rrect: _pill(75), color: TtColors.warning));                          // 25 % : orange

    await t.pump(const Duration(seconds: 10));
    expect(find.text('00:10'), findsOneWidget);
    expect(_barPaint, paints..rrect(rrect: _pill(300))..rrect(rrect: _pill(37.5), color: TtColors.danger));                         // 12,5 % : rouge
    expect(expired, 0);
    expect(FlashPulse.instance.running, isTrue);

    await t.pump(const Duration(seconds: 10));
    expect(find.text('00:00'), findsOneWidget);
    expect(_barPaint, isNot(paints..rrect()..rrect()));                                                                              // vide
    expect(expired, 1);
    expect(FlashPulse.instance.running, isFalse);            // plus aucune image demandée une fois le délai écoulé

    await t.pump(const Duration(seconds: 30));
    expect(expired, 1);                                      // jamais signalée deux fois
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('barre : une seule pulsation pour toutes, arrêtée à la dernière échéance et à la fermeture de l’écran', (t) async {
    final now = clock.now();
    final log = <String>[];
    final theme = TratraTheme.light();                       // même thème d'une image à l'autre : aucune animation de thème en plus
    Widget bars({bool second = true}) => MaterialApp(
        theme: theme,
        home: Scaffold(
            body: Column(children: [
          FlashCountdownBar(key: const ValueKey('a'), deadline: FlashDeadline.from(secondsLeft: 5, receivedAt: now)!, onExpired: () => log.add('a')),
          if (second)
            FlashCountdownBar(key: const ValueKey('b'), deadline: FlashDeadline.from(secondsLeft: 10, receivedAt: now)!, onExpired: () => log.add('b')),
        ])));
    expect(FlashPulse.instance.running, isFalse);
    await t.pumpWidget(bars());
    expect(FlashPulse.instance.running, isTrue);
    expect(t.binding.transientCallbackCount, 1);             // deux barres, un seul rappel d'image
    await t.pump(const Duration(seconds: 6));
    expect(log, ['a']);
    expect(FlashPulse.instance.running, isTrue);             // la seconde court encore
    expect(timeOf(t, 'a'), '00:00');
    expect(timeOf(t, 'b'), '00:04');
    await t.pumpWidget(bars(second: false));                 // barre retirée avant son échéance : ni rappel ni minuterie en attente
    expect(FlashPulse.instance.running, isFalse);
    expect(t.binding.transientCallbackCount, 0);
    await t.pump(const Duration(seconds: 10));
    expect(log, ['a']);
  });

  testWidgets('barre : échéance signalée même sans image (écran recouvert), rien sur un délai déjà écoulé, recalage sur un nouvel état', (t) async {
    var expired = 0;
    Widget bar(FlashDeadline d, {bool enabled = true}) =>
        TickerMode(enabled: enabled, child: FlashCountdownBar(deadline: d, onExpired: () => expired++));
    final start = clock.now();
    await pumpBar(t, bar(FlashDeadline.from(secondsLeft: 5, receivedAt: start)!, enabled: false));
    expect(FlashPulse.instance.running, isFalse);            // écran recouvert : aucune image demandée…
    await t.pump(const Duration(seconds: 6));
    expect(expired, 1);                                      // …mais l'échéance est bien signalée
    expect(find.text('00:00'), findsOneWidget);

    // Délai déjà écoulé à la construction : barre vide, rien de déclenché (l'appelant ne boucle pas sur un état non clos).
    await pumpBar(t, const SizedBox());
    await pumpBar(t, bar(FlashDeadline.from(secondsLeft: 0, receivedAt: clock.now())!));
    expect(find.text('00:00'), findsOneWidget);
    expect(FlashPulse.instance.running, isFalse);
    await t.pump(const Duration(seconds: 5));
    expect(expired, 1);

    // Nouvel état du serveur : la barre se recale aussitôt, puis signale la nouvelle échéance.
    await pumpBar(t, bar(FlashDeadline.from(secondsLeft: 30, receivedAt: clock.now())!));
    expect(find.text('00:30'), findsOneWidget);
    expect(FlashPulse.instance.running, isTrue);
    await t.pump(const Duration(seconds: 30));
    expect(expired, 2);
  });

  // ── Proposition du professionnel ──────────────────────────────────────────────────────────────────────────────────────────────

  for (final skew in const [Duration(hours: -3), Duration(hours: 3)]) {
    testWidgets('proposition : barre calée sur l’heure du serveur (écart téléphone/serveur de ${skew.inHours} h)', (t) async {
      final s = TimedServer(skew: skew);
      s.offers[7] = TimedOffer(7, sentAt: s.now.subtract(const Duration(seconds: 30)), expiresAt: s.now.add(const Duration(seconds: 60)));
      final (c, _, _, _) = await pumpPro(t, s);
      unawaited(c.present(7, ring: true));
      await settle(t);
      expect(timeOf(t, 'flash-countdown'), '01:00');                         // 60 s restantes sur 90, malgré 3 h d'écart d'horloge
      final d = t.widget<FlashCountdownBar>(find.byKey(const ValueKey('flash-countdown'))).deadline;
      expect(d.total, const Duration(seconds: 90));
      expect(d.fraction(), closeTo(59.5 / 90, 0.005));
      expect(find.text('Temps pour répondre'), findsOneWidget);
      expect(find.byKey(const ValueKey('flash-accept')), findsOneWidget);
      await t.pump(const Duration(seconds: 9, milliseconds: 500));
      expect(timeOf(t, 'flash-countdown'), '00:50');
    });
  }

  testWidgets('proposition fermée puis rouverte : la barre reprend au bon endroit', (t) async {
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now, expiresAt: s.now.add(const Duration(seconds: 90)));
    final (c, _, key, _) = await pumpPro(t, s);
    unawaited(c.present(7, ring: true));
    await settle(t);
    expect(timeOf(t, 'flash-countdown'), '01:30');
    key.currentState!.pop();
    await t.pump();
    await t.pump(const Duration(seconds: 1));                                // fin de la transition de fermeture
    expect(find.byType(FlashCountdownBar), findsNothing);
    expect(FlashPulse.instance.running, isFalse);                            // écran fermé : plus rien ne tourne
    await t.pump(const Duration(seconds: 28));
    unawaited(c.present(7));
    await settle(t);                                                         // 30 s écoulées depuis l'envoi
    await t.pump(const Duration(milliseconds: 300));
    expect(timeOf(t, 'flash-countdown'), '01:00');
    expect(s.offerGets, 2);                                                  // l'état vient du serveur, pas d'un compteur gardé en mémoire
  });

  testWidgets('à 0 : accepter / refuser retirés aussitôt, puis l’état réel est relu sur le serveur', (t) async {
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now.subtract(const Duration(seconds: 30)), expiresAt: s.now.add(const Duration(seconds: 60)));
    final (c, native, _, _) = await pumpPro(t, s);
    unawaited(c.present(7, ring: true));
    await settle(t);
    await t.pump(const Duration(seconds: 58, milliseconds: 500));
    expect(timeOf(t, 'flash-countdown'), '00:01');
    expect(find.byKey(const ValueKey('flash-accept')), findsOneWidget);
    expect(s.offerGets, 1);

    s.hang = Completer<void>();                                              // réseau lent : la relecture ne répond pas tout de suite
    s.offers[7]!.status = 'withdrawn';                                       // entre-temps, la mission a été attribuée à un autre
    await t.pump(const Duration(seconds: 1));
    expect(timeOf(t, 'flash-countdown'), '00:00');
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);        // sans attendre la réponse du serveur
    expect(find.byKey(const ValueKey('flash-decline')), findsNothing);
    expect(find.textContaining('délai de réponse est écoulé'), findsOneWidget);
    expect(native.stops, greaterThan(0));                                    // sonnerie arrêtée
    expect(s.offerGets, 2);                                                  // état réel demandé

    s.hang!.complete();
    s.hang = null;
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Cette mission n’est plus disponible.'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-countdown')), findsNothing);
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(s.posts, isEmpty);
    expect(FlashPulse.instance.running, isFalse);
  });

  testWidgets('à 0, proposition pas encore close par le serveur : elle reste échue, sans relecture en boucle', (t) async {
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now, expiresAt: s.now.add(const Duration(seconds: 20)));
    final (c, _, _, _) = await pumpPro(t, s);
    unawaited(c.present(7, ring: true));
    await settle(t);
    await t.pump(const Duration(seconds: 20));
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(timeOf(t, 'flash-countdown'), '00:00');
    expect(s.offerGets, 2);
    await t.pump(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 30));
    expect(s.offerGets, 2);                                                  // une seule relecture à l'échéance
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(find.textContaining('délai de réponse est écoulé'), findsOneWidget);
  });

  testWidgets('WebSocket : mission attribuée à un autre → écran clos aussitôt, alerte retirée', (t) async {
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now, expiresAt: s.now.add(const Duration(seconds: 90)));
    final (c, native, _, events) = await pumpPro(t, s);
    unawaited(c.present(7, ring: true));
    await settle(t);
    expect(find.byKey(const ValueKey('flash-accept')), findsOneWidget);
    s.offers[7]!.status = 'withdrawn';
    events.add(InboxEvent('flash_offer', raw: const {'type': 'flash_offer', 'id': 7, 'status': 'withdrawn'}));
    await settle(t);
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(find.textContaining('n’est plus disponible'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-countdown')), findsNothing);
    expect(native.cancelled, contains(7));
    expect(s.offerGets, 2);
    // Évènement d'une AUTRE proposition : rien n'est relu ici.
    events.add(InboxEvent('flash_offer', raw: const {'type': 'flash_offer', 'id': 8, 'status': 'withdrawn'}));
    await settle(t);
    expect(s.offerGets, 2);
  });

  testWidgets('contre-offre reçue en direct : sa barre ; à 0 les réponses se ferment et la proposition reste valable', (t) async {
    final s = TimedServer();
    final o = s.offers[7] = TimedOffer(7, sentAt: s.now.subtract(const Duration(minutes: 2)), expiresAt: s.now.subtract(const Duration(seconds: 30)),
        status: 'quoted', mode: 'quote');
    final (c, _, _, events) = await pumpPro(t, s);
    unawaited(c.present(7));
    await settle(t);
    expect(find.byKey(const ValueKey('flash-quoted')), findsOneWidget);
    expect(find.byType(FlashCountdownBar), findsNothing);

    o
      ..status = 'countered'
      ..counterAt = s.now
      ..counterExpiresAt = s.now.add(const Duration(minutes: 5));
    events.add(InboxEvent('flash_offer', raw: const {'type': 'flash_offer', 'id': 7, 'status': 'countered', 'counter_amount': 25000}));
    await settle(t);
    expect(find.text('Contre-offre du client : 25 000 FCFA'), findsOneWidget);
    expect(timeOf(t, 'flash-counter-countdown'), '05:00');
    expect(disabled(t, 'flash-counter-accept'), isFalse);
    await t.pump(const Duration(seconds: 149, milliseconds: 500));
    expect(timeOf(t, 'flash-counter-countdown'), '02:30');
    await t.pump(const Duration(seconds: 149));
    expect(timeOf(t, 'flash-counter-countdown'), '00:01');
    expect(disabled(t, 'flash-counter-accept'), isFalse);

    s.hang = Completer<void>();
    o.status = 'quoted';                                                     // le serveur rend la proposition initiale
    await t.pump(const Duration(seconds: 1));
    expect(timeOf(t, 'flash-counter-countdown'), '00:00');
    expect(disabled(t, 'flash-counter-accept'), isTrue);                     // aussitôt, avant la réponse du serveur
    expect(disabled(t, 'flash-counter-decline'), isTrue);
    expect(find.textContaining('délai de la contre-offre est écoulé'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flash-counter-accept')), warnIfMissed: false);
    await t.pump();
    expect(s.posts, isEmpty);

    s.hang!.complete();
    s.hang = null;
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('flash-quoted')), findsOneWidget);      // état réel : la proposition reste valable
    expect(find.byKey(const ValueKey('flash-counter-accept')), findsNothing);
    expect(find.textContaining('votre proposition reste valable'), findsOneWidget);
    expect(FlashPulse.instance.running, isFalse);
  });

  testWidgets('liaison rétablie (resync) : l’état réel est relu, même sans évènement reçu', (t) async {
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now, expiresAt: s.now.add(const Duration(seconds: 90)));
    final (c, _, _, events) = await pumpPro(t, s);
    unawaited(c.present(7, ring: true));
    await settle(t);
    s.offers[7]!.status = 'withdrawn';                                       // attribuée pendant la coupure : aucun évènement reçu
    await t.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('flash-accept')), findsOneWidget);
    events.add(InboxEvent('resync'));
    await settle(t);
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(find.text('Cette mission n’est plus disponible.'), findsOneWidget);
  });

  testWidgets('arrière-plan : au retour la barre est au bon endroit ; délai passé en arrière-plan → plus d’action', (t) async {
    addTearDown(() => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now, expiresAt: s.now.add(const Duration(seconds: 90)));
    final (c, native, _, _) = await pumpPro(t, s);
    unawaited(c.present(7, ring: true));
    await settle(t);
    expect(timeOf(t, 'flash-countdown'), '01:30');

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 29, milliseconds: 500));            // 30 s en arrière-plan : aucune image
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(timeOf(t, 'flash-countdown'), '01:00');
    expect(s.offerGets, 2);                                                  // relu au retour
    expect(find.byKey(const ValueKey('flash-accept')), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    s.offers[7]!.status = 'expired';
    await t.pump(const Duration(seconds: 70));                               // l'échéance passe en arrière-plan
    expect(native.stops, greaterThan(0));                                    // sonnerie coupée à l'échéance, sans attendre le retour
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(find.textContaining('délai de réponse est écoulé'), findsOneWidget);
  });

  // ── « Mes propositions » ──────────────────────────────────────────────────────────────────────────────────────────────────────

  testWidgets('« Mes propositions » : barre sur les propositions à traiter ; relue à l’échéance et sur évènement', (t) async {
    final s = TimedServer();
    s.offers[7] = TimedOffer(7, sentAt: s.now.subtract(const Duration(seconds: 30)), expiresAt: s.now.add(const Duration(seconds: 60)));
    s.offers[8] = TimedOffer(8, sentAt: s.now.subtract(const Duration(minutes: 9)), expiresAt: s.now.subtract(const Duration(minutes: 7)),
        status: 'countered', mode: 'quote')
      ..counterAt = s.now.subtract(const Duration(seconds: 100))
      ..counterExpiresAt = s.now.add(const Duration(seconds: 200));
    s.offers[9] = TimedOffer(9, sentAt: s.now.subtract(const Duration(hours: 1)), expiresAt: s.now.subtract(const Duration(minutes: 58)),
        status: 'accepted');
    final (_, _, _, events) = await pumpPro(t, s, home: const FlashOffersScreen());
    await t.pump(const Duration(milliseconds: 100));
    expect(timeOf(t, 'flash-offer-countdown-7'), '01:00');
    expect(timeOf(t, 'flash-offer-countdown-8'), '03:20');
    expect(find.byKey(const ValueKey('flash-offer-countdown-9')), findsNothing);       // plus rien à décider : pas de barre
    expect(find.text('En attente de votre réponse'), findsOneWidget);
    expect(find.text('Contre-offre du client à traiter'), findsOneWidget);
    expect(s.listGets, 1);

    await t.pump(const Duration(seconds: 60));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('En attente de votre réponse'), findsNothing);
    expect(find.text('Sans réponse dans le délai'), findsOneWidget);
    expect(timeOf(t, 'flash-offer-countdown-7'), '00:00');
    expect(s.listGets, 2);                                                             // relue à l'échéance, une fois
    await t.pump(const Duration(seconds: 20));
    expect(s.listGets, 2);

    s.offers[7]!.status = 'expired';
    s.offers[8]!.status = 'accepted';                                                  // contre-offre acceptée depuis l'autre écran
    events.add(InboxEvent('flash_offer', raw: const {'type': 'flash_offer', 'id': 8, 'status': 'accepted'}));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(s.listGets, 3);
    expect(find.byType(FlashCountdownBar), findsNothing);
    expect(find.text('Acceptée — mission confirmée'), findsNWidgets(2));
    expect(FlashPulse.instance.running, isFalse);
  });

  // ── Propositions reçues par le client ─────────────────────────────────────────────────────────────────────────────────────────

  testWidgets('client : validité de chaque proposition ; à 0 « Choisir » et « Contre-offre » se ferment, puis l’état réel est relu', (t) async {
    late final DateTime t0;
    final s = TimedRequests((now) {
      final lapsed = !now.isBefore(t0.add(const Duration(seconds: 60)));
      return cli.request(status: 'quoting', mode: 'quote', s: cli.search(phase: 'selection', proposals: 2), quotes: [
        {
          ...cli.quote(31, 30000, status: lapsed ? 'lapsed' : 'quoted'),
          'at': _iso(t0.subtract(const Duration(minutes: 29))), 'expires_at': _iso(t0.add(const Duration(seconds: 60))),
          'can_choose': !lapsed, 'can_counter': !lapsed, if (lapsed) 'status_label': 'Proposition échue',
        },
        {
          ...cli.quote(32, 28000, status: 'countered'),
          'at': _iso(t0.subtract(const Duration(minutes: 10))), 'expires_at': _iso(t0.add(const Duration(minutes: 20))),
          'counter_at': _iso(t0.subtract(const Duration(seconds: 100))), 'counter_expires_at': _iso(t0.add(const Duration(seconds: 200))),
        },
      ]);
    });
    t0 = s.now;
    await cli.pump(t, s);
    expect(timeOf(t, 'flash-quote-countdown-31'), '01:00');
    expect(timeOf(t, 'flash-quote-countdown-32'), '20:00');
    expect(timeOf(t, 'flash-quote-answer-countdown-32'), '03:20');             // réponse du professionnel à la contre-offre
    expect(find.text('Proposition valable encore'), findsNWidgets(2));
    expect(disabled(t, 'flash-choose-31'), isFalse);
    expect(disabled(t, 'flash-counter-31'), isFalse);

    await t.pump(const Duration(seconds: 55));
    expect(timeOf(t, 'flash-quote-countdown-31'), '00:05');
    expect(disabled(t, 'flash-choose-31'), isFalse);
    s.hang = Completer<void>();                                                 // réseau lent au moment de l'échéance
    await t.pump(const Duration(seconds: 5));
    expect(timeOf(t, 'flash-quote-countdown-31'), '00:00');
    expect(disabled(t, 'flash-choose-31'), isTrue);                            // aussitôt, avant toute réponse du serveur
    expect(disabled(t, 'flash-counter-31'), isTrue);
    expect(find.text('Proposition échue'), findsOneWidget);
    expect(disabled(t, 'flash-choose-32'), isFalse);                           // l'autre proposition reste ouverte
    await t.tap(find.byKey(const ValueKey('flash-choose-31')), warnIfMissed: false);
    await t.pump();
    expect(s.posts, isEmpty);

    s.hang!.complete();
    s.hang = null;
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('flash-choose-31')), findsNothing);       // état réel du serveur : proposition échue
    expect(find.byKey(const ValueKey('flash-quote-countdown-31')), findsNothing);
    expect(find.text('Proposition échue'), findsOneWidget);
    expect(timeOf(t, 'flash-quote-countdown-32'), '19:00');
  });

  testWidgets('client : proposition close par le serveur après l’échéance → relue dès l’évènement WebSocket (constaté sur téléphone)', (t) async {
    // Le serveur accorde une courte tolérance avant de clore une proposition : la lecture faite à 0 la voit encore « valable ».
    // L'évènement qui suit ne change aucun compteur ; il doit pourtant faire relire l'état réel, sans attendre 30 s.
    Map<String, dynamic> state(int seq, {required bool lapsed}) =>
        cli.request(status: 'quoting', mode: 'quote', s: cli.search(phase: 'selection', proposals: 2, seq: seq), quotes: [
          {...cli.quote(31, 30000, status: lapsed ? 'lapsed' : 'quoted'), 'can_choose': !lapsed, 'can_counter': !lapsed},
          cli.quote(32, 28000),
        ]);
    final s = cli.Server(state(20, lapsed: false));
    final events = StreamController<InboxEvent>.broadcast();
    addTearDown(events.close);
    final live = FlashRequestLive(api: FlashApi(BaseApi(client: s.client)), requestId: 9, events: events.stream, socketLive: () => true,
        observeLifecycle: false);
    await live.start();
    expect(s.gets, 1);
    expect((live.data!['quotes'] as List).first['can_choose'], isTrue);

    s.current = state(21, lapsed: true);
    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'quoting', 'version': 1,
        'search': cli.search(phase: 'selection', proposals: 2, seq: 21)}));
    await t.pump();
    await t.pump();
    expect(s.gets, 2);
    expect((live.data!['quotes'] as List).first['can_choose'], isFalse);

    events.add(InboxEvent('flash_request', raw: {'type': 'flash_request', 'id': 9, 'status': 'quoting', 'version': 1,
        'search': cli.search(phase: 'selection', proposals: 2, seq: 21)}));          // message en double : aucune lecture de plus
    await t.pump();
    await t.pump();
    expect(s.gets, 2);
    live.dispose();                                                              // sa lecture périodique s'arrête avec elle
  });

  testWidgets('client : serveur qui ne donne pas son heure → aucune barre inventée, propositions utilisables', (t) async {
    await cli.pump(t, cli.Server(cli.request(status: 'quoting', mode: 'quote', s: cli.search(phase: 'selection', proposals: 1), quotes: [
      {...cli.quote(31, 30000), 'at': '2026-11-11T19:30:00+00:00', 'expires_at': '2026-11-11T20:00:00+00:00'},
    ])));
    expect(find.byType(FlashCountdownBar), findsNothing);
    expect(disabled(t, 'flash-choose-31'), isFalse);
  });
}
