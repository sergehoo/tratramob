// ===============================
// lib/core/base_api.dart ✅ (tel quel, juste petite sécurité sur initialize)
// ===============================
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/auth_http_client.dart';
import 'package:flutter_tratra/core/network_errors.dart';

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

  /// Télécharge un document PRIVÉ (justificatif, reçu) avec la session. Le jeton n'est envoyé QU'À l'origine de l'API : une URL d'une
  /// autre origine est refusée sans requête (jamais de fuite du jeton). L'URL renvoyée par l'API est relative à l'origine.
  Future<Uint8List> downloadPrivate(String url) async {
    final origin = Uri.parse(baseUrl).origin;
    final uri = url.startsWith('http') ? Uri.parse(url) : Uri.parse('$origin$url');
    if (uri.origin != origin) throw ApiException(0, 'Pièce jointe indisponible.');
    final r = await client.get(uri, headers: await headers);
    if (r.statusCode < 200 || r.statusCode >= 300) handleError(r);
    return r.bodyBytes;
  }

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
      ).timeout(const Duration(seconds: 15));
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

  /// Envoi multipart AVEC progression (0..1) : le corps est transmis par morceaux et compté (le client à rafraîchissement automatique
  /// met le corps en mémoire avant l'envoi, sans progression). Sur 401, UN rafraîchissement de session puis un nouvel essai.
  /// Les envois de messages et de statuts portent un `client_id` : rejouer après une coupure réseau ne crée jamais de doublon
  /// (`networkRetries` nouveaux essais automatiques, espacés de `retryDelay`, puis 2 × `retryDelay`…).
  Future<http.Response> uploadMultipart(
    String path, {
    Map<String, String> fields = const {},
    List<Future<http.MultipartFile> Function()> files = const [],
    void Function(double)? onProgress,
    Duration timeout = const Duration(minutes: 5),
    int networkRetries = 0,
    Duration retryDelay = const Duration(seconds: 1),
  }) async {
    Future<http.Response> attempt(String? access) async {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..fields.addAll(fields)
        ..headers['Accept'] = 'application/json';
      if (access != null && access.isNotEmpty) req.headers['Authorization'] = 'Bearer $access';
      for (final f in files) {
        req.files.add(await f());
      }
      final total = req.contentLength;
      // finalize() pose l'en-tête « multipart/form-data; boundary=… » : il doit précéder la copie des en-têtes, sinon la requête part sans
      // Content-Type et le serveur répond « Type de média « » non supporté ».
      // Progression RÉELLE : chaque morceau est compté quand le client HTTP le prend pour l'écrire sur la connexion (il suspend la lecture
      // tant que le réseau n'a pas absorbé le précédent) — et non quand il est mis en mémoire, ce qui affichait 100 % aussitôt.
      var sent = 0;
      final body = req.finalize().map((chunk) {
        sent += chunk.length;
        if (total > 0) onProgress?.call((sent / total).clamp(0.0, 1.0));
        return chunk;
      });
      final request = _StreamBodyRequest(req.method, req.url, body)
        ..headers.addAll(req.headers)
        ..contentLength = total;
      final sw = Stopwatch()..start();
      try {
        final response = await http.Response.fromStream(await _raw.send(request).timeout(timeout));
        if (kDebugMode) debugPrint('[envoi] $path : HTTP ${response.statusCode} en ${sw.elapsedMilliseconds} ms ($sent/$total octets)');
        return response;
      } catch (e) {
        if (kDebugMode) debugPrint('[envoi] $path : ${e.runtimeType} après ${sw.elapsedMilliseconds} ms ($sent/$total octets) : $e');
        rethrow;
      }
    }

    // Envoi idempotent (`client_id`) : une coupure du transport est rejouée automatiquement (nouvelle connexion), jamais un délai dépassé
    // ni une réponse du serveur.
    Future<http.Response> attemptWithRetries(String? access) async {
      for (var i = 0;; i++) {
        try {
          return await attempt(access);
        } catch (e) {
          if (i >= networkRetries || !isTransientNetworkError(e)) rethrow;
          await Future<void>.delayed(retryDelay * (i + 1));
        }
      }
    }

    await initialize();
    String? access;
    try {
      access = await storage.read(key: AppConstants.authTokenKey);
    } catch (_) {
      access = _authToken;
    }
    var r = await attemptWithRetries(access);
    if (r.statusCode == 401) {
      final fresh = await _refreshAccess();
      if (fresh != null) r = await attemptWithRetries(fresh);
    }
    return r;
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


/// Requête dont le corps est un flux déjà construit (multipart finalisé et compté) : lu à la demande par le client HTTP.
class _StreamBodyRequest extends http.BaseRequest {
  _StreamBodyRequest(super.method, super.url, this._body);
  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
