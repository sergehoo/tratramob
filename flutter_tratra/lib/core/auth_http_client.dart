// lib/core/auth_http_client.dart
//
// Client HTTP qui intercepte les 401 : tente UN rafraîchissement du token JWT
// puis rejoue la requête. Centralise le refresh pour toute l'app (toutes les
// requêtes passant par BaseApi.client en bénéficient automatiquement).
import 'dart:async';
import 'package:http/http.dart' as http;

/// Renvoie un nouvel access token (ou null si le refresh échoue).
typedef RefreshCallback = Future<String?> Function();

class AuthHttpClient extends http.BaseClient {
  final http.Client _inner;
  final RefreshCallback _refresh;

  AuthHttpClient(this._inner, {required RefreshCallback refresh}) : _refresh = refresh;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Bufferise le corps pour pouvoir rejouer la requête après un refresh.
    final bodyBytes = await request.finalize().toBytes();

    final first = await _inner.send(_rebuild(request, bodyBytes));
    if (first.statusCode != 401) return first;

    // Vide le flux de la 1re réponse puis tente un refresh.
    await first.stream.drain<void>();
    final newAccess = await _refresh();
    if (newAccess == null || newAccess.isEmpty) {
      // Refresh impossible -> on renvoie un 401 propre (requête rejouée à vide).
      return _inner.send(_rebuild(request, bodyBytes));
    }

    final retry = _rebuild(request, bodyBytes);
    retry.headers['Authorization'] = 'Bearer $newAccess';
    return _inner.send(retry);
  }

  http.Request _rebuild(http.BaseRequest src, List<int> body) {
    final r = http.Request(src.method, src.url);
    r.headers.addAll(src.headers);
    r.bodyBytes = body;
    r.followRedirects = src.followRedirects;
    r.maxRedirects = src.maxRedirects;
    r.persistentConnection = src.persistentConnection;
    return r;
  }

  @override
  void close() => _inner.close();
}
