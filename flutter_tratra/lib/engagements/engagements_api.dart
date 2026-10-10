// lib/engagements/engagements_api.dart
//
// Client de l'API des engagements (`/handy/engagements/…`), commune au web et à Flutter. Les règles (qui peut quoi, quand)
// restent côté serveur : `actions` et `can_*` renvoyés par l'API pilotent l'interface. Les écritures sensibles envoient
// `Idempotency-Key` : un renvoi après coupure rejoue la même action sans doublon.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart' show PrivateDownloader;

/// Page de résultats `{count, next_offset, results}`.
class EngPage {
  const EngPage({required this.count, required this.results, this.nextOffset});
  final int count;
  final int? nextOffset;
  final List<Map<String, dynamic>> results;
}

class EngagementsApi implements PrivateDownloader {
  EngagementsApi(this._base);
  final BaseApi _base;

  static const _root = '/engagements';

  Uri _uri(String path) => Uri.parse('${_base.baseUrl}$_root$path');

  Future<dynamic> _send(String method, String path, {Object? body, String? idempotencyKey}) async {
    final headers = {...await _base.headers, if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey};
    final encoded = body == null ? null : json.encode(body);
    final uri = _uri(path);
    final http.Response r = switch (method) {
      'POST' => await _base.client.post(uri, headers: headers, body: encoded ?? '{}'),
      'PATCH' => await _base.client.patch(uri, headers: headers, body: encoded ?? '{}'),
      _ => await _base.client.get(uri, headers: headers),
    };
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    if (r.bodyBytes.isEmpty) return null;
    return _base.decodeBody(r);
  }

  static Map<String, dynamic> _map(dynamic d) => d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};

  Future<Map<String, dynamic>> getMap(String path) async => _map(await _send('GET', path));

  Future<EngPage> getPage(String path) async {
    final d = _map(await _send('GET', path));
    final rows = (d['results'] is List ? d['results'] as List : const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return EngPage(count: d['count'] is num ? (d['count'] as num).toInt() : rows.length, nextOffset: d['next_offset'] is num ? (d['next_offset'] as num).toInt() : null, results: rows);
  }

  /// Liste simple `{results: [...]}` (avenants, évaluations, litiges…).
  Future<List<Map<String, dynamic>>> getList(String path) async => (await getPage(path)).results;

  Future<Map<String, dynamic>> post(String path, [Object? body, String? idempotencyKey]) async =>
      _map(await _send('POST', path, body: body, idempotencyKey: idempotencyKey));

  Future<Map<String, dynamic>> patch(String path, Object body) async => _map(await _send('PATCH', path, body: body));

  /// POST multipart avec pièce jointe facultative (justificatif de paiement ou d'ajustement) : `http` pose la frontière.
  Future<Map<String, dynamic>> postForm(String path, Map<String, String> fields, {String? filePath, String? idempotencyKey}) async {
    final req = http.MultipartRequest('POST', _uri(path));
    final h = await _base.headers;
    h.remove('Content-Type');
    req.headers.addAll({...h, if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey});
    req.fields.addAll({for (final e in fields.entries) if (e.value.isNotEmpty) e.key: e.value});
    if (filePath != null) req.files.add(await http.MultipartFile.fromPath('evidence', filePath));
    final r = await http.Response.fromStream(await _base.client.send(req));
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    return _map(_base.decodeBody(r));
  }

  /// Métiers actifs du catalogue (liste publique `/categories/`).
  Future<List<Map<String, dynamic>>> categories() async {
    final r = await _base.client.get(Uri.parse('${_base.baseUrl}/categories/?page_size=100&ordering=name'), headers: await _base.headers);
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    return _base.extractResults(_base.decodeBody(r)).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// Pièce justificative PRIVÉE (visible des deux parties seulement) : voir `BaseApi.downloadPrivate` (jeton limité à l'origine de l'API).
  @override
  Future<Uint8List> download(String url) => _base.downloadPrivate(url);
}
