// ===============================
// lib/services/user_service.dart ✅ (optionnel mais propre)
// ===============================
import 'dart:convert';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/user.dart';

class UserService {
  final BaseApi api;
  UserService(this.api);

  Future<User> update(User user) async {
    final r = await api.client.put(
      Uri.parse('${api.baseUrl}/users/${user.id}/'),
      headers: await api.headers,
      body: jsonEncode(user.toJson()),
    );
    if (r.statusCode != 200) api.handleError(r);
    return User.fromJson(api.decodeBody(r));
  }
}
