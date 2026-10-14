// Messagerie : modèles, API (idempotence, curseurs, progression d'envoi), temps réel (billet, réception, accusé, reprise après coupure,
// rattrapage) et écran de conversation (états d'envoi, échec puis renvoi sans doublon). Aucun réseau réel.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/chat_models.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/screens/dashboard/messages_screen.dart';

Map<String, dynamic> msg(int id, {bool mine = false, String content = 'Bonjour', String state = 'sent', String? clientId, int conv = 5, Map<String, dynamic>? attachment, Map<String, dynamic>? context}) => {
      'id': id,
      'conversation': conv,
      'mine': mine,
      'content': content,
      'kind': attachment == null ? 'text' : (attachment['kind'] ?? 'image'),
      'created_at': '2026-10-13T10:0$id:00Z',
      'is_read': state == 'read',
      'state': state,
      'client_id': clientId,
      'sender': mine ? 'Moi' : 'Awa K.',
      'via_staff': false,
      'attachment': attachment,
      'context': context,
    };

Map<String, dynamic> conv({int id = 5, String kind = 'direct', int unread = 0, bool blocked = false, bool canSend = true}) => {
      'id': id, 'kind': kind, 'booking_id': null, 'counterpart': kind == 'support' ? 'Équipe Tratra' : 'Awa K.', 'counterpart_id': kind == 'support' ? null : 7,
      'last_message': 'Bonjour', 'last_at': '2026-10-13T10:05:00Z', 'unread': unread, 'blocked': blocked, 'can_send': canSend,
    };

class FakeSink implements WebSocketSink {
  FakeSink(this.socket);
  final FakeSocket socket;
  @override
  Future<void> close([int? closeCode, String? closeReason]) async => socket.closedByClient = true;
  @override
  void add(dynamic data) => socket.sent.add('$data');
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> get done async {}
}

class FakeSocket extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <String>[];
  bool closedByClient = false;
  final Completer<void> readyCompleter = Completer<void>()..complete();
  void push(Map<String, dynamic> event) => incoming.add(jsonEncode(event));
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

http.Response json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

class Server {
  final requests = <http.Request>[];
  int tickets = 0;
  bool down = false;
  List<Map<String, dynamic>> syncMessages = [];
  Map<String, dynamic> Function(http.Request)? onSend;
  late final client = MockClient((r) async {
    requests.add(r);
    if (down) throw http.ClientException('réseau coupé');
    final p = r.url.path;
    if (p.endsWith('/realtime/ticket/')) {
      tickets++;
      return json({'ticket': 't$tickets', 'path': '/ws/inbox/', 'expires_in': 60}, 200);
    }
    if (p.endsWith('/messages/unread/')) return json({'total': 2, 'conversations': {}}, 200);
    if (p.endsWith('/messages/sync/')) {
      return json({'messages': syncMessages, 'conversations': [conv(unread: syncMessages.length)], 'last_id': syncMessages.isEmpty ? 0 : syncMessages.last['id'], 'has_more': false, 'unread_total': syncMessages.length}, 200);
    }
    if (p.endsWith('/send/')) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final custom = onSend?.call(r);
      return json(custom ?? {'message': msg(9, mine: true, content: '${body['content']}', clientId: '${body['client_id']}'), 'created': true}, 201);
    }
    if (p.endsWith('/read/')) return json({'marked': 1, 'unread_total': 0}, 200);
    if (p.contains('/me/conversations/') && p.endsWith('/messages/')) {
      return json({'conversation': conv(), 'results': [msg(1, state: 'delivered'), msg(2, mine: true, content: 'Oui', state: 'delivered'), msg(3, mine: true, content: 'Merci', state: 'read')], 'has_more': false, 'next_before': null}, 200);
    }
    return http.Response('{}', 200);
  });
}

BaseApi apiFor(Server s) {
  FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access', AppConstants.refreshTokenKey: 'refresh'});
  return BaseApi(client: s.client);
}

void main() {
  group('modèles', () {
    test('message : états, pièce jointe, contexte de réponse à un statut', () {
      final m = ChatMessage.fromJson(msg(4, mine: true, state: 'delivered', clientId: 'abc', attachment: {'url': '/media/chat/x.jpg', 'kind': 'image', 'mime': 'image/jpeg', 'size': 1200, 'name': 'x.jpg'}, context: {'status': 12, 'text': 'Promo'}));
      expect(m.state, 'delivered');
      expect(m.attachment!.kind, 'image');
      expect(m.statusContext!['status'], 12);
      expect(m.copyWith(state: 'read').state, 'read');
      expect(resolveMediaUrl(m.attachment!.url!), startsWith('http'));          // URL relative résolue contre l'API
      expect(resolveMediaUrl('https://cdn.test/a.jpg'), 'https://cdn.test/a.jpg');
    });

    test('conversation : fil « Équipe Tratra » et blocage', () {
      final support = ChatConversation.fromJson(conv(kind: 'support'));
      expect(support.isSupport, isTrue);
      expect(support.counterpartId, isNull);
      final blocked = ChatConversation.fromJson(conv(blocked: true, canSend: false));
      expect(blocked.blocked && !blocked.canSend, isTrue);
    });

    test('identifiant d\'envoi : UUID v4, jamais deux fois le même', () {
      final ids = {for (var i = 0; i < 50; i++) newClientId()};
      expect(ids.length, 50);
      expect(ids.first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });

  group('API', () {
    test('envoi : client_id transmis, réponse typée ; curseur « before » et rattrapage « after »', () async {
      final s = Server();
      final api = MessagingApi(apiFor(s));
      final m = await api.send(5, content: 'Bonjour', clientId: 'cid-1');
      expect(m.clientId, 'cid-1');
      expect(jsonDecode(s.requests.last.body), {'content': 'Bonjour', 'client_id': 'cid-1'});
      expect(s.requests.last.headers['Authorization'], 'Bearer access');
      await api.thread(5, before: 42, limit: 20);
      expect(s.requests.last.url.query, 'limit=20&before=42');
      await api.sync(17);
      expect(s.requests.last.url.query, 'after=17');
      expect(await api.unreadTotal(), 2);
    });

    test('envoi multipart : progression jusqu\'à 100 %, champs et fichier envoyés, session rafraîchie sur 401 puis un seul renvoi', () async {
      var attempts = 0;
      final seen = <String>[];
      FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'old', AppConstants.refreshTokenKey: 'refresh'});
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/auth/refresh/')) return http.Response(jsonEncode({'access': 'fresh'}), 200);
        attempts++;
        seen.add('${r.headers['Authorization']}');
        if (attempts == 1) return http.Response('{}', 401);
        final body = utf8.decode(r.bodyBytes, allowMalformed: true);
        expect(body, contains('name="client_id"'));
        expect(body, contains('cid-9'));
        expect(body, contains('name="file"'));
        return http.Response(jsonEncode({'message': msg(9, mine: true, clientId: 'cid-9', attachment: {'url': 'https://cdn/x.jpg', 'kind': 'image'})}), 201);
      });
      final progress = <double>[];
      final r = await BaseApi(client: client).uploadMultipart(
        '/me/conversations/5/send/',
        fields: {'content': 'photo', 'client_id': 'cid-9'},
        files: [() async => http.MultipartFile.fromBytes('file', List<int>.filled(70000, 1), filename: 'a.jpg')],
        onProgress: progress.add,
      );
      expect(r.statusCode, 201);
      expect(seen, ['Bearer old', 'Bearer fresh']);
      expect(progress.last, 1.0);
      // la progression ne recule jamais, sauf au redémarrage du seul renvoi après 401
      var resets = 0;
      for (var i = 1; i < progress.length; i++) {
        if (progress[i] < progress[i - 1]) resets++;
      }
      expect(resets, 1);
    });
  });

  group('temps réel', () {
    late Server server;
    late List<FakeSocket> sockets;
    late InboxController inbox;

    setUp(() {
      server = Server();
      sockets = [];
      inbox = InboxController(apiFor(server), MessagingApi(apiFor(server)),
          connect: (uri) {
            expect(uri.path, '/ws/inbox/');
            expect(uri.queryParameters['ticket'], startsWith('t'));
            final s = FakeSocket();
            sockets.add(s);
            return s;
          },
          pollEvery: const Duration(milliseconds: 30),
          backoff: (_) => const Duration(milliseconds: 20),
          requestTimeout: const Duration(milliseconds: 200));
    });

    tearDown(() => inbox.dispose());

    Future<void> settle([int ms = 80]) => Future<void>.delayed(Duration(milliseconds: ms));

    test('connexion par billet signé, message reçu, accusé « distribué » envoyé, compteur mis à jour', () async {
      final got = <InboxEvent>[];
      inbox.events.listen(got.add);
      await inbox.bindUser('9');
      await settle();
      expect(inbox.status, InboxStatus.live);
      expect(server.tickets, 1);
      sockets.single.push({'type': 'message', 'message': msg(11, content: 'Salut'), 'conversation': conv(unread: 1), 'unread_total': 3});
      await settle();
      final e = got.firstWhere((x) => x.type == 'message');
      expect(e.message!.content, 'Salut');
      expect(e.conversation!.unread, 1);
      expect(inbox.unread, 3);
      expect(inbox.lastMessageId, 11);
      expect(sockets.single.sent.map(jsonDecode), contains(equals({'type': 'ack', 'ids': [11]})));
      // un message envoyé par soi-même n'est jamais acquitté
      sockets.single.push({'type': 'message', 'message': msg(12, mine: true), 'conversation': conv(), 'unread_total': 3});
      await settle();
      expect(sockets.single.sent.length, 1);
    });

    test('coupure : hors ligne signalé, nouveau billet, reconnexion et rattrapage des messages manqués par l\'API', () async {
      final got = <InboxEvent>[];
      final statuses = <InboxStatus>[];
      inbox.events.listen(got.add);
      inbox.addListener(() => statuses.add(inbox.status));
      await inbox.bindUser('9');
      await settle();
      sockets.single.push({'type': 'message', 'message': msg(11), 'conversation': conv(unread: 1), 'unread_total': 1});
      await settle();
      server.syncMessages = [msg(12, content: 'Manqué pendant la coupure'), msg(13, content: 'Manqué aussi')];
      sockets.single.dropFromServer();
      await settle(250);
      expect(statuses, contains(InboxStatus.offline));            // la coupure est signalée…
      expect(inbox.status, InboxStatus.live);                     // …puis la connexion est rétablie toute seule
      expect(server.tickets, greaterThanOrEqualTo(2));
      expect(sockets.length, greaterThanOrEqualTo(2));
      final replayed = got.where((x) => x.type == 'message').map((x) => x.message!.id).toList();
      expect(replayed, containsAll([11, 12, 13]));
      expect(inbox.lastMessageId, 13);
      expect(got.where((x) => x.type == 'resync'), isNotEmpty);
      expect(server.requests.any((r) => r.url.path.endsWith('/messages/sync/') && r.url.queryParameters['after'] == '11'), isTrue);
    });

    test('lecture sur un autre appareil : seul le compteur est synchronisé, aucun évènement « lu » ne touche mes propres messages', () async {
      final got = <InboxEvent>[];
      inbox.events.listen(got.add);
      await inbox.bindUser('9');
      await settle();
      sockets.single.push({'type': 'read_self', 'conversation': 5, 'count': 2, 'unread_total': 0});
      await settle();
      expect(inbox.unread, 0);
      expect(got.where((e) => e.type == 'read'), isEmpty);
      expect(got.where((e) => e.type == 'resync'), isNotEmpty);
    });

    test('accusés, lectures et évènements de statuts sont relayés ; changement de compte coupe la connexion', () async {
      final got = <InboxEvent>[];
      inbox.events.listen(got.add);
      await inbox.bindUser('9');
      await settle();
      sockets.single.push({'type': 'delivered', 'ids': [2, 3]});
      sockets.single.push({'type': 'read', 'conversation': 5, 'upto': 3, 'count': 2});
      sockets.single.push({'type': 'status', 'action': 'new', 'author': 7, 'status': 40});
      sockets.single.push({'type': 'inconnu', 'x': 1});
      await settle();
      expect(got.where((x) => x.type == 'delivered').single.ids, [2, 3]);
      expect(got.where((x) => x.type == 'read').single.upto, 3);
      expect(got.where((x) => x.type == 'status'), hasLength(1));
      await inbox.bindUser(null);
      expect(sockets.single.closedByClient, isTrue);
      expect(inbox.unread, 0);
    });
  });

  group('écran de conversation', () {
    Widget host(Server s, {InboxController? inbox}) {
      final base = apiFor(s);
      final api = MessagingApi(base);
      return MultiProvider(
        providers: [
          Provider<MessagingApi>.value(value: api),
          ChangeNotifierProvider<InboxController>.value(value: inbox ?? InboxController(base, api)),
        ],
        child: MaterialApp(theme: TratraTheme.light(), home: const ConversationScreen(conversationId: 5, title: 'Awa K.')),
      );
    }

    testWidgets('messages persistants affichés avec leurs états d\'envoi, lecture marquée côté serveur', (t) async {
      final s = Server();
      await t.pumpWidget(host(s));
      await t.pumpAndSettle();
      expect(find.text('Bonjour'), findsOneWidget);
      expect(find.text('Oui'), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNWidgets(2));       // « distribué » et « lu »
      expect(s.requests.any((r) => r.url.path.endsWith('/read/')), isTrue); // message reçu non lu : marqué lu
    });

    testWidgets('échec réseau : message conservé, « Renvoyer » réutilise le MÊME client_id, un seul message à la fin', (t) async {
      final s = Server();
      await t.pumpWidget(host(s));
      await t.pumpAndSettle();
      s.down = true;
      await t.enterText(find.byType(TextField).last, 'Je passe demain');
      await t.tap(find.text('Envoyer'));
      await t.pumpAndSettle();
      expect(find.text('Renvoyer'), findsOneWidget);
      expect(find.text('Je passe demain'), findsOneWidget);
      final firstAttempt = jsonDecode(s.requests.last.body)['client_id'];
      s.down = false;
      await t.tap(find.text('Renvoyer'));
      await t.pumpAndSettle();
      final sends = s.requests.where((r) => r.url.path.endsWith('/send/')).toList();
      expect(sends.length, greaterThanOrEqualTo(2));
      expect(jsonDecode(sends.last.body)['client_id'], firstAttempt);
      expect(find.text('Renvoyer'), findsNothing);
      expect(find.text('Je passe demain'), findsOneWidget);                // pas de doublon
    });

    testWidgets('un évènement temps réel ajoute le message sans recharger ; un message déjà présent n\'est pas dupliqué', (t) async {
      final s = Server();
      final base = apiFor(s);
      final fake = FakeSocket();
      final inbox = InboxController(base, MessagingApi(base), connect: (_) => fake, pollEvery: const Duration(hours: 1));
      await t.pumpWidget(host(s, inbox: inbox));
      await t.pumpAndSettle();
      await inbox.bindUser('9');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      fake.push({'type': 'message', 'message': msg(20, content: 'En direct !'), 'conversation': conv(unread: 1), 'unread_total': 1});
      fake.push({'type': 'message', 'message': msg(20, content: 'En direct !'), 'conversation': conv(unread: 1), 'unread_total': 1});
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pumpAndSettle();
      expect(find.text('En direct !'), findsOneWidget);
      await inbox.bindUser(null);
      await t.pumpWidget(const SizedBox.shrink());
      inbox.dispose();
    });
  });
}
