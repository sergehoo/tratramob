// lib/screens/trust/identity_api.dart
//
// Tratra ID : vérification publique d'un badge, QR de mission, badge de l'artisan.
// Mêmes endpoints, mêmes règles que le web : la validité est décidée par le serveur à chaque appel.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;

/// Résultat affichable d'une vérification (badge permanent ou QR de mission).
@immutable
class IdentityOutcome {
  const IdentityOutcome({required this.ok, required this.tone, required this.title, required this.message, this.holder, this.tratraId, this.extra});

  final bool ok;

  /// `ok` (vert), `danger` (rouge : badge révoqué / inconnu), `warn` (orange : QR expiré, déjà utilisé…).
  final String tone;
  final String title;
  final String message;
  final Map<String, dynamic>? holder;
  final String? tratraId;
  final String? extra;
}

const _passRefusals = <String, String>{
  'unknown': 'Ce QR ne correspond à aucune de vos réservations. Connectez-vous avec le compte qui a réservé.',
  'used': 'Ce QR a déjà été utilisé : l’identité de l’artisan a déjà été vérifiée.',
  'expired': 'Ce QR a expiré. Demandez à l’artisan d’en afficher un nouveau.',
  'replaced': 'Ce QR a été remplacé par un plus récent. Demandez à l’artisan de l’afficher à nouveau.',
  'revoked': 'Cet artisan n’est plus vérifié par Tratra. Ne le laissez pas intervenir et contactez le support.',
  'booking_not_active': 'Cette réservation n’est plus en cours.',
};

class IdentityApi {
  IdentityApi(this._base);
  final BaseApi _base;

  Uri _uri(String path) => Uri.parse('${_base.baseUrl}$path');

  Map<String, dynamic> _map(http.Response r) {
    final d = _base.decodeBody(r);
    return d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// GET /verify/id/<code>/ — public. 200 (actif / révoqué) et 404 (inconnu) portent la même forme.
  Future<IdentityOutcome> verifyCode(String code) async {
    try {
      final r = await _base.client.get(_uri('/verify/id/${Uri.encodeComponent(code)}/'), headers: await _base.getHeaders(withAuth: false));
      if (r.statusCode != 200 && r.statusCode != 404) _base.handleError(r);
      final d = _map(r);
      final status = '${d['status']}';
      if (d['valid'] == true && d['holder'] is Map) {
        return IdentityOutcome(
          ok: true,
          tone: 'ok',
          title: 'Professionnel vérifié par Tratra',
          message: '${d['message']}',
          holder: (d['holder'] as Map).cast<String, dynamic>(),
          tratraId: '${d['tratra_id']}',
        );
      }
      return IdentityOutcome(
        ok: false,
        tone: 'danger',
        title: status == 'revoked' ? 'Badge révoqué' : 'Badge inconnu',
        message: '${d['message']}',
        tratraId: status == 'revoked' ? '${d['tratra_id']}' : null,
      );
    } catch (e) {
      return IdentityOutcome(
        ok: false,
        tone: 'warn',
        title: 'Vérification impossible',
        message: '${friendlyError(e)} Ne faites pas confiance à un badge non vérifié.',
      );
    }
  }

  /// POST /verify/pass/ — le client de la réservation scanne le QR de mission (usage unique).
  Future<IdentityOutcome> consumePass(String token) async {
    try {
      final r = await _base.client.post(_uri('/verify/pass/'), headers: await _base.headers, body: json.encode({'token': token}));
      final d = _map(r);
      if (r.statusCode == 200 && d['valid'] == true) {
        final when = DateTime.tryParse('${d['verified_at']}')?.toLocal();
        return IdentityOutcome(
          ok: true,
          tone: 'ok',
          title: 'Identité confirmée',
          message: '${d['message']}',
          holder: (d['holder'] as Map?)?.cast<String, dynamic>(),
          tratraId: '${d['tratra_id']}',
          extra: 'Réservation #${d['booking_id']}${'${d['service'] ?? ''}'.isEmpty ? '' : ' · ${d['service']}'}'
              '${when == null ? '' : ' — vérifié à ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'}',
        );
      }
      if (r.statusCode == 401) _base.handleError(r);
      final code = '${d['code'] ?? 'error'}';
      return IdentityOutcome(
        ok: false,
        tone: code == 'revoked' ? 'danger' : 'warn',
        title: 'Vérification refusée',
        message: _passRefusals[code] ?? '${d['detail'] ?? 'La vérification a échoué. Réessayez dans un instant.'}',
      );
    } catch (e) {
      return IdentityOutcome(ok: false, tone: 'warn', title: 'Vérification impossible', message: friendlyError(e));
    }
  }

  /// POST /bookings/{id}/identity-pass/ — l'artisan obtient son QR de mission (15 min, usage unique).
  Future<Map<String, dynamic>> issuePass(int bookingId) async {
    final r = await _base.client.post(_uri('/bookings/$bookingId/identity-pass/'), headers: await _base.headers, body: '{}');
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final d = _map(r);
      throw Exception('${d['detail'] ?? 'Le QR de mission n’a pas pu être généré.'}');
    }
    return _map(r);
  }

  /// GET /bookings/{id}/identity/ — la vérification a-t-elle eu lieu ?
  Future<Map<String, dynamic>> bookingIdentity(int bookingId) async {
    final r = await _base.client.get(_uri('/bookings/$bookingId/identity/'), headers: await _base.headers);
    if (r.statusCode != 200) _base.handleError(r);
    return _map(r);
  }

  /// GET /me/tratra-id/ — badge numérique et QR permanent de l'artisan.
  Future<Map<String, dynamic>> myId() async {
    final r = await _base.client.get(_uri('/me/tratra-id/'), headers: await _base.headers);
    if (r.statusCode != 200) _base.handleError(r);
    return _map(r);
  }

  /// GET /me/tratra-id/badge.pdf — badge imprimable, enregistré dans le dossier temporaire.
  Future<File> badgePdf(String code) async {
    final r = await _base.client.get(_uri('/me/tratra-id/badge.pdf'), headers: await _base.headers);
    if (r.statusCode != 200) {
      final d = _map(r);
      throw Exception('${d['detail'] ?? 'Le badge imprimable n’est pas disponible pour le moment.'}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/tratra-id-$code.pdf');
    return file.writeAsBytes(r.bodyBytes, flush: true);
  }
}

/// Octets d'une image `data:image/png;base64,...` (QR renvoyés par l'API).
Uint8List dataUrlBytes(String dataUrl) => base64Decode(dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl);

/// Cible d'un QR Tratra : badge permanent (code) ou QR de mission (jeton).
sealed class ScanTarget {
  const ScanTarget();
}

class IdTarget extends ScanTarget {
  const IdTarget(this.code);
  final String code;
}

class PassTarget extends ScanTarget {
  const PassTarget(this.token);
  final String token;
}

/// QR d'un équipement Tratra Business (réservé aux membres de son organisation).
class EquipTarget extends ScanTarget {
  const EquipTarget(this.code);
  final String code;
}

final _codeRe = RegExp(r'^TR-[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$');
final _equipRe = RegExp(r'^EQ-[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$');

/// Interprète le contenu d'un QR : URL Tratra (`/verify/<code>` ou `/verify/pass/<jeton>`) ou code nu.
/// Seul le code ou le jeton extrait est envoyé à NOTRE API : l'URL n'est jamais ouverte.
ScanTarget? parseQr(String raw) {
  final v = raw.trim();
  if (v.isEmpty || v.length > 400) return null;
  final upper = v.toUpperCase();
  if (_codeRe.hasMatch(upper)) return IdTarget(upper);
  if (_equipRe.hasMatch(upper)) return EquipTarget(upper);
  final seg = Uri.tryParse(v)?.pathSegments ?? const <String>[];
  final e = seg.indexOf('equipment');
  if (e >= 0 && seg.length > e + 1 && _equipRe.hasMatch(seg[e + 1].toUpperCase())) return EquipTarget(seg[e + 1].toUpperCase());
  final i = seg.indexOf('verify');
  if (i < 0) return null;
  if (seg.length > i + 2 && seg[i + 1] == 'pass' && seg[i + 2].isNotEmpty) return PassTarget(seg[i + 2]);
  if (seg.length > i + 1) {
    final code = seg[i + 1].toUpperCase();
    if (_codeRe.hasMatch(code)) return IdTarget(code);
  }
  return null;
}
