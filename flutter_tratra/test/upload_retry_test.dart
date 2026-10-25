// Envois de fichiers (statuts, pièces jointes) : une coupure du transport est rejouée automatiquement quand l'envoi est idempotent
// (`client_id`), jamais une réponse illisible ni un envoi non idempotent ; le message d'échec porte une référence technique courte.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/network_errors.dart';

Future<http.Response> _upload(BaseApi api, {int retries = 2}) => api.uploadMultipart(
      '/statuses/',
      fields: {'text': 'bonsoir à tous, privilégiés d’un nouveau service', 'client_id': 'cid-1'},
      files: [() async => http.MultipartFile.fromBytes('file', List<int>.filled(50000, 7), filename: 'photo.jpg')],
      networkRetries: retries,
      retryDelay: Duration.zero,
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'tok', AppConstants.refreshTokenKey: 'refresh'}));

  test('coupure du transport : nouvel essai automatique avec le même client_id, puis publication', () async {
    final ids = <String>[];
    final client = MockClient((r) async {
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      ids.add(RegExp(r'name="client_id"\r\n\r\n([^\r]+)').firstMatch(body)!.group(1)!);
      if (ids.length == 1) throw const SocketException('Connection reset by peer', osError: OSError('Connection reset by peer', 104));
      if (ids.length == 2) throw http.ClientException('Connection closed before full header was received');
      return http.Response(jsonEncode({'status': {'id': 5}}), 201);
    });
    final r = await _upload(BaseApi(client: client));
    expect(r.statusCode, 201);
    expect(ids, ['cid-1', 'cid-1', 'cid-1']);            // jamais un autre identifiant : le serveur ne publie qu'une fois
  });

  test('au-delà des essais prévus, la coupure remonte (message avec référence)', () async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      throw const SocketException('Connection reset by peer', osError: OSError('Connection reset by peer', 104));
    });
    Object? error;
    try {
      await _upload(BaseApi(client: client));
    } catch (e) {
      error = e;
    }
    expect(calls, 3);
    expect(error, isA<SocketException>());
    expect(transferErrorRef(error!), 'NET-104');
    expect(transferFailureMessage(error, retryHint: 'Touchez « Réessayer ».'), contains('(réf. NET-104)'));
  });

  test('envoi non idempotent : aucun nouvel essai automatique', () async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      throw http.ClientException('Connection closed');
    });
    await expectLater(_upload(BaseApi(client: client), retries: 0), throwsA(isA<http.ClientException>()));
    expect(calls, 1);
  });

  test('une réponse du serveur n’est jamais rejouée, même une erreur', () async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      return http.Response('<html>Bad Gateway</html>', 502);
    });
    final r = await _upload(BaseApi(client: client));
    expect(r.statusCode, 502);
    expect(calls, 1);
  });

  test('références et messages : délai, réponse illisible, connexion fermée, TLS', () {
    expect(transferErrorRef(TimeoutException('x')), 'DELAI');
    expect(transferFailureMessage(TimeoutException('x'), retryHint: 'R.'), startsWith('L’envoi prend trop de temps'));
    expect(transferErrorRef(const FormatException('x')), 'REPONSE');
    expect(transferFailureMessage(const FormatException('x'), retryHint: 'R.'), contains('l’envoi a peut-être abouti'));
    expect(transferErrorRef(http.ClientException('closed')), 'CONN');
    expect(transferErrorRef(const HandshakeException('x')), 'TLS');
    expect(transferErrorRef(const SocketException('x')), 'NET');
    expect(isTransientNetworkError(TimeoutException('x')), isFalse);    // 5 minutes déjà écoulées : pas de nouvel essai automatique
    expect(isTransientNetworkError(const FormatException('x')), isFalse);
  });
}
