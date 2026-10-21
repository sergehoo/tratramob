// Connexion bloquée après trop de tentatives : message clair avec compte à rebours (donné par le serveur) et accès au support,
// au lieu du « mot de passe incorrect » trompeur ; le serveur reste l'autorité à la fin du décompte.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/screens/auth/login_screen.dart';
import 'package:flutter_tratra/screens/auth/widgets/login_lock_notice.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

http.Response lockedResponse(int seconds) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'code': 'login_locked',
        'detail': 'Connexion temporairement bloquée après trop de tentatives. Patientez 55:30 ou contactez le support (support@tratra.net).',
        'retry_after': seconds,
        'support_email': 'aide@exemple.test',
      })),
      429,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _FakeApi extends ApiService {
  _FakeApi(this.next);
  Object Function() next;
  int calls = 0;

  @override
  Future<User> loginWithUsername(String username, String password, {bool remember = true}) async {
    calls++;
    throw next();
  }
}

var clock = DateTime(2026, 10, 20, 12);

/// Fait avancer l'horloge injectée ET le minuteur de l'écran du même temps.
Future<void> advance(WidgetTester t, int seconds) async {
  clock = clock.add(Duration(seconds: seconds));
  await t.pump(Duration(seconds: seconds));
}

Widget host(ApiService api) => MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<AuthService>(create: (_) => AuthService(BaseApi())),
      ],
      child: MaterialApp(theme: TratraTheme.light(), home: LoginScreen(now: () => clock)),
    );

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Future<void> submit(WidgetTester t) async {
  await t.enterText(find.byType(TextField).at(0), '+2250594977511');
  await t.enterText(find.byType(TextField).at(1), 'mot-de-passe');
  await t.tap(find.text('Se connecter'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  group('lecture de la réponse du serveur', () {
    test('429 login_locked : code, temps restant et support', () {
      final e = ApiException.fromResponse(lockedResponse(3330));
      expect(e.isLoginLocked, isTrue);
      expect((e.retryAfterSeconds, e.supportEmail), (3330, 'aide@exemple.test'));
    });

    test('un refus ordinaire ou un 429 de débit n’est jamais pris pour un blocage', () {
      final wrong = ApiException.fromResponse(http.Response.bytes(utf8.encode('{"non_field_errors":["Aucun compte actif"]}'), 400));
      expect(wrong.isLoginLocked, isFalse);
      final throttled = ApiException.fromResponse(http.Response.bytes(utf8.encode('{"detail":"Requête ralentie. Expected available in 60 seconds."}'), 429));
      expect(throttled.isLoginLocked, isFalse);
      expect(ApiException.fromResponse(http.Response('pas du json', 429)).isLoginLocked, isFalse);
      expect(ApiException(429, 'x', body: '{"code":"login_locked"}').isLoginLocked, isFalse); // sans délai : pas de décompte inventé
    });

    test('mise en forme mm:ss', () {
      expect(formatCountdown(3330), '55:30');
      expect(formatCountdown(3600), '60:00');
      expect(formatCountdown(7), '00:07');
      expect(formatCountdown(0), '00:00');
      expect(formatCountdown(-4), '00:00');
    });
  });

  group('écran de connexion', () {
    setUp(() {
      clock = DateTime(2026, 10, 20, 12);
      resetRememberedLoginLock();
    });

    testWidgets('bloqué : message, compte à rebours qui descend, bouton désactivé — jamais « mot de passe incorrect »', (t) async {
      tall(t);
      final api = _FakeApi(() => ApiException.fromResponse(lockedResponse(3330)));
      await t.pumpWidget(host(api));
      await submit(t);
      expect(find.text('Connexion bloquée'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-lock-countdown')), findsOneWidget);
      expect(find.text('55:30'), findsOneWidget);
      expect(find.textContaining('incorrect'), findsNothing);
      expect(find.text('Contacter le support'), findsOneWidget);
      expect(find.text('Réessayer dans 55:30'), findsOneWidget);
      expect(t.widget<TratraButton>(find.widgetWithText(TratraButton, 'Réessayer dans 55:30')).onPressed, isNull);
      await advance(t, 1);
      expect(find.text('55:29'), findsOneWidget);
      await advance(t, 29);
      expect(find.text('55:00'), findsOneWidget);
      expect(api.calls, 1); // aucun nouvel essai pendant le blocage
      await t.pumpWidget(const SizedBox()); // le minuteur s'arrête avec l'écran
    });

    testWidgets('à la fin du décompte, le formulaire redevient utilisable', (t) async {
      tall(t);
      var attempts = 0;
      final api = _FakeApi(() => ++attempts == 1 ? ApiException.fromResponse(lockedResponse(3)) : ApiException(400, 'refus'));
      await t.pumpWidget(host(api));
      await submit(t);
      expect(find.text('00:03'), findsOneWidget);
      await advance(t, 4);
      expect(find.text('Connexion bloquée'), findsNothing);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(t.widget<TratraButton>(find.widgetWithText(TratraButton, 'Se connecter')).onPressed, isNotNull);
      await t.tap(find.text('Se connecter'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('Téléphone ou mot de passe incorrect.'), findsOneWidget); // un vrai refus ordinaire garde son message
      expect(api.calls, 2);
    });

    testWidgets('le décompte survit à un retour sur l’écran (le serveur reste l’autorité)', (t) async {
      tall(t);
      final api = _FakeApi(() => ApiException.fromResponse(lockedResponse(600)));
      await t.pumpWidget(host(api));
      await submit(t);
      await t.pumpWidget(const SizedBox()); // l'utilisateur quitte l'écran
      await t.pumpWidget(host(api));
      await t.pump();
      expect(find.text('Connexion bloquée'), findsOneWidget);
      expect(find.byKey(const ValueKey('login-lock-countdown')), findsOneWidget);
      expect(api.calls, 1);
      await advance(t, 601); // fin du blocage mémorisé
      expect(find.text('Connexion bloquée'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
