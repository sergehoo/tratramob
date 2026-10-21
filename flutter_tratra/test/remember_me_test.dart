// « Se souvenir de moi » (application) : case cochée par défaut ; décochée, la session s'arrête à la fermeture RÉELLE de l'application
// (démarrage à froid suivant), jamais en simple arrière-plan ; révocation, changement de compte, aucun mot de passe conservé.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/auth/login_screen.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: const {'content-type': 'application/json; charset=utf-8'});

/// Serveur simulé : connexion (corps enregistré), profil, déconnexion (jeton révoqué enregistré).
class _Server {
  final logins = <Map<String, dynamic>>[];
  final revoked = <String>[];
  late final client = MockClient((r) async {
    if (r.url.path.endsWith('/auth/login/')) {
      logins.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
      return _json({'access': 'acc-${logins.length}', 'refresh': 'ref-${logins.length}'});
    }
    if (r.url.path.endsWith('/users/me/')) {
      return _json({'id': 9, 'email': '', 'first_name': 'Awa', 'user_type': 'client', 'is_active': true, 'is_verified': true});
    }
    if (r.url.path.endsWith('/auth/logout/')) {
      revoked.add('${(jsonDecode(r.body) as Map)['refresh']}');
      return _json({});
    }
    return _json({});
  });
}

Future<Map<String, String>> _stored() => const FlutterSecureStorage().readAll();

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('cochée (défaut) : session gardée, aucun indicateur de fin à la fermeture ; décochée : indicateur posé', () async {
    final server = _Server();
    final api = ApiService(client: server.client);
    await api.loginWithUsername('+2250700000888', 'secret-de-test');
    expect(server.logins.last['remember_me'], isTrue);
    var stored = await _stored();
    expect(stored[AppConstants.refreshTokenKey], 'ref-1');
    expect(stored.containsKey(AppConstants.sessionOnlyKey), isFalse);
    expect(stored.values.join(), isNot(contains('secret-de-test')), reason: 'aucun mot de passe conservé');

    await api.loginWithUsername('+2250700000888', 'secret-de-test', remember: false);
    expect(server.logins.last['remember_me'], isFalse);
    stored = await _stored();
    expect(stored[AppConstants.sessionOnlyKey], '1');

    await api.loginWithUsername('+2250700000999', 'autre', remember: true);   // changement de compte : choix du NOUVEAU compte
    expect((await _stored()).containsKey(AppConstants.sessionOnlyKey), isFalse);
  });

  test('décochée : au démarrage à froid suivant, session révoquée et effacée (push retiré, données locales purgées)', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppConstants.authTokenKey: 'acc-1',
      AppConstants.refreshTokenKey: 'ref-1',
      AppConstants.userDataKey: jsonEncode({'id': 9, 'email': '', 'user_type': 'client', 'is_active': true}),
      AppConstants.sessionOnlyKey: '1',
    });
    final server = _Server();
    final session = Session(AuthService(BaseApi(client: server.client)), StorageService());
    var unregistered = false, wiped = false;
    session.onBeforeLogout = () async => unregistered = true;
    session.addLogoutWipe(() async => wiped = true);

    expect(await session.endSessionOnlyAtColdStart(), isTrue);
    await session.loadFromStorage();
    expect(session.isAuthenticated, isFalse);
    expect(server.revoked, ['ref-1'], reason: 'jeton révoqué côté serveur');
    expect(unregistered && wiped, isTrue);
    final stored = await _stored();
    for (final key in [AppConstants.authTokenKey, AppConstants.refreshTokenKey, AppConstants.userDataKey, AppConstants.sessionOnlyKey]) {
      expect(stored.containsKey(key), isFalse, reason: key);
    }
  });

  test('cochée : la session survit au redémarrage ; rien n’est révoqué', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppConstants.authTokenKey: 'acc-1',
      AppConstants.refreshTokenKey: 'ref-1',
      AppConstants.userDataKey: jsonEncode({'id': 9, 'email': '', 'user_type': 'client', 'is_active': true}),
    });
    final server = _Server();
    final session = Session(AuthService(BaseApi(client: server.client)), StorageService());
    expect(await session.endSessionOnlyAtColdStart(), isFalse);
    await session.loadFromStorage();
    expect(session.isAuthenticated, isTrue);
    expect(server.revoked, isEmpty);
  });

  test('décochée sans réseau au démarrage : purge locale quand même (rien ne reste sur le téléphone)', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppConstants.authTokenKey: 'acc-1',
      AppConstants.refreshTokenKey: 'ref-1',
      AppConstants.sessionOnlyKey: '1',
    });
    final offline = MockClient((_) async => throw http.ClientException('hors ligne'));
    final session = Session(AuthService(BaseApi(client: offline)), StorageService());
    expect(await session.endSessionOnlyAtColdStart(), isTrue);
    expect((await _stored()).isEmpty, isTrue);
  });

  testWidgets('écran de connexion : « Se souvenir de moi » coché par défaut et modifiable', (t) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<AuthService>(create: (_) => AuthService(BaseApi())),
      ],
      child: MaterialApp(theme: TratraTheme.light(), home: const LoginScreen()),
    ));
    expect(find.text('Se souvenir de moi'), findsOneWidget);
    expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await t.tap(find.byKey(const ValueKey('login-remember')));
    await t.pump();
    expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });
}
