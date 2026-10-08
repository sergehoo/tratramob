// ===============================
// lib/services/storage_service.dart
// Stockage CHIFFRÉ (Keychain iOS / Keystore Android) du token JWT et des
// données utilisateur. Utilise la MÊME clé de token que BaseApi
// (AppConstants.authTokenKey) -> les sources de token convergent.
// ===============================
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../core/constants.dart';

class StorageService {
  final FlutterSecureStorage _storage;

  StorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// Conservé pour compatibilité (l'ancien backend SharedPreferences
  /// nécessitait une init asynchrone). No-op désormais.
  Future<void> init() async {}

  Future<void> saveAuthToken(String token) async {
    await _storage.write(key: AppConstants.authTokenKey, value: token);
  }

  Future<String?> getAuthToken() async {
    return _storage.read(key: AppConstants.authTokenKey);
  }

  Future<void> saveUserData(User user) async {
    await _storage.write(
      key: AppConstants.userDataKey,
      value: jsonEncode(user.toStorageJson()),
    );
  }

  Future<User?> getUserData() async {
    final data = await _storage.read(key: AppConstants.userDataKey);
    if (data == null) return null;
    try {
      return User.fromJson(jsonDecode(data));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAuthData() async {
    await _storage.delete(key: AppConstants.authTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userDataKey);
  }
}
