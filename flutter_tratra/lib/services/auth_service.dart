// ===============================
// lib/services/auth_service.dart  (login: /auth/login/)
// ===============================
import 'dart:convert';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/user.dart';

class AuthService {
  final BaseApi api;
  AuthService(this.api);

  /// POST /auth/login/  => {access, refresh?, user?}
  Future<(String access, String? refresh)> login({
    required String username,
    required String password,
  }) async {
    final headers = await api.getHeaders(withAuth: false);
    final r = await api.client.post(
      Uri.parse('${api.baseUrl}${AppConstants.authLoginEndpoint}'),
      headers: headers,
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (r.statusCode != 200) api.handleError(r);

    final data = api.decodeBody(r);
    final access = (data['access'] ?? '').toString();
    final refresh = data['refresh']?.toString();

    if (access.isEmpty) throw Exception("Token d'accès manquant");
    await api.setAuthToken(access);

    return (access, refresh);
  }

  Future<void> logout() async {
    // si ton backend supporte /auth/logout/ tu peux garder.
    // sinon, on fait juste clear token côté app.
    try {
      final r = await api.client.post(
        Uri.parse('${api.baseUrl}${'/auth/logout/'}'),
        headers: await api.headers,
      );
      // On ne bloque pas si endpoint inexistant:
      if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 404) {
        api.handleError(r);
      }
    } catch (_) {}
    await api.setAuthToken(null);
  }

  Future<User> getCurrentUser() async {
    final r = await api.client.get(
      Uri.parse('${api.baseUrl}/users/me/'),
      headers: await api.headers,
    );
    if (r.statusCode != 200) api.handleError(r);
    return User.fromJson(api.decodeBody(r));
  }
}
