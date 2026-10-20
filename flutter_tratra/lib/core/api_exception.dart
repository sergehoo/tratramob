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
      // Message précis du serveur (délai avant un nouveau code, essais épuisés…) s'il existe.
      return ApiException(
          status, _messageFrom(body) ?? 'Trop de tentatives. Patientez quelques instants puis réessayez.',
          body: body);
    }
    if (status >= 500) {
      // 502/503 explicites (ex. SMS indisponible) : message du serveur ; sinon message générique.
      return ApiException(status, (status == 502 || status == 503 ? _messageFrom(body) : null) ?? 'Erreur serveur $status',
          body: body);
    }
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

  /// Code d'erreur métier stable du serveur (`version_conflict`, `duplicate_booking`, `idempotency_key_reuse`…), s'il existe.
  String? get code {
    try {
      final data = json.decode(body);
      return data is Map && data['code'] is String ? data['code'] as String : null;
    } catch (_) {
      return null;
    }
  }

  /// Délai (secondes) avant un nouvel essai, quand le serveur l'indique (blocage de connexion).
  int? get retryAfterSeconds {
    try {
      final data = json.decode(body);
      final v = data is Map ? data['retry_after'] : null;
      return v is int ? v : int.tryParse('${v ?? ''}');
    } catch (_) {
      return null;
    }
  }

  /// Adresse du support à contacter, quand le serveur la fournit.
  String? get supportEmail {
    try {
      final data = json.decode(body);
      return data is Map && data['support_email'] is String ? data['support_email'] as String : null;
    } catch (_) {
      return null;
    }
  }

  /// Erreurs par champ renvoyées sous `fields` (« first_name » → message), quand le serveur les détaille.
  Map<String, String> get fieldErrors {
    try {
      final data = json.decode(body);
      final f = data is Map ? data['fields'] : null;
      return f is Map ? {for (final e in f.entries) '${e.key}': '${e.value}'} : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Connexion temporairement bloquée après trop de tentatives (réponse 429 `login_locked`, avec le temps restant).
  bool get isLoginLocked => statusCode == 429 && code == 'login_locked' && (retryAfterSeconds ?? 0) > 0;

  /// Écriture concurrente : l'objet a été modifié ailleurs (autre appareil, autre acteur) depuis le dernier chargement.
  bool get isVersionConflict => statusCode == 409 && code == 'version_conflict';

  /// Réservation identique déjà créée (double appui, renvoi) : identifiant de la réservation existante.
  int? get existingBookingId {
    if (statusCode != 409 || code != 'duplicate_booking') return null;
    try {
      final id = (json.decode(body) as Map)['existing_id'];
      return id is int ? id : int.tryParse('$id');
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => message;
}
