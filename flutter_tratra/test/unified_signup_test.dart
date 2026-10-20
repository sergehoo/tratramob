// Compte unique : inscription par téléphone (sans identifiant ni e-mail obligatoire) et connexion par téléphone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/auth/forgot_password_screen.dart';
import 'package:flutter_tratra/screens/auth/login_screen.dart';
import 'package:flutter_tratra/screens/auth/register_screen.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';

Widget _host(Widget child) => MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<AuthService>(create: (_) => AuthService(BaseApi())),
      ],
      child: MaterialApp(theme: TratraTheme.light(), home: child),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('l’inscription demande prénom, nom, téléphone (pays + numéro national, Côte d’Ivoire par défaut), mot de passe et conditions', (t) async {
    _tall(t);
    await t.pumpWidget(_host(const RegisterScreen()));
    for (final label in ['Prénom', 'Nom', 'Téléphone', 'Mot de passe', 'Confirmer le mot de passe']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('conditions d’utilisation'), findsOneWidget);
    // plus de nom d'utilisateur, d'e-mail obligatoire, ni de choix de profil
    for (final gone in ['Adresse email', "Nom d'utilisateur", 'Artisan', 'Entreprise', 'Client']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('+225'), findsOneWidget);                                          // indicatif affiché, jamais à taper
    expect(find.byKey(const ValueKey('phone-country')), findsOneWidget);
  });

  testWidgets('la connexion se fait par téléphone et propose la récupération du compte', (t) async {
    _tall(t);
    await t.pumpWidget(_host(const LoginScreen()));
    expect(find.text('Téléphone'), findsOneWidget);
    expect(find.text('Mot de passe oublié ?'), findsOneWidget);
    expect(find.text('Email ou nom d’utilisateur'), findsNothing);
  });

  testWidgets('la récupération commence par le numéro, sans révéler si le compte existe', (t) async {
    _tall(t);
    await t.pumpWidget(_host(const ForgotPasswordScreen()));
    expect(find.text('Recevoir le code'), findsOneWidget);
    expect(find.text('+225'), findsOneWidget);                                          // indicatif affiché, jamais à taper
    expect(find.byKey(const ValueKey('phone-country')), findsOneWidget);
    expect(find.text('Nouveau mot de passe'), findsNothing); // seulement après l'envoi du code
  });
}
