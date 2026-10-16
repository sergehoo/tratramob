// Serveur muet : l'inscription et la connexion (ApiService) échouent au bout du délai au lieu de figer l'écran.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_tratra/core/timeout_http_client.dart';
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart';

void main() {
  test('une requête sans réponse expire au lieu de bloquer indéfiniment', () async {
    final client = TimeoutHttpClient(MockClient((_) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 80));
    await expectLater(client.post(Uri.parse('https://exemple.test/handy/users/'), body: '{}'), throwsA(isA<TimeoutException>()));
  });

  test('l’expiration est présentée comme « impossible de joindre le service »', () async {
    final client = TimeoutHttpClient(MockClient((_) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 50));
    Object? error;
    try {
      await client.post(Uri.parse('https://exemple.test/handy/auth/login/'));
    } catch (e) {
      error = e;
    }
    expect(error, isA<TimeoutException>());
    expect(authErrorMessage(error!), startsWith('Impossible de joindre le service'));
  });

  test('une réponse normale n’est pas affectée', () async {
    final client = TimeoutHttpClient(MockClient((_) async => http.Response('{"ok":true}', 201)), timeout: const Duration(milliseconds: 80));
    final r = await client.post(Uri.parse('https://exemple.test/x'));
    expect(r.statusCode, 201);
  });

  test('envoi de fichier : délai plus long que les requêtes ordinaires', () async {
    final client = TimeoutHttpClient(
      MockClient.streaming((req, body) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.StreamedResponse(Stream.value([]), 201);
      }),
      timeout: const Duration(milliseconds: 80),
      uploadTimeout: const Duration(seconds: 2),
    );
    final req = http.MultipartRequest('POST', Uri.parse('https://exemple.test/upload'))..fields['a'] = 'b';
    expect((await client.send(req)).statusCode, 201);
  });
}
