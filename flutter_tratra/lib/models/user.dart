// lib/models/user.dart

import 'package:flutter/foundation.dart';

@immutable
class User {
  final String id; // stocké en String côté app
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? profileImage;
  final String userType; // 'client' | 'artisan' | autre
  final DateTime? dateJoined;
  final bool isActive;
  final Map<String, dynamic>? preferences;
  final String? username; // utile si login par username

  /// Téléphone vérifié par code OTP (`is_verified` côté API).
  final bool isVerified;

  const User({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.profileImage,
    required this.userType,
    this.dateJoined,
    required this.isActive,
    this.preferences,
    this.username,
    this.isVerified = false,
  });

  /// Concatène prénom/nom en gérant les null/vides proprement.
  String get fullName {
    final f = (firstName ?? '').trim();
    final l = (lastName ?? '').trim();
    final join = [f, l].where((s) => s.isNotEmpty).join(' ');
    // fallback: username ou email si pas de nom
    if (join.isNotEmpty) return join;
    if ((username ?? '').isNotEmpty) return username!;
    return email;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    // Helpers légers pour tolérer les types variables
    String _asString(dynamic v, {String fallback = ''}) {
      if (v == null) return fallback;
      if (v is String) return v;
      if (v is num || v is bool) return v.toString();
      return fallback;
    }

    bool _asBool(dynamic v, {bool fallback = true}) {
      if (v == null) return fallback;
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
      }
      return fallback;
    }

    DateTime? _asDate(dynamic v) {
      if (v == null) return null;
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    Map<String, dynamic>? _asMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
      return null;
    }

    dynamic _firstPresent(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null) return value;
      }
      return null;
    }

    String? _optionalString(dynamic value) {
      final parsed = _asString(value).trim();
      return parsed.isEmpty ? null : parsed;
    }

    return User(
      id: _asString(json['id']), // accepte int | string
      email: _asString(json['email']),
      firstName: _optionalString(json['first_name']),
      lastName: _optionalString(json['last_name']),
      // L'API Django expose `phone` et `profile_picture`; les alias conservent
      // la compatibilité avec les anciennes réponses mobile.
      phoneNumber: _optionalString(_firstPresent(['phone', 'phone_number'])),
      profileImage:
          _optionalString(_firstPresent(['profile_picture', 'profile_image'])),
      userType: _asString(json['user_type'], fallback: 'client'),
      dateJoined: _asDate(json['date_joined']),
      isActive: _asBool(json['is_active'], fallback: true),
      preferences: _asMap(json['preferences']),
      isVerified: _asBool(json['is_verified'], fallback: false),
      username: _asString(json['username'], fallback: '').isEmpty
          ? null
          : _asString(json['username']),
    );
  }

  /// Format d'écriture de l'API Django. Les champs calculés / lecture seule ne
  /// sont pas envoyés, et une image doit être téléversée en multipart plutôt
  /// qu'en envoyant une URL dans un JSON de profil.
  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'email': email,
      'user_type': userType,
    };
    if ((username ?? '').trim().isNotEmpty) body['username'] = username!.trim();
    if ((firstName ?? '').trim().isNotEmpty) {
      body['first_name'] = firstName!.trim();
    }
    if ((lastName ?? '').trim().isNotEmpty) {
      body['last_name'] = lastName!.trim();
    }
    if ((phoneNumber ?? '').trim().isNotEmpty) {
      body['phone'] = phoneNumber!.trim();
    }
    return body;
  }

  /// Un utilisateur ne peut pas changer son rôle depuis l'écran profil.
  /// Le PATCH côté API permet aussi d'éviter de redemander son mot de passe.
  Map<String, dynamic> toProfileUpdateJson() {
    final body = toJson();
    body.remove('user_type');
    return body;
  }

  /// Représentation complète destinée uniquement au cache chiffré local.
  /// Elle ne doit pas être envoyée à l'API car elle contient des champs
  /// serveur en lecture seule.
  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phoneNumber,
        'profile_picture': profileImage,
        'user_type': userType,
        'date_joined': dateJoined?.toIso8601String(),
        'is_active': isActive,
        'preferences': preferences,
        'username': username,
      };
}
