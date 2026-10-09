// core/api_exception.dart
//
// Erreur d'API typée : `toString()` renvoie un message FRANÇAIS lisible (jamais le JSON
// brut de la réponse). Miroir de `ApiError` / `apiErrorMessage` côté web (lib/api.ts).
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body = ''});

  final int statusCode;
  final String message;

  /// Corps brut de la réponse (diagnostic uniquement : à ne jamais afficher).
  final String body;

  factory ApiException.fromResponse(http.Response r) {
    final status = r.statusCode;
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (status == 401) {
      return ApiException(status, 'Non autorisé — veuillez vous reconnecter', body: body);
    }
    if (status == 403) return ApiException(status, 'Accès refusé', body: body);
    if (status == 404) return ApiException(status, 'Ressource non trouvée', body: body);
    if (status == 429) {
      return ApiException(status, 'Trop de tentatives. Patientez quelques instants puis réessayez.', body: body);
    }
    if (status >= 500) return ApiException(status, 'Erreur serveur $status', body: body);
    return ApiException(status, _messageFrom(body) ?? 'La requête a été refusée. Vérifiez les informations saisies.',
        body: body);
  }

  /// Premier message lisible d'un corps d'erreur DRF : `detail`, `non_field_errors`,
  /// ou première erreur de champ (« champ : message »).
  static String? _messageFrom(String body) {
    try {
      final data = json.decode(body);
      return _first(data);
    } catch (_) {
      return null;
    }
  }

  static String? _first(dynamic data, [String? field]) {
    if (data is String) {
      return (field == null || field == 'detail' || field == 'non_field_errors') ? data : '$field : $data';
    }
    if (data is List) {
      for (final item in data) {
        final m = _first(item, field);
        if (m != null) return m;
      }
    }
    if (data is Map) {
      for (final key in ['detail', 'non_field_errors']) {
        if (data.containsKey(key)) {
          final m = _first(data[key], key);
          if (m != null) return m;
        }
      }
      for (final entry in data.entries) {
        if (entry.key == 'code') continue;
        final m = _first(entry.value, entry.key.toString());
        if (m != null) return m;
      }
    }
    return null;
  }

  @override
  String toString() => message;
}
