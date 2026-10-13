// lib/messaging/messaging_api.dart
//
// API de la messagerie (/me/conversations/…, /me/messages/…, /me/blocks/…) au-dessus de BaseApi : session, rafraîchissement et erreurs en
// français sont ceux de l'application. Les écritures portent un `client_id` (idempotence).
import 'dart:convert';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/upload_file.dart';
import 'package:flutter_tratra/messaging/chat_models.dart';

class ConversationPage {
  ConversationPage(this.items, this.nextPage, this.unreadTotal);
  final List<ChatConversation> items;
  final int? nextPage;
  final int unreadTotal;
}

class ThreadPage {
  ThreadPage(this.conversation, this.messages, this.hasMore, this.nextBefore);
  final ChatConversation conversation;
  final List<ChatMessage> messages;
  final bool hasMore;
  final int? nextBefore;
}

class SyncResult {
  SyncResult(this.messages, this.conversations, this.lastId, this.hasMore, this.unreadTotal);
  final List<ChatMessage> messages;
  final List<ChatConversation> conversations;
  final int lastId;
  final bool hasMore;
  final int unreadTotal;
}

class MessagingApi {
  MessagingApi(this._base);
  final BaseApi _base;

  Future<dynamic> _call(String method, String path, {Object? body}) async {
    final uri = Uri.parse('${_base.baseUrl}$path');
    final headers = await _base.headers;
    final encoded = body == null ? null : json.encode(body);
    final r = switch (method) {
      'POST' => await _base.client.post(uri, headers: headers, body: encoded ?? '{}'),
      'DELETE' => await _base.client.delete(uri, headers: headers),
      _ => await _base.client.get(uri, headers: headers),
    };
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    return r.bodyBytes.isEmpty ? null : _base.decodeBody(r);
  }

  Map<String, dynamic> _map(dynamic d) => d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  List<Map<String, dynamic>> _list(dynamic d) => (d is List ? d : const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  Future<ConversationPage> conversations({String query = '', int page = 1}) async {
    final q = query.trim().isEmpty ? '' : '&q=${Uri.encodeQueryComponent(query.trim())}';
    final d = _map(await _call('GET', '/me/conversations/?page=$page$q'));
    return ConversationPage(_list(d['results']).map(ChatConversation.fromJson).toList(), (d['next_page'] as num?)?.toInt(), ((d['unread_total'] ?? 0) as num).toInt());
  }

  Future<ThreadPage> thread(int id, {int? before, int limit = 40}) async {
    final d = _map(await _call('GET', '/me/conversations/$id/messages/?limit=$limit${before == null ? '' : '&before=$before'}'));
    return ThreadPage(ChatConversation.fromJson(_map(d['conversation'])), _list(d['results']).map(ChatMessage.fromJson).toList(), d['has_more'] == true,
        (d['next_before'] as num?)?.toInt());
  }

  /// Ouvre (ou retrouve) le fil privé UNIQUE avec un membre.
  Future<int> openDirect(int userId) async => ((_map(await _call('POST', '/me/conversations/', body: {'user': userId}))['id']) as num).toInt();

  Future<int> openBooking(int bookingId) async => ((_map(await _call('POST', '/me/conversations/', body: {'booking': bookingId}))['id']) as num).toInt();

  /// Envoie un message (texte et/ou média). Idempotent : renvoyer le même `clientId` renvoie le message déjà enregistré.
  Future<ChatMessage> send(int conversation, {required String content, required String clientId, String? filePath, void Function(double)? onProgress}) async {
    if (filePath == null) {
      final d = _map(await _call('POST', '/me/conversations/$conversation/send/', body: {'content': content, 'client_id': clientId}));
      return ChatMessage.fromJson(_map(d['message']));
    }
    final r = await _base.uploadMultipart(
      '/me/conversations/$conversation/send/',
      fields: {'content': content, 'client_id': clientId},
      files: [() => multipartFromPath('file', filePath)],
      onProgress: onProgress,
    );
    if (r.statusCode < 200 || r.statusCode >= 300) _base.handleError(r);
    return ChatMessage.fromJson(_map(_map(_base.decodeBody(r))['message']));
  }

  Future<int> markRead(int conversation) async => ((_map(await _call('POST', '/me/conversations/$conversation/read/'))['marked'] ?? 0) as num).toInt();

  Future<void> delivered(List<int> ids) async {
    if (ids.isNotEmpty) await _call('POST', '/me/messages/delivered/', body: {'ids': ids});
  }

  /// Rattrapage après une coupure : messages plus récents que `after`, de toutes mes conversations.
  Future<SyncResult> sync(int after) async {
    final d = _map(await _call('GET', '/me/messages/sync/?after=$after'));
    return SyncResult(_list(d['messages']).map(ChatMessage.fromJson).toList(), _list(d['conversations']).map(ChatConversation.fromJson).toList(),
        ((d['last_id'] ?? after) as num).toInt(), d['has_more'] == true, ((d['unread_total'] ?? 0) as num).toInt());
  }

  Future<int> unreadTotal() async => ((_map(await _call('GET', '/me/messages/unread/'))['total'] ?? 0) as num).toInt();

  Future<void> block(int userId) => _call('POST', '/me/blocks/', body: {'user': userId});
  Future<void> unblock(int userId) => _call('DELETE', '/me/blocks/$userId/');
  Future<void> report(int conversation, String reason, {bool block = false}) =>
      _call('POST', '/me/conversations/$conversation/report/', body: {'reason': reason, 'block': block});

  /// Billet signé (60 s) et chemin de la WebSocket `inbox`.
  Future<({String ticket, String path})> ticket() async {
    final d = _map(await _call('POST', '/me/realtime/ticket/'));
    return (ticket: '${d['ticket']}', path: '${d['path'] ?? '/ws/inbox/'}');
  }
}
