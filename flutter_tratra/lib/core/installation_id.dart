// lib/core/installation_id.dart
//
// Identifiant d'INSTALLATION de l'application (UUID v4 aléatoire, créé au premier besoin, gardé dans le stockage chiffré) : envoyé
// à l'inscription et aux demandes de code SMS (en-tête `X-Tratra-Device`) pour que le serveur limite le nombre de comptes et de
// codes par appareil (protection contre les inscriptions en masse). Il ne contient aucune donnée de l'appareil ni de l'utilisateur
// et disparaît à la désinstallation.
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String installationIdKey = 'tratra_installation_id';
const String deviceHeader = 'X-Tratra-Device';

String newInstallationId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  String hex(int i, int j) => b.sublist(i, j).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

Future<String?> installationId([FlutterSecureStorage storage = const FlutterSecureStorage()]) async {
  try {
    final existing = await storage.read(key: installationIdKey);
    if (existing != null && existing.length == 36) return existing;
    final id = newInstallationId();
    await storage.write(key: installationIdKey, value: id);
    return id;
  } catch (_) {
    return null; // stockage indisponible : la requête part sans l'en-tête (le serveur applique ses autres limites)
  }
}

/// En-têtes à ajouter aux requêtes protégées (inscription, demandes de code).
Future<Map<String, String>> deviceHeaders([FlutterSecureStorage storage = const FlutterSecureStorage()]) async {
  final id = await installationId(storage);
  return id == null ? const {} : {deviceHeader: id};
}
