// Tratra ID : analyse des QR scannés, présentation des résultats et refus — rien n'est inventé côté mobile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/trust/identity_api.dart';
import 'package:flutter_tratra/screens/trust/verify_result.dart';

void main() {
  group('parseQr', () {
    test('badge permanent : URL de vérification ou code nu', () {
      for (final raw in ['https://tratra.ci/verify/TR-ABCD-EFGH', 'http://localhost:3000/verify/tr-abcd-efgh/', 'TR-ABCD-EFGH', ' tr-abcd-efgh ']) {
        final t = parseQr(raw);
        expect(t, isA<IdTarget>(), reason: raw);
        expect((t as IdTarget).code, 'TR-ABCD-EFGH');
      }
    });

    test('QR de mission : seul le jeton est extrait', () {
      final t = parseQr('https://tratra.ci/verify/pass/AbC-123_xyz');
      expect(t, isA<PassTarget>());
      expect((t as PassTarget).token, 'AbC-123_xyz');
    });

    test('QR étranger ou invalide : refusé, jamais interprété', () {
      for (final raw in ['', 'https://evil.example/pay?to=me', 'TR-ABCD-EFG0', 'TR-ABCD', 'javascript:alert(1)', 'https://tratra.ci/verify/', 'https://tratra.ci/verify/pass/', 'x' * 500]) {
        expect(parseQr(raw), isNull, reason: raw);
      }
    });
  });

  group('résultat', () {
    Widget host(IdentityOutcome o) => MaterialApp(theme: TratraTheme.light(), home: Scaffold(body: SingleChildScrollView(child: VerifyResultView(outcome: o))));

    testWidgets('badge actif : identité, métiers et badges réels', (t) async {
      await t.pumpWidget(host(const IdentityOutcome(
        ok: true,
        tone: 'ok',
        title: 'Professionnel vérifié par Tratra',
        message: 'Identité contrôlée par l’équipe Tratra.',
        tratraId: 'TR-ABCD-EFGH',
        holder: {
          'display_name': 'Awa K.',
          'photo': null,
          'trades': ['Plomberie', 'Électricité'],
          'commune': 'Cocody',
          'badges': [
            {'code': 'VERIFIE', 'label': 'Vérifié'}
          ],
          'kyc_verified_on': '2026-10-08T10:00:00Z',
        },
      )));
      expect(find.text('Professionnel vérifié par Tratra'), findsOneWidget);
      expect(find.text('Awa K.'), findsOneWidget);
      expect(find.text('Plomberie, Électricité'), findsOneWidget);
      expect(find.text('Vérifié'), findsOneWidget);
      expect(find.textContaining('TR-ABCD-EFGH'), findsOneWidget);
    });

    testWidgets('badge révoqué : aucune donnée personnelle affichée', (t) async {
      await t.pumpWidget(host(const IdentityOutcome(
        ok: false,
        tone: 'danger',
        title: 'Badge révoqué',
        message: 'Ce professionnel n’est plus vérifié par Tratra.',
        tratraId: 'TR-ABCD-EFGH',
      )));
      expect(find.text('Badge révoqué'), findsOneWidget);
      expect(find.byType(TratraAvatar), findsNothing);
      expect(find.byIcon(Icons.gpp_bad_rounded), findsOneWidget);
    });
  });
}
