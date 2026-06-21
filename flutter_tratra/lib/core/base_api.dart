// ===============================
// lib/core/base_api.dart ✅ (tel quel, juste petite sécurité sur initialize)
// ===============================
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tratra/core/constants.dart';

class BaseApi {
  final http.Client client;
  final FlutterSecureStorage storage;

  String? _authToken;
  bool _didInit = false;

  BaseApi({http.Client? client})
      : client = client ?? http.Client(),
        storage = const FlutterSecureStorage();

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

  Future<Map<String, String>> get headers async {
    await initialize();
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
    if (r.statusCode == 401) {
      throw Exception('Non autorisé — veuillez vous reconnecter');
    } else if (r.statusCode == 403) {
      throw Exception('Accès refusé');
    } else if (r.statusCode == 404) {
      throw Exception('Ressource non trouvée');
    } else if (r.statusCode >= 500) {
      throw Exception('Erreur serveur ${r.statusCode}');
    } else {
      throw Exception('Erreur ${r.statusCode}: ${r.body}');
    }
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
