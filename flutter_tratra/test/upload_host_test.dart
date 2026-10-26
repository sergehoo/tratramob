// Hôte d'envoi direct des fichiers (upload.tratra.net, « DNS seulement », hors Cloudflare) : sur certains Wi-Fi, les envois vers Cloudflare
// sont coupés au bout de 15 s alors qu'ils passent en direct. Les fichiers partent par cet hôte ; s'il n'a pas pu recevoir l'envoi (adresse
// inconnue, connexion refusée, certificat, route absente du proxy, chemin refusé), le même envoi repart par l'API habituelle — jamais après
// une coupure EN COURS d'envoi (l'envoi a pu être traité).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/network_errors.dart';

const upload = 'upload.tratra.net';
const api = 'api.tratra.net';

Future<http.Response> _status(BaseApi base, {int retries = 2}) => base.uploadMultipart(
      '/statuses/',
      fields: {'text': 'bonsoir', 'client_id': 'cid-7'},
      files: [() async => http.MultipartFile.fromBytes('file', List<int>.filled(43000, 7), filename: 'photo.jpg')],
      networkRetries: retries,
      retryDelay: Duration.zero,
    );

Future<http.Response> _file(BaseApi base) async => http.Response.fromStream(await base.sendFile((root) async {
      final req = http.MultipartRequest('PATCH', Uri.parse('$root/users/9/'));
      req.files.add(http.MultipartFile.fromBytes('profile_picture', List<int>.filled(1000, 1), filename: 'moi.jpg'));
      return req;
    }));

http.Response _json(int code, Object body, {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json', ...headers});

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({AppConstants.authTokenKey: 'tok', AppConstants.refreshTokenKey: 'refresh'});
    BaseApi.resetUploadHost();
  });

  test('base des envois : hôte direct en production, même API en recette locale, surcharge au build prioritaire', () {
    expect(AppConstants.uploadBaseFor('https://api.tratra.net/handy', ''), 'https://upload.tratra.net/handy');
    expect(AppConstants.uploadBaseFor('http://127.0.0.1:8000/handy', ''), 'http://127.0.0.1:8000/handy');
    expect(AppConstants.uploadBaseFor('https://api.tratra.net/handy', 'https://up.exemple.ci/handy'), 'https://up.exemple.ci/handy');
    expect(BaseApi().uploadBaseUrl, 'https://upload.tratra.net/handy');
  });

  test('un statut photo part par l\'hôte direct, même chemin d\'API', () async {
    final seen = <Uri>[];
    final r = await _status(BaseApi(client: MockClient((req) async {
      seen.add(req.url);
      return _json(201, {'status': {'id': 1}});
    })));
    expect(r.statusCode, 201);
    expect(seen.map((u) => '${u.host}${u.path}'), ['$upload/handy/statuses/']);
  });

  test('hôte direct introuvable : le même envoi repart aussitôt par l\'API, puis les suivants directement par elle', () async {
    final seen = <String>[];
    final base = BaseApi(client: MockClient((req) async {
      seen.add('${req.url.host} ${RegExp(r'name="client_id"\r\n\r\n([^\r]+)').firstMatch(utf8.decode(req.bodyBytes, allowMalformed: true))?.group(1)}');
      if (req.url.host == upload) {
        throw const SocketException("Failed host lookup: 'upload.tratra.net'", osError: OSError('No address associated with hostname', 7));
      }
      return _json(201, {'status': {'id': 2}});
    }));
    expect((await _status(base)).statusCode, 201);
    expect(seen, ['$upload cid-7', '$api cid-7']);                 // un seul essai sur l'hôte injoignable, même identifiant d'envoi
    expect(base.uploadBaseUrl, 'https://api.tratra.net/handy');
    seen.clear();
    expect((await _status(base)).statusCode, 201);
    expect(seen, ['$api cid-7']);                                   // plus de détour pendant uploadHostRetryAfter
  });

  test('coupure EN COURS d\'envoi sur l\'hôte direct : nouveaux essais sur lui seulement (l\'envoi a pu être traité)', () async {
    final hosts = <String>[];
    final base = BaseApi(client: MockClient((req) async {
      hosts.add(req.url.host);
      if (hosts.length < 3) throw http.ClientException('Connection closed before full header was received');
      return _json(201, {'status': {'id': 3}});
    }));
    expect((await _status(base)).statusCode, 201);
    expect(hosts, [upload, upload, upload]);
    expect(base.uploadBaseUrl, 'https://upload.tratra.net/handy');
  });

  test('certificat refusé, route absente du proxy, chemin refusé par l\'hôte : repli sur l\'API', () async {
    for (final failure in <Object>[
      const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      http.Response('404 page not found', 404, headers: {'content-type': 'text/plain'}),
      _json(404, {'code': 'upload_host_only'}, headers: {'x-upload-host': 'refused'}),
    ]) {
      BaseApi.resetUploadHost();
      final hosts = <String>[];
      final base = BaseApi(client: MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == upload) {
          if (failure is http.Response) return failure;
          throw failure;
        }
        return _json(200, {'id': 9});
      }));
      final r = await _file(base);
      expect(r.statusCode, 200, reason: '$failure');
      expect(hosts, [upload, api], reason: '$failure');
      // Chemin refusé : propre à CET envoi, l'hôte reste utilisé pour les autres.
      expect(base.uploadBaseUrl, failure is http.Response && failure.headers['x-upload-host'] == 'refused'
          ? 'https://upload.tratra.net/handy' : 'https://api.tratra.net/handy');
    }
  });

  test('une vraie réponse de l\'API par l\'hôte direct n\'est jamais rejouée (erreur comprise)', () async {
    var calls = 0;
    final r = await _file(BaseApi(client: MockClient((req) async {
      calls++;
      return _json(404, {'detail': 'Introuvable.'});
    })));
    expect((r.statusCode, calls), (404, 1));
  });

  test('« jamais atteint le serveur » : adresse, refus, réseau, certificat — pas une coupure ni un délai', () {
    expect(neverReachedServer(const SocketException("Failed host lookup: 'upload.tratra.net'")), isTrue);
    expect(neverReachedServer(const SocketException('x', osError: OSError('Connection refused', 111))), isTrue);
    expect(neverReachedServer(const SocketException('x', osError: OSError('Network is unreachable', 101))), isTrue);
    expect(neverReachedServer(const HandshakeException('CERTIFICATE_VERIFY_FAILED')), isTrue);
    expect(neverReachedServer(const SocketException('x', osError: OSError('Connection reset by peer', 104))), isFalse);
    expect(neverReachedServer(http.ClientException('Connection closed before full header was received')), isFalse);
  });
}
