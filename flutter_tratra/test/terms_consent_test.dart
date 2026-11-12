// Conditions d'utilisation : case jamais précochée et liens ouvrables à l'inscription, version annoncée au serveur, nouvelle version
// refusée par le serveur → la case est décochée (jamais d'acceptation supposée), Paramètres → Informations légales.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/legal.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/auth/register_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/legal_info_screen.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _field(String label) => find.descendant(of: find.widgetWithText(TratraInput, label), matching: find.byType(TextField));

Future<void> _fill(WidgetTester t) async {
  await t.enterText(_field('Prénom'), 'Awa');
  await t.enterText(_field('Nom'), 'Koné');
  await t.enterText(find.descendant(of: find.byType(TratraPhoneField), matching: find.byType(TextField)), '0700000000');
  await t.enterText(_field('Mot de passe'), 'Essai2026x');
  await t.enterText(_field('Confirmer le mot de passe'), 'Essai2026x');
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('inscription', () {
    late List<Map<String, dynamic>> signups;
    late List<http.Response> answers;

    Widget host() => MultiProvider(
          providers: [
            Provider<ApiService>(create: (_) => ApiService(client: MockClient((r) async {
                  if (r.url.path.endsWith('/users/')) {
                    signups.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
                    return answers.removeAt(0);
                  }
                  return _json({'detail': 'Non autorisé'}, 401);                    // connexion automatique : non (pas de stockage)
                }))),
            Provider<StorageService>(create: (_) => StorageService()),
            Provider<AuthService>(create: (_) => AuthService(BaseApi())),
          ],
          child: MaterialApp(
            theme: TratraTheme.light(),
            home: const RegisterScreen(),
            onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => Scaffold(body: Text('écran ${s.name}'))),
          ),
        );

    setUp(() {
      signups = [];
      answers = [];
    });

    testWidgets('case jamais précochée, liens ouvrables ; sans la case aucun compte n’est créé ; cochée : version annoncée', (t) async {
      _tall(t);
      await t.pumpWidget(host());
      await _fill(t);
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('terms-accept'))).value, isFalse);
      expect(find.text('J’accepte les Conditions d’utilisation et la politique de confidentialité.'), findsOneWidget);
      expect(find.byKey(const ValueKey('terms-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('privacy-open')), findsOneWidget);

      await _tap(t, find.text('Créer mon compte'));
      expect(signups, isEmpty, reason: 'aucune inscription sans consentement explicite');
      expect(find.textContaining('Cochez « J’accepte les Conditions d’utilisation »'), findsOneWidget);

      answers.add(_json({'id': 7, 'first_name': 'Awa', 'last_name': 'Koné', 'phone': '+2250700000000', 'user_type': 'client'}, 201));
      await _tap(t, find.byKey(const ValueKey('terms-accept')));
      await _tap(t, find.text('Créer mon compte'));
      expect(signups, hasLength(1));
      expect(signups.single['accept_terms'], isTrue);
      expect(signups.single['terms_version'], LegalLinks.termsVersion);
    });

    testWidgets('conditions modifiées depuis ce build : la case est décochée, la personne recoche, la version du serveur est annoncée', (t) async {
      _tall(t);
      await t.pumpWidget(host());
      await _fill(t);
      answers.add(_json({'code': 'terms_outdated', 'detail': 'Les conditions ont été mises à jour.', 'current_version': '2027-01-15'}, 400));
      await _tap(t, find.byKey(const ValueKey('terms-accept')));
      await _tap(t, find.text('Créer mon compte'));
      expect(signups.single['terms_version'], LegalLinks.termsVersion);
      expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('terms-accept'))).value, isFalse, reason: 'jamais d’acceptation supposée');
      expect(find.textContaining('ont été mises à jour'), findsOneWidget);

      await _tap(t, find.text('Créer mon compte'));
      expect(signups, hasLength(1), reason: 'case décochée : rien n’est envoyé');
      answers.add(_json({'id': 7, 'first_name': 'Awa', 'last_name': 'Koné', 'phone': '+2250700000000', 'user_type': 'client'}, 201));
      await _tap(t, find.byKey(const ValueKey('terms-accept')));
      await _tap(t, find.text('Créer mon compte'));
      expect(signups, hasLength(2));
      expect(signups.last['terms_version'], '2027-01-15');
    });
  });

  testWidgets('les liens ouvrent les pages publiques du site', (t) async {
    final opened = <Uri>[];
    await t.pumpWidget(MaterialApp(
      theme: TratraTheme.light(),
      home: Scaffold(body: TermsConsent(value: false, onChanged: (_) {}, opener: (_, uri) async => opened.add(uri))),
    ));
    await t.tap(find.byKey(const ValueKey('terms-open')));
    await t.tap(find.byKey(const ValueKey('privacy-open')));
    expect(opened.map((u) => '$u'), ['https://tratra.net/conditions-utilisation', 'https://tratra.net/confidentialite']);
  });

  group('Paramètres → Informations légales', () {
    Map<String, dynamic> status({String? accepted, String? at}) => {
          'current': {'version': '2026-11-12', 'updated_on': '2026-11-12', 'url': 'https://tratra.net/conditions-utilisation'},
          'accepted_version': accepted,
          'accepted_at': at,
          'up_to_date': accepted == '2026-11-12',
          'needs_acceptance': accepted != '2026-11-12',
        };

    Widget host(http.Client client, List<Uri> opened) {
      FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'access', AppConstants.refreshTokenKey: 'refresh'});
      return Provider<DashboardApi>.value(
        value: DashboardApi(BaseApi(client: client)),
        child: MaterialApp(theme: TratraTheme.light(), home: LegalInfoScreen(opener: (_, uri) async => opened.add(uri))),
      );
    }

    testWidgets('compte antérieur : nouvelle version proposée, acceptée seulement après la case cochée', (t) async {
      _tall(t);
      final posts = <Map>[];
      final opened = <Uri>[];
      final client = MockClient((r) async {
        if (r.method == 'POST') {
          posts.add(jsonDecode(r.body) as Map);
          return _json(status(accepted: '2026-11-12', at: '2026-11-12T10:00:00Z'));
        }
        return _json(status(at: '2026-10-01T09:00:00Z'));
      });
      await t.pumpWidget(host(client, opened));
      await t.pumpAndSettle();
      expect(find.text('Nouvelle version à lire'), findsOneWidget);
      expect(find.textContaining('avant leur version actuelle'), findsOneWidget);
      expect(t.widget<TratraButton>(find.byKey(const ValueKey('legal-accept'))).onPressed, isNull, reason: 'case non cochée');

      await _tap(t, find.byKey(const ValueKey('terms-accept')));
      await _tap(t, find.byKey(const ValueKey('legal-accept')));
      expect(posts.single, {'version': '2026-11-12', 'accept': true, 'source': 'app'});
      expect(find.text('Version acceptée'), findsOneWidget);
      expect(find.byKey(const ValueKey('legal-accept')), findsNothing);

      await _tap(t, find.byKey(const ValueKey('legal-deletion')));
      expect(opened.single.toString(), 'https://tratra.net/suppression-compte');
    });

    testWidgets('statut illisible (hors connexion, serveur antérieur) : les pages restent accessibles', (t) async {
      _tall(t);
      final opened = <Uri>[];
      await t.pumpWidget(host(MockClient((_) async => _json({'detail': 'introuvable'}, 404)), opened));
      await t.pumpAndSettle();
      expect(find.text('Statut indisponible'), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('legal-terms')));
      await _tap(t, find.byKey(const ValueKey('legal-privacy')));
      expect(opened.map((u) => '$u'), ['https://tratra.net/conditions-utilisation', 'https://tratra.net/confidentialite']);
    });
  });
}
