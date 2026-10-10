// lib/services/cash_service.dart
//
// Paiement en ESPÈCES d'une réservation : état et historique, déclaration (justificatif facultatif), confirmation ou contestation par
// l'AUTRE partie. Les règles restent côté serveur ; ce service ne simule rien. Jamais un encaissement « vérifié par un prestataire ».
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart' show PrivateDownloader;

class CashService extends BaseApi implements PrivateDownloader {
  CashService(BaseApi api, {super.client});

  Map<String, dynamic> _map(dynamic d) => d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};

  /// `{booking_id, booking_status, payment, cash}` — `cash` est nul quand la réservation se règle par un prestataire de paiement.
  Future<Map<String, dynamic>> get(int bookingId) async {
    final r = await client.get(Uri.parse('$baseUrl/bookings/$bookingId/payment/'), headers: await headers);
    if (r.statusCode != 200) handleError(r);
    return _map(decodeBody(r));
  }

  /// Déclare un paiement (multipart : photo du reçu facultative). `idempotencyKey` identique = même intention rejouée sans doublon.
  Future<Map<String, dynamic>> declare(int bookingId, Map<String, String> fields, {String? filePath, required String idempotencyKey}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/bookings/$bookingId/payment/cash/'));
    final h = await headers;
    h.remove('Content-Type');
    req.headers.addAll({...h, 'Idempotency-Key': idempotencyKey});
    req.fields.addAll({for (final e in fields.entries) if (e.value.isNotEmpty) e.key: e.value});
    if (filePath != null) req.files.add(await http.MultipartFile.fromPath('receipt', filePath));
    final r = await http.Response.fromStream(await client.send(req));
    if (r.statusCode < 200 || r.statusCode >= 300) handleError(r);
    return _map(decodeBody(r));
  }

  /// Confirme (`confirm: true`) ou conteste (`false`, motif obligatoire) une déclaration de l'AUTRE partie.
  Future<Map<String, dynamic>> respond(int declarationId, bool confirm, [String reason = '']) async {
    final r = await client.post(Uri.parse('$baseUrl/payments/cash/$declarationId/respond/'),
        headers: await headers, body: json.encode({'confirm': confirm, 'reason': reason}));
    if (r.statusCode != 200) handleError(r);
    return _map(decodeBody(r));
  }

  @override
  Future<Uint8List> download(String url) => downloadPrivate(url);
}
