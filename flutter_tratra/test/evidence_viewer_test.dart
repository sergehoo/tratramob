// Pièces justificatives privées : ouverture SÛRE des PDF (contrôle de signature et de taille, lecture dans l'application, copies
// temporaires supprimées), jeton de session jamais envoyé hors de l'origine de l'API, niveau de preuve d'un paiement affiché
// sans jamais prétendre « vérifié » — sans réseau ni moteur natif.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/engagements/labels.dart';

Uint8List pdf([int extra = 0]) => Uint8List.fromList([...utf8.encode('%PDF-1.4\n%reçu\n'), ...List.filled(extra, 0x20)]);

// PNG 1×1 valide.
final png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

// L'origine de l'API est celle de la configuration (TRATRA_API_BASE) : les tests s'y adaptent.
final origin = Uri.parse(AppConstants.baseUrl).origin;

({EngagementsApi api, List<http.Request> calls}) fakeApi(http.Response Function(http.Request r) handler) {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'access-secret'});
  final calls = <http.Request>[];
  final client = MockClient((r) async {
    calls.add(r);
    return handler(r);
  });
  return (api: EngagementsApi(BaseApi(client: client)), calls: calls);
}

Widget host(EngagementsApi api, Widget home) => Provider<EngagementsApi>.value(value: api, child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: home)));

void main() {
  group('contrôle des pièces', () {
    test('signature PDF : exigée dans les 1024 premiers octets', () {
      expect(EvidenceFiles.looksLikePdf(pdf()), isTrue);
      expect(EvidenceFiles.looksLikePdf(Uint8List.fromList([...List.filled(200, 0x20), ...ascii.encode('%PDF-1.7')])), isTrue);
      expect(EvidenceFiles.looksLikePdf(Uint8List.fromList([...List.filled(1100, 0x20), ...ascii.encode('%PDF-1.7')])), isFalse);
      expect(EvidenceFiles.looksLikePdf(png), isFalse);
      expect(EvidenceFiles.looksLikePdf(Uint8List.fromList(ascii.encode('<html>%PD</html>'))), isFalse);
      expect(EvidenceFiles.looksLikePdf(Uint8List(0)), isFalse);
    });

    test('refus : vide ou trop volumineux ; sinon acceptable', () {
      expect(EvidenceFiles.refusal(Uint8List(0)), isNotNull);
      expect(EvidenceFiles.refusal(Uint8List(EvidenceFiles.maxBytes + 1)), contains('trop volumineux'));
      expect(EvidenceFiles.refusal(pdf()), isNull);
    });
  });

  group('copies temporaires', () {
    late Directory temp, docs;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('tratra_cache_');
      docs = Directory.systemTemp.createTempSync('tratra_docs_');
    });
    tearDown(() {
      temp.deleteSync(recursive: true);
      docs.deleteSync(recursive: true);
    });

    test('purge : seules les copies du moteur PDF disparaissent, jamais les autres fichiers', () async {
      const hex = '0123456789abcdef0123456789abcdef';
      File('${temp.path}/$hex.pdf').writeAsBytesSync(pdf());
      File('${temp.path}/${hex.replaceRange(0, 1, 'f')}.jpg').writeAsBytesSync(png);
      File('${temp.path}/rapport.pdf').writeAsStringSync('à conserver');
      File('${temp.path}/$hex.txt').writeAsStringSync('à conserver aussi');
      Directory('${temp.path}/pdf_renderer_cache').createSync();
      File('${temp.path}/pdf_renderer_cache/page.png').writeAsBytesSync(png);
      Directory('${docs.path}/pdf_renderer_cache').createSync();
      File('${docs.path}/pdf_renderer_cache/p.png').writeAsBytesSync(png);
      File('${docs.path}/contrat-signe.pdf').writeAsStringSync('mon document');

      final removed = await EvidenceFiles.purge(temp: temp, documents: docs);

      expect(removed, 4);
      expect(temp.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toSet(), {'rapport.pdf', '$hex.txt'});
      expect(docs.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last).toSet(), {'contrat-signe.pdf'});
    });

    test('purge : dossier absent ou illisible, aucune exception', () async {
      final gone = Directory('${temp.path}/inexistant');
      expect(await EvidenceFiles.purge(temp: gone, documents: gone), 0);
    });
  });

  group('téléchargement', () {
    test('le jeton n’est envoyé qu’à l’origine de l’API ; toute autre origine est refusée sans requête', () async {
      final f = fakeApi((r) => http.Response.bytes(pdf(), 200));
      await f.api.download('/handy/engagements/evidence/payment/4/');
      expect(f.calls.single.url.toString(), '$origin/handy/engagements/evidence/payment/4/');
      expect(f.calls.single.headers['Authorization'], 'Bearer access-secret');
      await f.api.download('$origin/handy/engagements/evidence/payment/5/');
      expect(f.calls, hasLength(2));
      final host = Uri.parse(origin).host;
      for (final evil in ['https://pirate.example/vol', 'http://$host/handy/x', 'https://$host.pirate.example/x', 'https://$host:8443/x']) {
        await expectLater(f.api.download(evil), throwsA(isA<ApiException>()));
      }
      expect(f.calls, hasLength(2), reason: 'aucune requête (donc aucun jeton) vers une autre origine');
    });
  });

  group('lecture dans l’application', () {
    Json evidence(String name) => {'name': name, 'url': '/handy/engagements/evidence/payment/4/'};

    testWidgets('PDF : ouvert dans le lecteur interne, jamais confié à une application tierce', (t) async {
      final f = fakeApi((r) => http.Response.bytes(pdf(2048), 200));
      Uint8List? shown;
      await t.pumpWidget(host(f.api, EvidenceLink(api: f.api, evidence: evidence('recu.pdf'), pdfBodyBuilder: (ctx, b) {
        shown = b;
        return const Text('corps-du-lecteur');
      })));
      await t.tap(find.text('Voir la pièce jointe'));
      await t.pumpAndSettle();
      expect(find.text('corps-du-lecteur'), findsOneWidget);
      expect(find.text('Pièce jointe (PDF)'), findsOneWidget);
      expect(find.textContaining('Privée : visible des deux parties seulement'), findsOneWidget);
      expect(shown!.length, pdf(2048).length);
      await t.tap(find.byType(CloseButton));
      await t.pumpAndSettle();
      expect(find.text('corps-du-lecteur'), findsNothing);
      expect(f.calls, hasLength(1));
    });

    testWidgets('faux PDF : message clair, aucun moteur sollicité', (t) async {
      final f = fakeApi((r) => http.Response.bytes(ascii.encode('<html><script>alert(1)</script></html>'), 200));
      var built = false;
      await t.pumpWidget(host(f.api, EvidenceLink(api: f.api, evidence: evidence('recu.pdf'), pdfBodyBuilder: (ctx, b) {
        built = true;
        return const Text('ne doit pas s’afficher');
      })));
      await t.tap(find.text('Voir la pièce jointe'));
      await t.pumpAndSettle();
      expect(find.text('Ce fichier n’est pas un PDF valide.'), findsOneWidget);
      expect(built, isFalse);
    });

    testWidgets('pièce trop volumineuse : refusée sous le lien, rien ne s’ouvre', (t) async {
      final f = fakeApi((r) => http.Response.bytes(pdf(EvidenceFiles.maxBytes), 200));
      await t.pumpWidget(host(f.api, EvidenceLink(api: f.api, evidence: evidence('gros.pdf'), pdfBodyBuilder: (ctx, b) => const Text('ne doit pas s’afficher'))));
      await t.tap(find.text('Voir la pièce jointe'));
      await t.pumpAndSettle();
      expect(find.textContaining('trop volumineux'), findsOneWidget);
      expect(find.text('ne doit pas s’afficher'), findsNothing);
    });

    testWidgets('image : affichée dans une feuille privée', (t) async {
      final f = fakeApi((r) => http.Response.bytes(png, 200));
      await t.pumpWidget(host(f.api, EvidenceLink(api: f.api, evidence: evidence('recu.png'))));
      await t.tap(find.text('Voir la pièce jointe'));
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('Privée : visible des deux parties seulement'), findsOneWidget);
    });

    testWidgets('erreur serveur : message réel, pas de lecteur', (t) async {
      final f = fakeApi((r) => http.Response(jsonEncode({'detail': 'Introuvable.'}), 404, headers: {'content-type': 'application/json'}));
      await t.pumpWidget(host(f.api, EvidenceLink(api: f.api, evidence: evidence('recu.pdf'), pdfBodyBuilder: (ctx, b) => const Text('ne doit pas s’afficher'))));
      await t.tap(find.text('Voir la pièce jointe'));
      await t.pumpAndSettle();
      expect(find.text('ne doit pas s’afficher'), findsNothing);
      expect(find.byType(Text).evaluate().any((e) => (e.widget as Text).data == 'Voir la pièce jointe'), isTrue);
    });
  });
}
