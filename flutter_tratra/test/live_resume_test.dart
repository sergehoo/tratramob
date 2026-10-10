// Suivi live : reprise après coupure réseau, retour au premier plan et connexion « fantôme ».
// Aucune vraie socket : le serveur et la WebSocket sont simulés ; ce sont les règles du contrôleur qui sont vérifiées.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/screens/live/live_controller.dart';

Map<String, dynamic> snapshot({String phase = 'confirmed'}) => {
      'booking_id': 11,
      'role': 'client',
      'phase': phase,
      'status': 'confirmed',
      'window_open': true,
      'consent': {'artisan': false, 'client': false},
      'can': {'start_route': false, 'arrive': false, 'share_position': false},
      'artisan': {'sharing': false, 'position': null},
      'client': {'sharing': false, 'position': null},
      'destination': {'lat': 5.36, 'lng': -4.0083, 'source': 'booking'},
      'route': null,
    };

class FakeSink implements WebSocketSink {
  FakeSink(this.socket);
  final FakeSocket socket;
  @override
  Future<void> close([int? closeCode, String? closeReason]) async => socket.closedByClient = true;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> get done async {}
}

class FakeSocket extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  bool closedByClient = false;
  Completer<void> readyCompleter = Completer<void>();

  FakeSocket({bool opens = true}) {
    if (opens) readyCompleter.complete();
  }

  void push(Map<String, dynamic> state) => incoming.add(jsonEncode({'type': 'state', 'state': state}));
  void dropFromServer() => incoming.close();

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => FakeSink(this);
  @override
  Future<void> get ready => readyCompleter.future;
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

class Harness {
  Harness({this.backoff = const Duration(milliseconds: 20), this.watchdog = const Duration(seconds: 45)}) {
    FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access'});
    final client = MockClient((http.Request r) async {
      if (hang) {
        hungRequests++;
        return Completer<http.Response>().future; // le serveur ne répond jamais (connexion fantôme)
      }
      if (networkDown) throw http.ClientException('réseau coupé');
      if (r.url.path.endsWith('/ticket/')) {
        tickets++;
        return http.Response(jsonEncode({'ticket': 't$tickets', 'path': '/ws/live/11/'}), 200);
      }
      return http.Response(jsonEncode(snapshot()), 200);
    });
    controller = LiveController(
      BaseApi(client: client),
      11,
      connect: (uri) {
        connects.add(uri);
        if (networkDown) throw StateError('connexion impossible');
        final s = FakeSocket();
        sockets.add(s);
        return s;
      },
      pollEvery: const Duration(milliseconds: 40),
      watchdogAfter: watchdog,
      backoff: (_) => backoff,
      requestTimeout: const Duration(milliseconds: 150),
    );
  }

  final Duration backoff;
  final Duration watchdog;
  late final LiveController controller;
  final sockets = <FakeSocket>[];
  final connects = <Uri>[];
  int tickets = 0;
  int hungRequests = 0;
  bool networkDown = false;
  bool hang = false;
}

Future<void> settle([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le délai de reconnexion est progressif, plafonné et sans débordement', () {
    final delays = [for (var n = 1; n <= 200; n++) liveReconnectDelay(n)];
    expect(delays.first, const Duration(seconds: 2));
    expect(delays.every((d) => d >= const Duration(seconds: 2) && d <= const Duration(seconds: 30)), isTrue);
    expect(delays.last, const Duration(seconds: 30)); // 1 << 200 ne boucle plus à 1 s
    for (var i = 1; i < delays.length; i++) {
      expect(delays[i] >= delays[i - 1], isTrue);
    }
  });

  test('connexion temps réel : billet signé, WebSocket ouverte, états poussés appliqués', () async {
    final h = Harness();
    h.controller.start();
    await settle();
    expect(h.sockets, hasLength(1));
    expect(h.connects.single.scheme, 'wss'); // base HTTPS → WebSocket chiffrée
    expect(h.connects.single.queryParameters['ticket'], 't1');
    expect(h.controller.realtime, isTrue);
    h.sockets.single.push(snapshot(phase: 'en_route'));
    await settle(20);
    expect(h.controller.state?.phase, 'en_route');
    h.controller.dispose();
  });

  test('coupure côté serveur : reconnexion automatique avec un nouveau billet', () async {
    final h = Harness(backoff: const Duration(milliseconds: 150));
    h.controller.start();
    await settle();
    h.sockets.first.dropFromServer();
    await settle(30);
    expect(h.controller.realtime, isFalse);
    await settle(300);
    expect(h.sockets, hasLength(2));
    expect(h.tickets, 2);
    expect(h.connects.last.queryParameters['ticket'], 't2'); // jamais de billet réutilisé
    expect(h.controller.realtime, isTrue);
    h.controller.dispose();
  });

  test('retour au premier plan : ancienne connexion fermée, une seule nouvelle, aucun doublon', () async {
    final h = Harness(backoff: const Duration(milliseconds: 20));
    h.controller.start();
    await settle();
    h.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(h.sockets, hasLength(2));
    expect(h.sockets.first.closedByClient, isTrue);
    expect(h.controller.realtime, isTrue);
    // l'ancienne connexion signale sa fin APRÈS son remplacement : aucune reconnexion parasite
    h.sockets.first.dropFromServer();
    await settle(300);
    expect(h.sockets, hasLength(2));
    expect(h.controller.realtime, isTrue);
    h.controller.dispose();
  });

  test('réseau coupé puis rétabli : hors ligne signalé, reprise immédiate sans attendre le délai de reconnexion', () async {
    final h = Harness(backoff: const Duration(minutes: 10)); // si la reprise attendait ce délai, le test échouerait
    h.controller.start();
    await settle();
    expect(h.controller.realtime, isTrue);

    h.networkDown = true;
    h.sockets.first.dropFromServer();
    await settle(250);
    expect(h.controller.offline, isTrue);
    expect(h.controller.realtime, isFalse);

    h.networkDown = false; // le réseau revient : la prochaine lecture réussit
    await settle(250);
    expect(h.controller.offline, isFalse);
    expect(h.controller.realtime, isTrue);
    expect(h.sockets, hasLength(2));
    h.controller.dispose();
  });

  test('connexion fantôme (changement de réseau) : le silence prolongé déclenche une vérification puis la réouverture', () async {
    final h = Harness(watchdog: const Duration(milliseconds: 100));
    h.controller.start();
    await settle();
    expect(h.sockets, hasLength(1));
    // La WebSocket paraît ouverte mais ne transmet plus rien ; le réseau a changé et la lecture directe échoue.
    h.networkDown = true;
    await settle(250);
    expect(h.controller.offline, isTrue);
    h.networkDown = false;
    await settle(300);
    expect(h.sockets.length, greaterThanOrEqualTo(2));
    expect(h.sockets.first.closedByClient, isTrue);
    expect(h.controller.realtime, isTrue);
    expect(h.controller.offline, isFalse);
    h.controller.dispose();
  });

  test('arrêt : plus aucune reconnexion ni lecture après dispose', () async {
    final h = Harness();
    h.controller.start();
    await settle();
    h.sockets.first.dropFromServer();
    h.controller.dispose();
    final before = (h.tickets, h.sockets.length);
    await settle(300);
    expect((h.tickets, h.sockets.length), before);
    expect(h.sockets.first.closedByClient, isTrue);
  });

  test('serveur muet : les requêtes expirent, le mode hors ligne s’affiche et aucune requête ne s’empile', () async {
    final h = Harness();
    h.hang = true;
    h.controller.start();
    await settle(900); // ~22 cycles de lecture à 40 ms si rien n'était protégé
    expect(h.controller.offline, isTrue);
    expect(h.hungRequests, lessThan(14)); // au plus une lecture + un billet en cours à la fois, pas une par cycle
    h.hang = false; // le serveur répond de nouveau
    await settle(900);
    expect(h.controller.offline, isFalse);
    expect(h.controller.realtime, isTrue);
    h.controller.dispose();
  });
}
