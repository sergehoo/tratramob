// lib/statuses/status_api.dart
//
// API des statuts (/statuses/…) au-dessus de BaseApi. La publication porte un `client_id` : un renvoi après coupure réseau ne publie
// jamais deux fois. Une vue n'est enregistrée que lorsque le statut est RÉELLEMENT affiché (`view`), jamais au préchargement.
import 'dart:convert';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/upload_file.dart';
import 'package:flutter_tratra/statuses/status_models.dart';

class StatusApi {
  StatusApi(this._base);
  final BaseApi _base;

  Future<dynamic> _call(String method, String path, {Object? body}) async {
    final uri = Uri.parse('${_base.baseUrl}$path');
    final headers = await _base.headers;
    final encoded = body == null ? null : json.encode(body);
    final r = switch (method) {
      'POST' => await _base.client.post(uri, headers: headers, body: encoded ?? '{}'),
      'PUT' => await _base.client.put(uri, headers: headers, body: encoded ?? '{}'),
      'DELETE' => await _base.client.delete(uri, headers: headers),
      _ => await _base.client.get(uri, headers: headers),
    };
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    return r.bodyBytes.isEmpty ? null : _base.decodeBody(r);
  }

  Map<String, dynamic> _map(dynamic d) => d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};

  Future<StatusFeed> feed() async => StatusFeed.fromJson(_map(await _call('GET', '/statuses/feed/')));

  Future<({List<StatusGroup> groups, int? next})> discover({int page = 1}) async {
    final d = _map(await _call('GET', '/statuses/discover/?page=$page'));
    return (
      groups: ((d['results'] as List?) ?? const []).whereType<Map>().map((e) => StatusGroup.fromJson(e.cast<String, dynamic>())).toList(),
      next: (d['next_page'] as num?)?.toInt(),
    );
  }

  /// Membres qui ont un statut que je peux voir (anneaux des avatars). Serveur plus ancien sans ce point d'accès : liste vide.
  Future<List<StatusPresenceEntry>> presence() async {
    final d = _map(await _call('GET', '/statuses/presence/'));
    return ((d['results'] as List?) ?? const []).whereType<Map>().map((e) => StatusPresenceEntry.fromJson(e.cast<String, dynamic>())).toList();
  }

  /// Statuts actifs d'un membre (toucher son avatar), avec les droits du serveur.
  Future<StatusGroup> author(int userId) async => StatusGroup.fromJson(_map(await _call('GET', '/statuses/authors/$userId/')));

  Future<StatusItem> publish({
    String text = '',
    String? filePath,
    required String audience,
    required bool allowReplies,
    String background = 'green',
    required String clientId,
    void Function(double)? onProgress,
  }) async {
    final fields = {'text': text, 'audience': audience, 'allow_replies': '$allowReplies', 'client_id': clientId, if (filePath == null) 'background': background};
    final r = await _base.uploadMultipart('/statuses/',
        fields: fields, files: [if (filePath != null) () => multipartFromPath('file', filePath)], onProgress: onProgress, networkRetries: 2);
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    return StatusItem.fromJson(_map(_map(_base.decodeBody(r))['status']));
  }

  Future<void> delete(int id) => _call('DELETE', '/statuses/$id/');

  /// À appeler quand le statut est réellement affiché. Renvoie vrai si la vue a été comptée.
  Future<bool> view(int id) async => _map(await _call('POST', '/statuses/$id/view/'))['counted'] == true;

  /// Liste NOMINATIVE des lecteurs : réservée à l'auteur.
  Future<List<StatusReader>> viewers(int id) async {
    final d = _map(await _call('GET', '/statuses/$id/viewers/'));
    return ((d['results'] as List?) ?? const []).whereType<Map>().map((e) => StatusReader.fromJson(e.cast<String, dynamic>())).toList();
  }

  Future<void> reply(int id, String content) => _call('POST', '/statuses/$id/reply/', body: {'content': content});
  Future<void> report(int id, String reason) => _call('POST', '/statuses/$id/report/', body: {'reason': reason});

  Future<Map<String, dynamic>> settings() async => _map(await _call('GET', '/statuses/settings/'));
  Future<Map<String, dynamic>> saveSettings({String? audience, bool? allowReplies}) async =>
      _map(await _call('PUT', '/statuses/settings/', body: {if (audience != null) 'audience': audience, if (allowReplies != null) 'allow_replies': allowReplies}));

  Future<List<Map<String, dynamic>>> contacts() async =>
      (((_map(await _call('GET', '/statuses/contacts/')))['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  Future<void> exclude(int userId) => _call('POST', '/statuses/exclusions/', body: {'user': userId});
  Future<void> include(int userId) => _call('DELETE', '/statuses/exclusions/$userId/');
}
