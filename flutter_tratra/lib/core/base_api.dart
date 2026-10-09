// ===============================
// lib/core/base_api.dart ✅ (tel quel, juste petite sécurité sur initialize)
// ===============================
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/auth_http_client.dart';

class BaseApi {
  final http.Client _raw;          // client brut (sans interception) pour le refresh
  late final http.Client client;   // client public avec auto-refresh sur 401
  final FlutterSecureStorage storage;

  String? _authToken;
  bool _didInit = false;

  BaseApi({http.Client? client})
      : _raw = client ?? http.Client(),
        storage = const FlutterSecureStorage() {
    this.client = AuthHttpClient(_raw, refresh: _refreshAccess);
  }

  String get baseUrl => AppConstants.baseUrl;

  Future<void> initialize() async {
    if (_didInit) return;
    _authToken = await storage.read(key: AppConstants.authTokenKey);
    _didInit = true;
  }

  Future<void> setAuthToken(String? token) async {
    _authToken = token;
    _didInit = true;
    if (token != null && token.isNotEmpty) {
      await storage.write(key: AppConstants.authTokenKey, value: token);
    } else {
      await storage.delete(key: AppConstants.authTokenKey);
    }
  }

  /// Stocke l'access ET le refresh token (à la connexion).
  Future<void> setTokens(String? access, String? refresh) async {
    await setAuthToken(access);
    if (refresh != null && refresh.isNotEmpty) {
      await storage.write(key: AppConstants.refreshTokenKey, value: refresh);
    } else {
      await storage.delete(key: AppConstants.refreshTokenKey);
    }
  }

  Future<void> clearTokens() async {
    _authToken = null;
    await storage.delete(key: AppConstants.authTokenKey);
    await storage.delete(key: AppConstants.refreshTokenKey);
  }

  /// Rafraîchit l'access token via le refresh stocké. Retourne le nouvel access
  /// (ou null). Utilise le client BRUT pour éviter toute récursion d'interception.
  Future<String?> _refreshAccess() async {
    final refresh = await storage.read(key: AppConstants.refreshTokenKey);
    if (refresh == null || refresh.isEmpty) return null;
    try {
      final r = await _raw.post(
        Uri.parse('$baseUrl${AppConstants.authRefreshEndpoint}'),
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );
      if (r.statusCode != 200) return null;
      final data = json.decode(utf8.decode(r.bodyBytes));
      final access = (data['access'] ?? '').toString();
      if (access.isEmpty) return null;
      _authToken = access;
      _didInit = true;
      await storage.write(key: AppConstants.authTokenKey, value: access);
      // rotation éventuelle du refresh (SimpleJWT ROTATE_REFRESH_TOKENS)
      final newRefresh = data['refresh']?.toString();
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await storage.write(key: AppConstants.refreshTokenKey, value: newRefresh);
      }
      return access;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> get headers async {
    // Le stockage chiffré est la source de vérité du jeton : les services métier sont des
    // instances distinctes et ne doivent jamais réutiliser le jeton d'un compte précédent
    // après une déconnexion / reconnexion avec un autre compte.
    try {
      _authToken = await storage.read(key: AppConstants.authTokenKey);
    } catch (_) {
      await initialize();
    }
    final h = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  Future<Map<String, String>> getHeaders({bool withAuth = true}) async {
    final h = await headers;
    if (!withAuth) h.remove('Authorization');
    return h;
  }

  List<dynamic> extractResults(dynamic decoded) {
    if (decoded is Map && decoded.containsKey('results')) {
      return (decoded['results'] as List?) ?? const [];
    }
    if (decoded is List) return decoded;
    return const [];
  }

  Never handleError(http.Response r) {
    throw ApiException.fromResponse(r);
  }

  dynamic decodeBody(http.Response r) {
    try {
      return json.decode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return r.body;
    }
  }

  String encodeBody(Map<String, dynamic> data) => jsonEncode(data);

  Map<String, dynamic> extractPagination(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final results = decoded['results'];
      final countFromResults = results is List ? results.length : 0;
      return {
        'count': (decoded['count'] is num)
            ? (decoded['count'] as num).toInt()
            : countFromResults,
        'next': decoded.containsKey('next') ? decoded['next'] : null,
        'previous':
            decoded.containsKey('previous') ? decoded['previous'] : null,
      };
    }
    if (decoded is List) {
      return {'count': decoded.length, 'next': null, 'previous': null};
    }
    return const {'count': 0, 'next': null, 'previous': null};
  }
}
