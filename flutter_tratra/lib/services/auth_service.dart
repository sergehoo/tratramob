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
    await api.setTokens(access, refresh);

    return (access, refresh);
  }

  Future<void> logout() async {
    final refresh = await api.storage.read(key: AppConstants.refreshTokenKey);
    try {
      // TokenBlacklistView attend explicitement le refresh token. La révocation
      // reste best-effort : une déconnexion locale doit toujours purger la session.
      if (refresh != null && refresh.isNotEmpty) {
        final r = await api.client.post(
          Uri.parse('${api.baseUrl}${AppConstants.authLogoutEndpoint}'),
          headers: await api.headers,
          body: jsonEncode({'refresh': refresh}),
        );
        if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 205) {
          api.handleError(r);
        }
      }
    } catch (_) {
      // Hors ligne ou jeton déjà expiré : la purge locale reste requise.
    } finally {
      await api.clearTokens();
    }
  }

  /// POST /auth/otp/request/ — envoie un code de vérification au téléphone du compte
  /// (utilisateur connecté). Le code éventuellement renvoyé en développement n'est JAMAIS exposé.
  Future<void> requestOtp() async {
    final r = await api.client.post(
      Uri.parse('${api.baseUrl}${AppConstants.otpRequestEndpoint}'),
      headers: await api.headers,
    );
    if (r.statusCode != 200 && r.statusCode != 201) api.handleError(r);
  }

  /// POST /auth/otp/verify/ { code } — marque le compte comme vérifié.
  Future<void> verifyOtp(String code) async {
    final r = await api.client.post(
      Uri.parse('${api.baseUrl}${AppConstants.otpVerifyEndpoint}'),
      headers: await api.headers,
      body: jsonEncode({'code': code}),
    );
    if (r.statusCode != 200) api.handleError(r);
  }

  Future<User> getCurrentUser() async {
    final r = await api.client.get(
      Uri.parse('${api.baseUrl}${AppConstants.usersMeEndpoint}'),
      headers: await api.headers,
    );
    if (r.statusCode != 200) api.handleError(r);
    return User.fromJson(api.decodeBody(r));
  }
}
