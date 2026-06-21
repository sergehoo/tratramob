// lib/services/notification_service.dart
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/notification.dart' as model;

class NotificationService extends BaseApi {
  NotificationService(BaseApi api, {http.Client? client})
      : super(client: client);

  Future<List<model.Notification>> list() async {
    final r = await client.get(Uri.parse('$baseUrl/notifications/'),
        headers: await headers);
    if (r.statusCode != 200) handleError(r);
    final decoded = decodeBody(r);
    final list = extractResults(decoded);
    return list.map((e) => model.Notification.fromJson(e)).toList();
  }

  Future<void> markRead(String id) async {
    final r = await client.patch(
      Uri.parse('$baseUrl/notifications/$id/'),
      headers: await headers,
      body: '{"read":true}',
    );
    if (r.statusCode != 200) handleError(r);
  }
}
