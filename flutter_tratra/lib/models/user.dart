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

    return User(
      id: _asString(json['id']), // accepte int | string
      email: _asString(json['email']),
      firstName: _asString(json['first_name'], fallback: '').isEmpty
          ? null
          : _asString(json['first_name']),
      lastName: _asString(json['last_name'], fallback: '').isEmpty
          ? null
          : _asString(json['last_name']),
      phoneNumber: _asString(json['phone_number'], fallback: '').isEmpty
          ? null
          : _asString(json['phone_number']),
      profileImage: _asString(json['profile_image'], fallback: '').isEmpty
          ? null
          : _asString(json['profile_image']),
      userType: _asString(json['user_type'], fallback: 'client'),
      dateJoined: _asDate(json['date_joined']),
      isActive: _asBool(json['is_active'], fallback: true),
      preferences: _asMap(json['preferences']),
      username: _asString(json['username'], fallback: '').isEmpty
          ? null
          : _asString(json['username']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'phone_number': phoneNumber,
        'profile_image': profileImage,
        'user_type': userType,
        'date_joined': dateJoined?.toIso8601String(),
        'is_active': isActive,
        'preferences': preferences,
        'username': username,
      };
}
