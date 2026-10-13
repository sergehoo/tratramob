import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/biometric/biometric_api.dart';
import 'package:flutter_tratra/biometric/biometric_flow_screen.dart';
import 'package:flutter_tratra/biometric/liveness_guidance.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';

FaceMetrics face({double yaw = 0, double pitch = 0, double? smile, double width = 0.5, double cx = 0.5, int faces = 1, double? eye}) =>
    FaceMetrics(faces: faces, yaw: yaw, pitch: pitch, smile: smile, widthRatio: width, centerX: cx, leftEyeOpen: eye, rightEyeOpen: eye);

http.Response json200(Object b, [int status = 200]) => http.Response(jsonEncode(b), status, headers: {'content-type': 'application/json; charset=utf-8'});

class Call {
  Call(this.method, this.path, this.headers, this.body);
  final String method, path, body;
  final Map<String, String> headers;
}

({BiometricApi api, BaseApi base, List<Call> calls}) fake(Future<http.Response> Function(http.Request r) h) {
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
  final calls = <Call>[];
  final base = BaseApi(client: MockClient((r) async {
    calls.add(Call(r.method, r.url.path, r.headers, utf8.decode(r.bodyBytes, allowMalformed: true)));
    return h(r);
  }));
  return (api: BiometricApi(base), base: base, calls: calls);
}

Map<String, dynamic> stateJson({bool enabled = true, bool consent = false, bool doc = true, String status = 'not_started', bool active = false}) => {
      'enabled': enabled, 'provider_configured': false, 'status': status, 'status_label': status, 'satisfied': false,
      'consent': {'version': '2026-10', 'text': 'Texte du consentement biométrique', 'granted': consent},
      'document': {'present': doc, 'status': 'pending'}, 'human_review_requested': false, 'active_session': active ? {} : null,
      'attempts': {'day': 1, 'max_day': 3, 'week': 1, 'max_week': 6}, 'decision_reason': '', 'alternative': {'available': true},
    };

void main() {
  group('guidage de la capture (cadrage, rotation, sourire)', () {
    test('cadrage : visage absent, multiple, trop loin, trop près, décentré', () {
      expect(evaluate('front', null).hint, contains('ovale'));
      expect(evaluate('front', face(faces: 0)).ok, isFalse);
      expect(evaluate('front', face(faces: 2)).hint, contains('Une seule personne'));
      expect(evaluate('front', face(width: 0.1)).hint, 'Rapprochez-vous');
      expect(evaluate('front', face(width: 0.95)).hint, contains('Éloignez'));
      expect(evaluate('front', face(cx: 0.9)).hint, 'Centrez votre visage');
    });

    test('chaque étape n\'est acceptée que dans la bonne pose', () {
      expect(evaluate('front', face()).ok, isTrue);
      expect(evaluate('front', face(yaw: 25)).ok, isFalse);
      expect(evaluate('front', face(eye: 0.1)).hint, contains('yeux ouverts'));
      expect(evaluate('left', face(yaw: 25 * kLeftYawSign)).ok, isTrue);
      expect(evaluate('left', face(yaw: 5)).ok, isFalse);
      expect(evaluate('left', face(yaw: -25 * kLeftYawSign)).ok, isFalse);        // l'autre côté ne compte pas
      expect(evaluate('right', face(yaw: -25 * kLeftYawSign)).ok, isTrue);
      expect(evaluate('right', face(yaw: 25 * kLeftYawSign)).ok, isFalse);
      expect(evaluate('up', face(pitch: 20)).ok, isTrue);
      expect(evaluate('up', face(pitch: -20)).ok, isFalse);
      expect(evaluate('down', face(pitch: -20)).ok, isTrue);
      expect(evaluate('down', face(pitch: 0)).ok, isFalse);
      expect(evaluate('smile', face(smile: 0.9)).ok, isTrue);
      expect(evaluate('smile', face(smile: 0.2)).hint, 'Souriez');
      expect(evaluate('inconnu', face()).ok, isFalse);                               // une étape inconnue n'est jamais « validée »
    });
  });

  group('API de vérification faciale', () {
    test('session : jeton, défis dans l\'ordre du serveur, reprise des étapes déjà envoyées', () {
      final s = BiometricSessionInfo.fromJson({
        'session_id': 7, 'token': 'tok', 'expires_at': '2026-10-13T10:00:00Z', 'captured': [0, 1],
        'challenges': [for (final (i, k) in ['front', 'up', 'left', 'down', 'right', 'smile'].indexed) {'index': i, 'kind': k, 'instruction': 'Étape $k'}],
      });
      expect(s.challenges.map((c) => c.kind), ['front', 'up', 'left', 'down', 'right', 'smile']);
      expect(s.nextIndex, 2);
      expect(BiometricSessionInfo.fromJson({'session_id': 1, 'token': 't', 'captured': [0, 1, 2], 'challenges': [for (var i = 0; i < 3; i++) {'index': i, 'kind': 'front', 'instruction': 'x'}]}).nextIndex, isNull);
    });

    test('envoi d\'une capture : jeton dans l\'en-tête (jamais l\'URL), multipart JPEG, étape et type', () async {
      final f = fake((r) async => json200({'index': 2}, 201));
      final s = BiometricSessionInfo(id: 9, token: 'jeton-secret', challenges: [BiometricChallenge(2, 'left', 'x')], captured: {}, expiresAt: null);
      await f.api.uploadCapture(s, index: 2, kind: 'left', bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]));
      final c = f.calls.single;
      expect(c.path, endsWith('/kyc/biometric/sessions/9/captures/'));
      expect(c.headers['X-Biometric-Token'], 'jeton-secret');
      expect(c.path, isNot(contains('jeton')));
      expect(c.headers['content-type'], startsWith('multipart/form-data'));
      expect(c.body, allOf(contains('name="index"'), contains('left'), contains('image/jpeg')));
    });

    test('erreurs du serveur : code et message lisibles, session perdue reconnue', () async {
      final f = fake((r) async => r.url.path.endsWith('/captures/') ? json200({'code': 'poor_quality', 'detail': 'Éclairage insuffisant.', 'problems': ['too_dark']}, 422) : json200({'code': 'expired', 'detail': 'La session a expiré.'}, 410));
      final s = BiometricSessionInfo(id: 1, token: 't', challenges: [], captured: {}, expiresAt: null);
      try {
        await f.api.uploadCapture(s, index: 0, kind: 'front', bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]));
        fail('attendu');
      } on BiometricApiException catch (e) {
        expect(e.code, 'poor_quality');
        expect(e.detail, 'Éclairage insuffisant.');
        expect(e.extra['problems'], ['too_dark']);
        expect(e.sessionLost, isFalse);
      }
      try {
        await f.api.submit(s);
        fail('attendu');
      } on BiometricApiException catch (e) {
        expect(e.sessionLost, isTrue);
        expect(e.status, 410);
      }
    });

    test('retrait du consentement : renvoie le nombre de captures supprimées', () async {
      final f = fake((r) async => json200({'captures_deleted': 6}));
      expect(await f.api.withdrawConsent(), 6);
      expect(f.calls.single.method, 'DELETE');
    });
  });

  group('écran de vérification faciale', () {
    Future<List<Call>> pump(WidgetTester t, Map<String, dynamic> state, {Future<http.Response> Function(http.Request r)? extra}) async {
      final f = fake((r) async {
        if (extra != null) {
          final x = await extra(r);
          return x;
        }
        return json200(state);
      });
      await t.pumpWidget(Provider<BaseApi>.value(value: f.base, child: MaterialApp(theme: TratraTheme.light(), home: const BiometricFlowScreen())));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 80));
      }
      return f.calls;
    }

    testWidgets('consentement explicite requis : le bouton reste inactif tant que la case n\'est pas cochée, l\'alternative est proposée', (t) async {
      final calls = await pump(t, stateJson(consent: false));
      expect(find.text('Texte du consentement biométrique'), findsOneWidget);
      expect(find.text('Demander une vérification par l’équipe'), findsOneWidget);
      final accept = find.widgetWithText(TratraButton, 'J’accepte et je continue');
      expect(t.widget<TratraButton>(accept).onPressed, isNull);
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      expect(t.widget<TratraButton>(accept).onPressed, isNotNull);
      expect(calls.where((c) => c.method == 'POST'), isEmpty);                        // rien n'est envoyé avant le consentement
    });

    testWidgets('sans pièce d\'identité : la capture n\'est pas proposée', (t) async {
      await pump(t, stateJson(doc: false));
      expect(find.text('Une pièce d’identité est nécessaire'), findsOneWidget);
      expect(find.text('Commencer la vérification'), findsNothing);
    });

    testWidgets('fonction désactivée : message clair et vérification humaine uniquement', (t) async {
      await pump(t, stateJson(enabled: false, consent: true));
      expect(find.text('Vérification automatique indisponible'), findsOneWidget);
      expect(find.text('Commencer la vérification'), findsNothing);
      expect(find.text('Demander une vérification par l’équipe'), findsOneWidget);
    });

    testWidgets('consentement donné : la capture peut commencer, et un dossier en attente est expliqué sans jamais être présenté comme validé', (t) async {
      await pump(t, stateJson(consent: true));
      expect(find.text('Commencer la vérification'), findsOneWidget);
      expect(find.textContaining('Retirer mon consentement'), findsOneWidget);
      await t.pumpWidget(const SizedBox());                                              // démonte l'écran : le suivant recharge son état
      await pump(t, stateJson(consent: true, status: 'pending_review'));
      expect(find.text('En attente de vérification par l’équipe'), findsOneWidget);
      expect(find.textContaining('satisfaisante'), findsNothing);
    });

    testWidgets('erreur réseau : message et bouton Réessayer', (t) async {
      await pump(t, {}, extra: (r) async => throw http.ClientException('hors ligne'));
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('demande de vérification humaine : appel serveur puis confirmation', (t) async {
      final calls = await pump(t, stateJson(consent: false), extra: (r) async => r.method == 'POST' ? json200({'status': 'pending_review'}) : json200(stateJson(consent: false)));
      await t.tap(find.text('Demander une vérification par l’équipe'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 80));
      }
      expect(calls.any((c) => c.method == 'POST' && c.path.endsWith('/kyc/biometric/human-review/') && c.body.contains('other')), isTrue);
      expect(find.text('Demande envoyée : l’équipe Tratra examinera votre dossier.'), findsOneWidget);
    });
  });
}
