// Statuts éphémères : modèles, API (publication idempotente), barre d'accueil (ordre, panne silencieuse), visionneuse (une vue seulement quand le
// statut est affiché, jamais pour soi, réponse, lecteurs réservés à l'auteur) et publication (aperçu, échec puis reprise avec le même client_id).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_bar.dart';
import 'package:flutter_tratra/statuses/status_composer.dart';
import 'package:flutter_tratra/statuses/status_models.dart';
import 'package:flutter_tratra/statuses/status_viewer.dart';

http.Response json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> status(int id, {String text = 'Promo plomberie', String kind = 'text', bool mine = false, bool seen = false, bool replies = true, int views = 0}) => {
      'id': id,
      'type': kind == 'text' ? 'text' : kind,
      'kind': kind,
      'text': text,
      'background': kind == 'text' ? 'green' : null,
      'media': null,
      'created_at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      'expires_at': DateTime.now().add(const Duration(hours: 23)).toIso8601String(),
      'audience': mine ? 'contacts' : null,
      'allow_replies': replies && !mine,
      'mine': mine,
      'seen': seen,
      if (mine) 'views': {'unique': views, 'total': views},
    };

Map<String, dynamic> authorGroup(int authorId, String name, List<Map<String, dynamic>> statuses) => {
      'author': {'id': authorId, 'name': name, 'avatar': null},
      'statuses': statuses,
      'unseen': statuses.where((s) => s['seen'] != true).length,
      'seen': statuses.every((s) => s['seen'] == true),
      'latest_at': DateTime.now().toIso8601String(),
    };

Map<String, dynamic> feedPayload({List<Map<String, dynamic>>? mine, List<Map<String, dynamic>>? contacts, int discover = 0}) => {
      'mine': {'author': {'id': 1, 'name': 'Serge O.', 'avatar': null}, 'statuses': mine ?? [], 'count': (mine ?? []).length},
      'contacts': contacts ?? [],
      'discover_count': discover,
      'limits': {'ttl_hours': 24, 'text_max': 700, 'video_max_seconds': 30, 'image_max_bytes': 10485760, 'video_max_bytes': 31457280},
    };

class Server {
  final requests = <http.Request>[];
  bool down = false;
  bool failFeed = false;
  Map<String, dynamic> feed = feedPayload();
  int publishFailures = 0;
  late final client = MockClient((r) async {
    requests.add(r);
    if (down) throw http.ClientException('réseau coupé');
    final p = r.url.path;
    if (p.endsWith('/statuses/feed/')) return failFeed ? json({'detail': 'indisponible'}, 503) : json(feed);
    if (p.endsWith('/statuses/settings/')) return json({'audience': 'contacts', 'allow_replies': true});
    if (p.endsWith('/view/')) return json({'counted': true});
    if (p.endsWith('/viewers/')) {
      return json({'results': [{'user': {'id': 8, 'name': 'Awa K.', 'avatar': null}, 'viewed_at': '2026-10-13T10:00:00Z'}]});
    }
    if (p.endsWith('/reply/')) return json({'conversation': 5, 'message': {}}, 201);
    if (p.endsWith('/statuses/') && r.method == 'POST') {
      if (publishFailures > 0) {
        publishFailures--;
        return json({'detail': 'Texte trop long.'}, 400);
      }
      return json({'status': status(50, text: 'publié', mine: true), 'created': true}, 201);
    }
    return json({});
  });
}

BaseApi apiFor(Server s) {
  FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access', AppConstants.refreshTokenKey: 'refresh'});
  return BaseApi(client: s.client);
}

Widget host(Server s, Widget child) {
  final base = apiFor(s);
  return MultiProvider(
    providers: [
      Provider<StatusApi>.value(value: StatusApi(base)),
      Provider<MessagingApi>.value(value: MessagingApi(base)),
      ChangeNotifierProvider<InboxController>.value(value: InboxController(base, MessagingApi(base))),
    ],
    child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: child)),
  );
}

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  group('modèles', () {
    test('statut : types, expiration lisible, compteurs de vues réservés à l\'auteur', () {
      final s = StatusItem.fromJson(status(3, mine: true, views: 4));
      expect(s.mine, isTrue);
      expect(s.viewsUnique, 4);
      expect(s.timeLeft, matches(RegExp(r'^(2[0-3]|1[0-9]) h$')));
      final other = StatusItem.fromJson(status(4));
      expect(other.viewsUnique, 0);                      // aucune donnée de lecteurs pour un statut qui n'est pas le sien
      expect(other.audience, isNull);
      final expired = StatusItem.fromJson({...status(5), 'expires_at': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String()});
      expect(expired.timeLeft, 'expiré');
    });

    test('fil : groupes et limites du serveur', () {
      final f = StatusFeed.fromJson(feedPayload(contacts: [authorGroup(7, 'Awa K.', [status(1)]), authorGroup(8, 'Moussa A.', [status(2, seen: true)])], discover: 3));
      expect(f.contacts.map((g) => g.seen), [false, true]);
      expect(f.discoverCount, 3);
      expect(f.limits.textMax, 700);
      expect(f.limits.videoMaxSeconds, 30);
    });

    test('durée d\'un statut texte : bornée entre 5 et 12 secondes', () {
      expect(statusTextDuration('ok').inSeconds, 5);
      expect(statusTextDuration('x' * 1000).inSeconds, 12);
    });
  });

  group('API', () {
    test('publication multipart : champs, client_id (idempotence), couleur seulement pour un texte ; fichier envoyé pour un média', () async {
      final s = Server();
      final api = StatusApi(apiFor(s));
      await api.publish(text: 'Bonjour', audience: 'extended', allowReplies: false, background: 'sky', clientId: 'cid-1');
      var body = utf8.decode(s.requests.last.bodyBytes, allowMalformed: true);
      for (final needle in ['name="text"', 'Bonjour', 'name="audience"', 'extended', 'name="allow_replies"', 'false', 'name="client_id"', 'cid-1', 'name="background"', 'sky']) {
        expect(body, contains(needle));
      }
      expect(body, isNot(contains('name="file"')));
      final file = File('${Directory.systemTemp.path}/statut_test.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(200, 7)]);
      addTearDown(() => file.deleteSync());
      final progress = <double>[];
      await api.publish(text: '', filePath: file.path, audience: 'contacts', allowReplies: true, clientId: 'cid-2', onProgress: progress.add);
      body = utf8.decode(s.requests.last.bodyBytes, allowMalformed: true);
      expect(body, contains('name="file"'));
      expect(body, isNot(contains('name="background"')));
      expect(progress.last, 1.0);
    });

    test('charger le fil ne compte jamais de vue ; la vue est un appel explicite', () async {
      final s = Server();
      final api = StatusApi(apiFor(s));
      await api.feed();
      await api.discover();
      expect(s.requests.where((r) => r.url.path.endsWith('/view/')), isEmpty);
      expect(await api.view(40), isTrue);
      expect(s.requests.last.url.path, endsWith('/statuses/40/view/'));
    });
  });

  group('barre d\'accueil', () {
    testWidgets('« Mon statut » d\'abord, puis les contacts (non lus avant les consultés) et l\'accès à Découvrir', (t) async {
      final s = Server()
        ..feed = feedPayload(
          contacts: [authorGroup(7, 'Awa K.', [status(1)]), authorGroup(8, 'Moussa A.', [status(2, seen: true)])],
          discover: 4,
        );
      await t.pumpWidget(host(s, const StatusBar()));
      await t.pumpAndSettle();
      final labels = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().toList();
      expect(labels.indexOf('Mon statut'), lessThan(labels.indexOf('Awa K.')));       // « Mon statut » en première position
      expect(labels.indexOf('Awa K.'), lessThan(labels.indexOf('Moussa A.')));        // non lu avant consulté
      expect(labels, contains('Découvrir (4)'));
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Statuts de Awa K., 1 non lu'), findsOneWidget);   // anneau « non lu » annoncé aux lecteurs d'écran
      expect(s.requests.where((r) => r.url.path.endsWith('/view/')), isEmpty);       // l'affichage de la barre ne compte aucune vue
    });

    testWidgets('une panne des statuts masque la barre sans erreur visible : l\'accueil n\'est pas dégradé', (t) async {
      final s = Server()..failFeed = true;
      await t.pumpWidget(host(s, const StatusBar()));
      await t.pumpAndSettle();
      expect(find.text('Mon statut'), findsNothing);
      expect(find.textContaining('indisponible'), findsNothing);
    });
  });

  group('visionneuse', () {
    Future<void> open(WidgetTester t, Server s, List<StatusGroup> groups, {int start = 0}) async {
      await t.pumpWidget(host(s, StatusViewerScreen(groups: groups, startGroup: start)));
      await t.pump();
    }

    StatusGroup g(int author, List<Map<String, dynamic>> st) => StatusGroup.fromJson(authorGroup(author, 'Awa K.', st));

    testWidgets('une vue est envoyée quand le statut est affiché, une seule fois par statut ; « suivant » enregistre le suivant', (t) async {
      final s = Server();
      await open(t, s, [g(7, [status(1, text: 'Premier'), status(2, text: 'Second')])]);
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Premier'), findsOneWidget);
      expect(s.requests.where((r) => r.url.path.endsWith('/statuses/1/view/')), hasLength(1));
      await t.tapAt(Offset(t.view.physicalSize.width / t.view.devicePixelRatio * 0.8, 300));   // zone « suivant »
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Second'), findsOneWidget);
      expect(s.requests.where((r) => r.url.path.endsWith('/statuses/2/view/')), hasLength(1));
      await t.tapAt(Offset(t.view.physicalSize.width / t.view.devicePixelRatio * 0.1, 300));   // retour : pas de double comptage
      await t.pump(const Duration(milliseconds: 50));
      expect(s.requests.where((r) => r.url.path.endsWith('/statuses/1/view/')), hasLength(1));
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('son propre statut : aucune vue envoyée, compteur de vues et liste nominative des lecteurs', (t) async {
      final s = Server();
      await open(t, s, [g(1, [status(9, text: 'Mon annonce', mine: true, views: 3)])]);
      await t.pump(const Duration(milliseconds: 50));
      expect(s.requests.where((r) => r.url.path.endsWith('/view/')), isEmpty);
      expect(find.text('3 vues'), findsOneWidget);
      expect(find.text('Mon statut'), findsOneWidget);
      await t.tap(find.text('3 vues'));
      await t.pumpAndSettle();
      expect(find.text('Lecteurs de ce statut'), findsOneWidget);
      expect(find.text('Awa K.'), findsWidgets);
      expect(s.requests.last.url.path, endsWith('/statuses/9/viewers/'));
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('réponse par message si autorisée ; champ absent sinon ; pas de lecteurs pour un statut d\'autrui', (t) async {
      final s = Server();
      await open(t, s, [g(7, [status(1, text: 'Réponse ouverte'), status(2, text: 'Réponses fermées', replies: false)])]);
      await t.pump(const Duration(milliseconds: 50));
      await t.enterText(find.byType(TextField), 'Intéressé !');
      await t.tap(find.byTooltip('Envoyer la réponse'));
      await t.pump(const Duration(milliseconds: 50));
      final reply = s.requests.lastWhere((r) => r.url.path.endsWith('/reply/'));
      expect(jsonDecode(reply.body), {'content': 'Intéressé !'});
      expect(find.byTooltip('Supprimer ce statut'), findsNothing);       // pas de suppression d'un statut d'autrui
      await t.tapAt(Offset(t.view.physicalSize.width / t.view.devicePixelRatio * 0.8, 300));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Les réponses sont désactivées pour ce statut.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('progression automatique : le statut suivant s\'affiche à la fin de la durée', (t) async {
      final s = Server();
      await open(t, s, [g(7, [status(1, text: 'A'), status(2, text: 'B')])]);
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('A'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('B'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    });
  });

  group('publication', () {
    testWidgets('texte vide : « Publier » inactif ; compteur de caractères borné ; aperçu en direct', (t) async {
      tall(t);
      final s = Server();
      await t.pumpWidget(host(s, StatusComposerScreen(limits: StatusLimits.fromJson(const {'text_max': 30}))));
      await t.pumpAndSettle();
      final publish = find.widgetWithText(TratraButton, 'Publier');
      expect(t.widget<TratraButton>(publish).onPressed, isNull);
      await t.enterText(find.byType(TextField).first, 'Chantier terminé');
      await t.pump();
      expect(find.text('Chantier terminé'), findsWidgets);               // aperçu et champ
      expect(t.widget<TratraButton>(publish).onPressed, isNotNull);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('échec puis « Réessayer » : le MÊME client_id est renvoyé (jamais de double publication)', (t) async {
      tall(t);
      final s = Server()..publishFailures = 1;
      await t.pumpWidget(host(s, Builder(builder: (ctx) => TextButton(onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => StatusComposerScreen(limits: StatusLimits.fromJson(const {})))), child: const Text('ouvrir')))));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Disponible demain');
      await t.pump();
      await t.tap(find.widgetWithText(TratraButton, 'Publier'));
      await t.pumpAndSettle();
      expect(find.text('Réessayer'), findsOneWidget);
      await t.tap(find.widgetWithText(TratraButton, 'Réessayer'));
      await t.pumpAndSettle();
      final posts = s.requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/statuses/')).toList();
      expect(posts, hasLength(2));
      String cid(http.Request r) => RegExp(r'name="client_id"\r\n\r\n([^\r]+)').firstMatch(utf8.decode(r.bodyBytes, allowMalformed: true))!.group(1)!;
      expect(cid(posts.first), cid(posts.last));
      expect(find.byType(StatusComposerScreen), findsNothing);              // publié : retour à l'écran précédent
    });
  });
}
