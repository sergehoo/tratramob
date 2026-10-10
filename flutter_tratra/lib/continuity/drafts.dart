// lib/continuity/drafts.dart
//
// Brouillon de réservation : ce que l'utilisateur a saisi n'est jamais perdu (fermeture, plantage, coupure réseau,
// changement d'écran). Un brouillon est local, chiffré, cloisonné par compte, effacé après confirmation du serveur ou
// à la déconnexion volontaire.
//
// Clé d'idempotence : [BookingDraft.idempotencyKey] = identifiant du brouillon + empreinte du CONTENU. Renvoyer la même
// demande (double appui, après un plantage) réutilise la même clé → le serveur retrouve la réservation déjà créée ;
// modifier un champ change l'empreinte → nouvelle intention, nouvelle clé. Aucun doublon dans les deux cas.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_tratra/continuity/vault.dart';

/// Identifiant aléatoire (cryptographique) en hexadécimal.
String randomHex(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Empreinte stable (FNV-1a 32 bits) : identique d'un lancement à l'autre, contrairement à `Object.hash`.
String fingerprint(String input) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(input)) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

class BookingDraft {
  BookingDraft({
    required this.serviceId,
    required this.base,
    required this.date,
    required this.hour,
    required this.minute,
    this.address = '',
    this.city = '',
    this.postalCode = '',
    this.notes = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String serviceId;
  final String base; // identifiant du brouillon (une intention)
  final DateTime date; // jour choisi
  final int hour;
  final int minute;
  final String address;
  final String city;
  final String postalCode;
  final String notes;
  final DateTime updatedAt;

  bool get isEmpty => address.trim().isEmpty && city.trim().isEmpty && postalCode.trim().isEmpty && notes.trim().isEmpty;

  String get _content =>
      [serviceId, date.toIso8601String().substring(0, 10), hour, minute, address.trim(), city.trim(), postalCode.trim(), notes.trim()].join('\u0001');

  /// 8 à 80 caractères [A-Za-z0-9-] : accepté par le serveur.
  String get idempotencyKey => 'bk-$base-${fingerprint(_content)}';

  Map<String, dynamic> toJson() => {
        'service_id': serviceId,
        'base': base,
        'date': date.toIso8601String(),
        'hour': hour,
        'minute': minute,
        'address': address,
        'city': city,
        'postal_code': postalCode,
        'notes': notes,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory BookingDraft.fromJson(Map<String, dynamic> j) => BookingDraft(
        serviceId: '${j['service_id']}',
        base: '${j['base']}',
        date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
        hour: (j['hour'] as num?)?.toInt() ?? 9,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        address: '${j['address'] ?? ''}',
        city: '${j['city'] ?? ''}',
        postalCode: '${j['postal_code'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
        updatedAt: DateTime.tryParse('${j['updated_at']}'),
      );

  BookingDraft copyWith({DateTime? date, int? hour, int? minute, String? address, String? city, String? postalCode, String? notes}) => BookingDraft(
        serviceId: serviceId,
        base: base,
        date: date ?? this.date,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        address: address ?? this.address,
        city: city ?? this.city,
        postalCode: postalCode ?? this.postalCode,
        notes: notes ?? this.notes,
      );
}

class DraftStore {
  DraftStore([ContinuityVault? vault]) : _vault = vault ?? ContinuityVault();
  final ContinuityVault _vault;

  static const Duration maxAge = Duration(days: 7);
  static String _name(String serviceId) => 'draft.$serviceId';

  Future<BookingDraft?> load(String userId, String serviceId, {DateTime? now}) async {
    final raw = await _vault.read(userId, _name(serviceId));
    if (raw is! Map) return null;
    final draft = BookingDraft.fromJson(raw.cast<String, dynamic>());
    if ((now ?? DateTime.now()).difference(draft.updatedAt) > maxAge) {
      await discard(userId, serviceId);
      return null;
    }
    return draft;
  }

  /// Un brouillon vide n'est pas conservé.
  Future<void> save(String userId, BookingDraft draft) async {
    if (draft.isEmpty) {
      await discard(userId, draft.serviceId);
      return;
    }
    await _vault.write(userId, _name(draft.serviceId), draft.toJson());
  }

  Future<void> discard(String userId, String serviceId) => _vault.delete(userId, _name(serviceId));
}
