import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/screens/auth/otp_screen.dart';

void main() {
  test('maskPhone ne montre jamais le numéro complet', () {
    expect(maskPhone('+2250700000002'), '+225 •• •• •• 02');
    expect(maskPhone('+225 07 00 00 00 02'), '+225 •• •• •• 02');
    expect(maskPhone('123'), '123');
  });

  test('User lit is_verified (faux par défaut)', () {
    final base = {'id': 1, 'email': 'a@b.c', 'user_type': 'client'};
    expect(User.fromJson(base).isVerified, isFalse);
    expect(User.fromJson({...base, 'is_verified': true}).isVerified, isTrue);
  });

  group('ApiException : jamais de JSON brut', () {
    ApiException of(int status, Object body) =>
        ApiException.fromResponse(http.Response.bytes(utf8.encode(jsonEncode(body)), status));

    test('detail DRF', () => expect(of(400, {'detail': 'Code invalide ou expiré.'}).toString(), 'Code invalide ou expiré.'));
    test('non_field_errors', () {
      expect(of(400, {'non_field_errors': ['Aucun compte actif']}).toString(), 'Aucun compte actif');
    });
    test('erreur de champ', () {
      expect(of(400, {'email': ['Adresse invalide.']}).toString(), 'email : Adresse invalide.');
    });
    test('statuts spéciaux', () {
      expect(of(429, {}).toString(), contains('Patientez'));
      expect(of(500, {}).toString(), 'Erreur serveur 500');
      expect(of(404, {}).toString(), 'Ressource non trouvée');
    });
    test('corps illisible : message générique', () {
      final e = ApiException.fromResponse(http.Response('<html>', 400));
      expect(e.toString(), isNot(contains('<html>')));
    });
  });

  testWidgets('TratraOtpInput remonte les chiffres et le code complet', (tester) async {
    String latest = '';
    String? completed;
    await tester.pumpWidget(MaterialApp(
      theme: TratraTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TratraOtpInput(onChanged: (v) => latest = v, onCompleted: (v) => completed = v),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), '12a345');
    await tester.pump();
    expect(latest, '12345'); // les non-chiffres sont filtrés
    expect(completed, isNull);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(completed, '123456');
  });
}
