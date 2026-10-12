// lib/core/upload_file.dart
//
// Fichiers envoyés au serveur (pièces KYC, photos, justificatifs, preuves) : le type est déterminé par le CONTENU du fichier, pas par son nom.
// `image_picker` (qualité réduite) renvoie parfois un fichier sans extension, ou avec l'extension d'origine (.webp, .heic) alors que les octets
// sont déjà du JPEG : le type déduit du nom (`application/octet-stream`, `image/webp`) faisait refuser la pièce (« Formats autorisés : PDF, JPEG
// et PNG »). Le nom et le type envoyés correspondent donc au contenu réel ; un contenu inconnu garde le comportement historique.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Type MIME et extension déduits des premiers octets, ou `null` si le format n'est pas reconnu.
({String mime, String ext})? sniffUpload(List<int> head) {
  bool starts(List<int> sig, [int at = 0]) {
    if (head.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (head[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0xFF, 0xD8, 0xFF])) return (mime: 'image/jpeg', ext: '.jpg');
  if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return (mime: 'image/png', ext: '.png');
  if (starts(const [0x25, 0x50, 0x44, 0x46, 0x2D])) return (mime: 'application/pdf', ext: '.pdf');
  if (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8)) return (mime: 'image/webp', ext: '.webp');
  return null;
}

/// Équivalent de `http.MultipartFile.fromPath` avec nom et type fidèles au contenu.
Future<http.MultipartFile> multipartFromPath(String field, String path) async {
  final head = <int>[];
  await for (final chunk in File(path).openRead(0, 16)) {
    head.addAll(chunk);
  }
  final kind = sniffUpload(head);
  if (kind == null) return http.MultipartFile.fromPath(field, path);
  return http.MultipartFile.fromPath(field, path, filename: 'document${kind.ext}', contentType: MediaType.parse(kind.mime));
}
