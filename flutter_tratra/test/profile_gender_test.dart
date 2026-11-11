// Profil : le genre est facultatif et déclaré par la personne (pictogramme travailleuse / travailleur sur la carte d'une recherche).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/screens/auth/profile_extras.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'auth_token': 'acc'}));

  Future<List<Map<String, dynamic>>> open(WidgetTester t, Map<String, dynamic> json) async {
    final sent = <Map<String, dynamic>>[];
    final api = DashboardApi(BaseApi(client: MockClient((r) async {
      sent.add((jsonDecode(r.body) as Map).cast<String, dynamic>());
      return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
    })));
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(Provider<DashboardApi>.value(
      value: api,
      child: MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: SingleChildScrollView(child: ProfileEditForm(user: User.fromJson(json))))),
    ));
    await t.pump();
    return sent;
  }

  TratraChip chip(WidgetTester t, String code) => t.widget<TratraChip>(find.byKey(ValueKey('profile-gender-$code')));

  testWidgets('genre non indiqué par défaut : rien de présélectionné ; le choix est envoyé tel quel', (t) async {
    final sent = await open(t, {'id': 9, 'email': '', 'first_name': 'Awa', 'last_name': 'Koné', 'user_type': 'handyman'});
    expect(chip(t, 'F').selected, isFalse);
    expect(chip(t, 'M').selected, isFalse);
    await t.tap(find.byKey(const ValueKey('profile-gender-F')));
    await t.pump();
    expect(chip(t, 'F').selected, isTrue);
    await t.tap(find.text('Enregistrer'));
    await t.pump(const Duration(milliseconds: 100));
    expect(sent.single['gender'], 'F');
  });

  testWidgets('genre déjà indiqué : affiché, et un second appui le retire', (t) async {
    final sent = await open(t, {'id': 9, 'email': '', 'first_name': 'Yao', 'last_name': 'Kouassi', 'user_type': 'handyman', 'gender': 'M'});
    expect(chip(t, 'M').selected, isTrue);
    await t.tap(find.byKey(const ValueKey('profile-gender-M')));
    await t.pump();
    expect(chip(t, 'M').selected, isFalse);
    await t.tap(find.text('Enregistrer'));
    await t.pump(const Duration(milliseconds: 100));
    expect(sent.single['gender'], '');
  });
}
