// Tratra Flash (application) : réception app ouverte (écran + sonnerie une seule fois), arrêt de l'alerte à la réponse, à l'échéance
// ou à l'attribution à un autre, actions des alertes (Accepter / Refuser / Voir), devis, réglages sonores, confidentialité.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_native.dart';
import 'package:flutter_tratra/flash/flash_settings.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

class FakeNative implements FlashNative {
  final played = <String>[];
  final cancelled = <int>[];
  int stops = 0;
  bool sound = true, vibration = true;
  FlashAction? launch;
  FlashPlayback playback = const FlashPlayback(played: true, vibrated: true);
  final controller = StreamController<FlashAction>.broadcast();

  @override
  Future<FlashAction?> takeLaunchAction() async {
    final a = launch;
    launch = null;
    return a;
  }

  @override
  Stream<FlashAction> get actions => controller.stream;
  @override
  Future<({bool sound, bool vibration})> prefs() async => (sound: sound, vibration: vibration);
  @override
  Future<void> setPrefs({required bool sound, required bool vibration}) async {
    this.sound = sound;
    this.vibration = vibration;
  }

  @override
  Future<FlashPlayback> play(String s, {bool withSound = true, bool withVibration = true}) async {
    played.add('$s:${withSound ? 'son' : '-'}:${withVibration ? 'vib' : '-'}');
    return playback;
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> cancel(int offerId) async => cancelled.add(offerId);
}

Map<String, dynamic> offer({String status = 'pending', String mode = 'firm', int seconds = 90}) => {
      'kind': 'flash_offer', 'id': 7, 'request': 3, 'mode': mode, 'category': 'Plomberie', 'zone': 'Cocody', 'when_label': 'Maintenant',
      'immediate': '1', 'amount': mode == 'firm' ? '15000' : '', 'amount_label': mode == 'firm' ? '15 000 FCFA' : 'Sur devis',
      'expires_at': '2026-10-21T20:00:00+00:00', 'distance_km': '1.2', 'status': status, 'seconds_left': seconds,
      'description': 'Fuite sous l’évier', 'why': [{'label': 'Proximité', 'detail': '1,2 km'}],
      'client_reputation': {'count': 0, 'average': null, 'public': false},
      'decline_reasons': [{'code': 'busy', 'label': 'Déjà occupé'}],
      if (status == 'accepted') ...{'address': 'Rue des Jardins, villa 12', 'client_name': 'Awa', 'booking': 55},
    };

class Server {
  Map<String, dynamic> current = offer();
  final posts = <String, Map<String, dynamic>>{};
  final keys = <String>[];
  late final client = MockClient((r) async {
    if (r.url.path.endsWith('/flash/offers/7/')) return _json(current);
    if (r.method == 'POST') {
      posts[r.url.path] = (jsonDecode(r.body) as Map).cast<String, dynamic>();
      keys.add(r.headers['Idempotency-Key'] ?? '');
      if (r.url.path.endsWith('/accept/')) {
        if (current['status'] == 'withdrawn') return _json({'code': 'already_assigned', 'detail': 'Cette mission a déjà été attribuée.'}, 409);
        current = offer(status: 'accepted');
        return _json(current);
      }
      if (r.url.path.endsWith('/decline/')) return _json(current = offer(status: 'declined'));
      if (r.url.path.endsWith('/quote/')) return _json(current = {...offer(status: 'quoted', mode: 'quote'), 'quote_amount': 22000});
    }
    return _json({}, 404);
  });
}

Future<(FlashController, FakeNative, Server, GlobalKey<NavigatorState>)> pumpApp(WidgetTester t, {Server? server}) async {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final s = server ?? Server();
  final native = FakeNative();
  final key = GlobalKey<NavigatorState>();
  final c = FlashController(api: FlashApi(BaseApi(client: s.client)), native: native, navigatorKey: key, isAuthenticated: () => true);
  await t.pumpWidget(ChangeNotifierProvider<FlashController>.value(
    value: c,
    child: MaterialApp(
      navigatorKey: key,
      theme: TratraTheme.light(),
      home: const Scaffold(body: SingleChildScrollView(child: FlashSoundSettings())),
    ),
  ));
  await c.start();
  return (c, native, s, key);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'auth_token': 'acc'}));

  testWidgets('app ouverte : écran Tratra Flash avec sonnerie, une seule fois, et détails sans donnée privée', (t) async {
    final (c, native, _, _) = await pumpApp(t);
    expect(c.handlePush({'t': 'new_mission', 'id': '7'}), isTrue);
    expect(c.handlePush({'t': 'new_mission', 'id': '7'}), isTrue);   // même push reçu deux fois
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Plomberie'), findsOneWidget);
    expect(find.text('15 000 FCFA'), findsOneWidget);
    expect(find.text('Cocody'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-countdown')), findsOneWidget);
    expect(native.played, ['tratra_flash:son:vib'], reason: 'une seule sonnerie, réglages respectés');
    expect(find.textContaining('Rue des Jardins'), findsNothing);
    expect(find.text('Nouveau client : pas encore évalué'), findsOneWidget);
    expect(c.handlePush({'t': 'booking_confirmed'}), isFalse, reason: 'les autres notifications gardent le bandeau habituel');
  });

  testWidgets('accepter : mission confirmée, adresse révélée, sonnerie arrêtée, clé d’idempotence stable', (t) async {
    final (c, native, server, _) = await pumpApp(t);
    unawaited(c.present(7, ring: true));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const ValueKey('flash-accept')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('flash-accepted')), findsOneWidget);
    expect(find.text('Adresse : Rue des Jardins, villa 12'), findsOneWidget);
    expect(server.keys, ['flash-accept-7']);
    expect(native.stops, greaterThan(0));
    expect(native.cancelled, contains(7));
  });

  testWidgets('mission prise par un autre pendant que l’écran est ouvert : alerte arrêtée, message clair', (t) async {
    final (c, native, server, _) = await pumpApp(t);
    unawaited(c.present(7, ring: true));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    server.current = offer(status: 'withdrawn');
    expect(c.handlePush({'t': 'flash_closed', 'offer': '7', 'status': 'withdrawn'}), isTrue);
    await t.pump();
    expect(find.textContaining('n’est plus disponible'), findsOneWidget);
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(native.cancelled, contains(7));
  });

  testWidgets('échéance : compte à rebours à zéro → plus d’action possible, sonnerie arrêtée', (t) async {
    final server = Server()..current = offer(seconds: 2);
    final (c, native, _, _) = await pumpApp(t, server: server);
    unawaited(c.present(7, ring: true));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('flash-accept')), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    expect(find.textContaining('délai de réponse est écoulé'), findsOneWidget);
    expect(native.stops, greaterThan(0));
  });

  testWidgets('refuser : motif facultatif, message « aucune conséquence »', (t) async {
    final (c, _, server, _) = await pumpApp(t);
    unawaited(c.present(7));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const ValueKey('flash-decline')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('decline-busy')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(server.posts['/handy/flash/offers/7/decline/'], {'reason': 'busy'});
    expect(find.byKey(const ValueKey('flash-declined')), findsOneWidget);
  });

  testWidgets('actions des alertes système : « Accepter » exécute l’acceptation, « Refuser » sans ouvrir d’écran', (t) async {
    final (c, native, server, _) = await pumpApp(t);
    native.controller.add(const FlashAction('accept', 7));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(server.posts.keys, contains('/handy/flash/offers/7/accept/'));
    expect(find.byKey(const ValueKey('flash-accepted')), findsOneWidget);
    expect(native.played, isEmpty, reason: 'l’alerte système a déjà sonné : aucune seconde sonnerie');

    final server2 = Server();
    final (c2, native2, _, _) = await pumpApp(t, server: server2);
    native2.controller.add(const FlashAction('decline', 7));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(server2.posts.keys, ['/handy/flash/offers/7/decline/']);
    expect(c2.showing, isNull);
    expect(find.text('Refus enregistré. Aucune conséquence sur votre réputation.'), findsOneWidget);
    expect(c, isNot(same(c2)));
  });

  testWidgets('sur devis : le pro envoie un prix', (t) async {
    final server = Server()..current = offer(mode: 'quote');
    final (c, _, _, _) = await pumpApp(t, server: server);
    unawaited(c.present(7));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Sur devis'), findsWidgets);
    expect(find.byKey(const ValueKey('flash-accept')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('flash-quote-amount')), '22 000');
    await t.tap(find.byKey(const ValueKey('flash-quote')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(server.posts['/handy/flash/offers/7/quote/'], {'amount': 22000, 'message': ''});
    expect(find.byKey(const ValueKey('flash-quoted')), findsOneWidget);
  });

  testWidgets('réglages : son et vibration enregistrés, aperçu qui explique le mode silencieux', (t) async {
    final (c, native, _, _) = await pumpApp(t);
    await t.tap(find.byKey(const ValueKey('flash-pref-vibration')));
    await t.pump();
    expect(native.vibration, isFalse);
    expect(c.vibrationOn, isFalse);
    native.playback = const FlashPlayback(ringer: 'silent');
    await t.tap(find.byKey(const ValueKey('flash-test-ring')));
    await t.pump();
    expect(native.played.last, 'tratra_flash:son:-');
    expect(find.text('Téléphone en mode silencieux : aucun son ni vibration.'), findsOneWidget);
    native.playback = const FlashPlayback(played: true);
    await t.tap(find.byKey(const ValueKey('flash-test-notification')));
    await t.pump();
    expect(native.played.last, 'tratra_notification:son:-');
  });

  test('liens profonds : proposition, demande, disponibilité, décision Trust', () {
    expect(parseDeepLink({'deeplink': 'tratra://flash_offer/7'}), const DeepLink(DeepLinkKind.flashOffer, id: 7));
    expect(parseDeepLink({'kind': 'flash_request', 'id': 3}), const DeepLink(DeepLinkKind.flashRequest, id: 3));
    expect(parseDeepLink({'kind': 'availability'}).kind, DeepLinkKind.availability);
    expect(parseDeepLink({'kind': 'trust_penalty', 'id': 2}).kind, DeepLinkKind.trustPenalty);
    expect(parseDeepLink({'kind': 'flash_offer'}).kind, DeepLinkKind.notifications, reason: 'sans identifiant : centre de notifications');
  });
}
