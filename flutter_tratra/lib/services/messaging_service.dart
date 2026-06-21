// lib/services/messaging_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/conversation.dart';
import 'package:flutter_tratra/models/message.dart';

class MessagingService extends BaseApi {
  MessagingService(BaseApi api, {http.Client? client}) : super(client: client);

  Future<List<Conversation>> conversations() async {
    final r = await client.get(Uri.parse('$baseUrl/conversations/'),
        headers: await headers);
    if (r.statusCode != 200) handleError(r);
    final decoded = decodeBody(r);
    final list = extractResults(decoded);
    return list.map((e) => Conversation.fromJson(e)).toList();
  }

  Future<List<Message>> messages(String conversationId) async {
    final uri = Uri.parse('$baseUrl/messages/').replace(queryParameters: {
      'conversation': conversationId,
    });
    final r = await client.get(uri, headers: await headers);
    if (r.statusCode != 200) handleError(r);
    final decoded = decodeBody(r);
    final list = extractResults(decoded);
    return list.map((e) => Message.fromJson(e)).toList();
  }

  Future<Message> send(Message message) async {
    final r = await client.post(
      Uri.parse('$baseUrl/messages/'),
      headers: await headers,
      body: json.encode(message.toJson()),
    );
    if (r.statusCode != 201) handleError(r);
    return Message.fromJson(decodeBody(r));
  }
}
