// lib/continuity/vault.dart
//
// Stockage local CHIFFRÉ (Keychain iOS / Keystore Android) des données de continuité : dernier état des activités,
// brouillons et file d'attente hors ligne. Chaque clé est CLOISONNÉE par compte (`cont.<compte>.<nom>`) : un second
// compte sur le même téléphone ne voit jamais les données du premier. Une déconnexion volontaire efface tout.
// Best-effort : un coffre illisible ne fait jamais échouer l'application, il se comporte comme un coffre vide.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ContinuityVault {
  ContinuityVault([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const String prefix = 'cont.';
  String _k(String userId, String name) => '$prefix$userId.$name';

  Future<Object?> read(String userId, String name) async {
    try {
      final raw = await _s.read(key: _k(userId, name));
      return raw == null ? null : jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String userId, String name, Object value) async {
    try {
      await _s.write(key: _k(userId, name), value: jsonEncode(value));
    } catch (_) {}
  }

  Future<void> delete(String userId, String name) async {
    try {
      await _s.delete(key: _k(userId, name));
    } catch (_) {}
  }

  /// Noms (sans préfixe de compte) enregistrés pour ce compte, ex. `draft.12`.
  Future<List<String>> names(String userId) async {
    try {
      final all = await _s.readAll();
      final head = '$prefix$userId.';
      return all.keys.where((k) => k.startsWith(head)).map((k) => k.substring(head.length)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Déconnexion volontaire : efface TOUTES les données de continuité, de tous les comptes.
  Future<void> wipeAll() async {
    try {
      final all = await _s.readAll();
      // Copie des clés AVANT de supprimer : on ne modifie jamais la table qu'on parcourt.
      final mine = all.keys.where((k) => k.startsWith(prefix)).toList();
      for (final k in mine) {
        await _s.delete(key: k);
      }
    } catch (_) {}
  }
}
