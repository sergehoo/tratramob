// Suppression de son propre compte : blocages affichés tels que le serveur les renvoie, confirmation obligatoire,
// mauvais mot de passe sans déconnexion, succès => session purgée et retour à la connexion.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/delete_account_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

class _FakeApi extends DashboardApi {
  _FakeApi(this.state, {this.postError}) : super(BaseApi());
  final Map<String, dynamic> state;
  final ApiException? postError;
  final posts = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getMap(String path) async => state;

  @override
  Future<Map<String, dynamic>> post(String path, [Object? body]) async {
    posts.add((body as Map).cast<String, dynamic>());
    if (postError != null) throw postError!;
    return {'deleted': true};
  }
}

class _FakeSession extends Session {
  _FakeSession() : super(AuthService(BaseApi()), StorageService());
  bool loggedOut = false;

  @override
  Future<void> logout() async => loggedOut = true;
}

Widget _host(_FakeApi api, _FakeSession session) => MultiProvider(
      providers: [
        Provider<DashboardApi>.value(value: api),
        ChangeNotifierProvider<Session>.value(value: session),
      ],
      child: MaterialApp(
        theme: TratraTheme.light(),
        home: const DeleteAccountScreen(),
        routes: {RouteNames.login: (_) => const Scaffold(body: Text('ÉCRAN CONNEXION'))},
      ),
    );

Finder get _delete => find.widgetWithText(TratraButton, 'Supprimer mon compte');

Future<void> _fill(WidgetTester t, {String password = 'secret123', String confirm = 'SUPPRIMER'}) async {
  final fields = find.byType(TextField);
  await t.enterText(fields.at(0), password);
  await t.enterText(fields.at(1), confirm);
  await t.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('blocages : raisons du serveur affichées, aucun champ ni bouton de suppression', (t) async {
    final api = _FakeApi({
      'allowed': false,
      'confirm_word': 'SUPPRIMER',
      'blockers': [
        {'code': 'open_booking', 'detail': 'Une réservation est en cours.'},
        {'code': 'wallet_balance', 'detail': 'Un solde est à retirer.'},
      ],
    });
    await t.pumpWidget(_host(api, _FakeSession()));
    await t.pumpAndSettle();
    expect(find.textContaining('Une réservation est en cours.'), findsOneWidget);
    expect(find.textContaining('Un solde est à retirer.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(_delete, findsNothing);
  });

  testWidgets('le bouton reste désactivé sans mot de passe ET sans le mot de confirmation exact', (t) async {
    final api = _FakeApi({'allowed': true, 'confirm_word': 'SUPPRIMER', 'blockers': []});
    await t.pumpWidget(_host(api, _FakeSession()));
    await t.pumpAndSettle();
    expect(t.widget<TratraButton>(_delete).onPressed, isNull);
    await _fill(t, confirm: 'supprim');
    expect(t.widget<TratraButton>(_delete).onPressed, isNull);
    await _fill(t, password: '');
    expect(t.widget<TratraButton>(_delete).onPressed, isNull);
    await _fill(t);
    expect(t.widget<TratraButton>(_delete).onPressed, isNotNull);
  });

  testWidgets('mauvais mot de passe : message précis, session conservée', (t) async {
    final api = _FakeApi(
      {'allowed': true, 'confirm_word': 'SUPPRIMER', 'blockers': []},
      postError: ApiException(403, 'Accès refusé', body: '{"detail":"Mot de passe incorrect.","code":"wrong_password"}'),
    );
    final session = _FakeSession();
    await t.pumpWidget(_host(api, session));
    await t.pumpAndSettle();
    await _fill(t);
    await t.tap(_delete);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TratraButton, 'Supprimer mon compte').last); // confirmation de la boîte de dialogue
    await t.pumpAndSettle();
    expect(find.text('Mot de passe incorrect.'), findsOneWidget);
    expect(session.loggedOut, isFalse);
    expect(find.text('ÉCRAN CONNEXION'), findsNothing);
  });

  testWidgets('succès : mot de passe et confirmation envoyés, session purgée, retour à la connexion', (t) async {
    final api = _FakeApi({'allowed': true, 'confirm_word': 'SUPPRIMER', 'blockers': []});
    final session = _FakeSession();
    await t.pumpWidget(_host(api, session));
    await t.pumpAndSettle();
    await _fill(t);
    await t.tap(_delete);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TratraButton, 'Supprimer mon compte').last);
    await t.pumpAndSettle();
    expect(api.posts, [
      {'password': 'secret123', 'confirm': 'SUPPRIMER'},
    ]);
    expect(session.loggedOut, isTrue);
    expect(find.text('ÉCRAN CONNEXION'), findsOneWidget);
  });

  testWidgets('annuler la confirmation n’envoie rien', (t) async {
    final api = _FakeApi({'allowed': true, 'confirm_word': 'SUPPRIMER', 'blockers': []});
    await t.pumpWidget(_host(api, _FakeSession()));
    await t.pumpAndSettle();
    await _fill(t);
    await t.tap(_delete);
    await t.pumpAndSettle();
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(api.posts, isEmpty);
  });
}
