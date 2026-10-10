// Réseau « fantôme » : une requête sans réponse expire au lieu de bloquer l'écran indéfiniment.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_tratra/core/auth_http_client.dart';

void main() {
  test('sans réponse du serveur, la requête expire (TimeoutException) au lieu d’attendre indéfiniment', () async {
    final client = AuthHttpClient(
      MockClient((_) => Completer<http.Response>().future),
      refresh: () async => null,
      timeout: const Duration(milliseconds: 80),
    );
    await expectLater(client.get(Uri.parse('https://exemple.test/handy/me/dashboard/')), throwsA(isA<TimeoutException>()));
  });

  test('une réponse normale n’est pas affectée', () async {
    final client = AuthHttpClient(MockClient((_) async => http.Response('{"ok":true}', 200)), refresh: () async => null, timeout: const Duration(milliseconds: 80));
    final r = await client.get(Uri.parse('https://exemple.test/x'));
    expect(r.statusCode, 200);
  });

  test('envoi de fichier : délai plus long que les requêtes ordinaires', () async {
    final client = AuthHttpClient(
      MockClient.streaming((req, body) async {
        await Future<void>.delayed(const Duration(milliseconds: 200)); // plus long que le délai ordinaire (80 ms)
        return http.StreamedResponse(Stream.value([]), 201);
      }),
      refresh: () async => null,
      timeout: const Duration(milliseconds: 80),
      uploadTimeout: const Duration(seconds: 2),
    );
    final req = http.MultipartRequest('POST', Uri.parse('https://exemple.test/upload'))..fields['a'] = 'b';
    final res = await client.send(req);
    expect(res.statusCode, 201);
  });

  test('401 puis jeton rafraîchi : la requête est rejouée une fois avec le nouveau jeton', () async {
    var calls = 0;
    final client = AuthHttpClient(
      MockClient((r) async {
        calls++;
        return r.headers['Authorization'] == 'Bearer neuf' ? http.Response('ok', 200) : http.Response('', 401);
      }),
      refresh: () async => 'neuf',
    );
    final r = await client.get(Uri.parse('https://exemple.test/x'), headers: {'Authorization': 'Bearer vieux'});
    expect(r.statusCode, 200);
    expect(calls, 2);
  });
}
