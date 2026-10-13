// lib/biometric/biometric_api.dart
//
// Client de la vérification faciale (API Django /kyc/biometric/…). Aucun secret ici : le jeton de session est court, renvoyé UNE fois par le serveur
// et transmis dans l'en-tête X-Biometric-Token (jamais dans l'URL). Le serveur est l'autorité : aucune décision, aucun score côté application.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:flutter_tratra/core/base_api.dart';

class BiometricApiException implements Exception {
  BiometricApiException(this.status, this.code, this.detail, [this.extra = const {}]);
  final int status;
  final String code;
  final String detail;
  final Map<String, dynamic> extra;

  /// La session n'est plus utilisable (expirée, jeton épuisé ou invalide) : il faut en relancer une.
  bool get sessionLost => code == 'expired' || code == 'token_exhausted' || code == 'invalid_token';

  @override
  String toString() => detail;
}

class BiometricChallenge {
  BiometricChallenge(this.index, this.kind, this.instruction);
  final int index;
  final String kind;
  final String instruction;
}

class BiometricSessionInfo {
  BiometricSessionInfo({required this.id, required this.token, required this.challenges, required this.captured, required this.expiresAt});
  final int id;
  final String token;
  final List<BiometricChallenge> challenges;
  final Set<int> captured;
  final DateTime? expiresAt;

  int? get nextIndex {
    for (final c in challenges) {
      if (!captured.contains(c.index)) return c.index;
    }
    return null;
  }

  factory BiometricSessionInfo.fromJson(Map<String, dynamic> j) => BiometricSessionInfo(
        id: (j['session_id'] as num).toInt(),
        token: '${j['token'] ?? ''}',
        challenges: ((j['challenges'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => BiometricChallenge((e['index'] as num).toInt(), '${e['kind']}', '${e['instruction']}'))
            .toList(),
        captured: ((j['captured'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet(),
        expiresAt: DateTime.tryParse('${j['expires_at'] ?? ''}'),
      );
}

class BiometricState {
  BiometricState(this.raw);
  final Map<String, dynamic> raw;

  bool get enabled => raw['enabled'] == true;
  bool get providerConfigured => raw['provider_configured'] == true;
  String get status => '${raw['status'] ?? 'not_started'}';
  String get statusLabel => '${raw['status_label'] ?? ''}';
  bool get satisfied => raw['satisfied'] == true;
  bool get consentGranted => (raw['consent'] as Map?)?['granted'] == true;
  String get consentVersion => '${(raw['consent'] as Map?)?['version'] ?? ''}';
  String get consentText => '${(raw['consent'] as Map?)?['text'] ?? ''}';
  bool get documentPresent => (raw['document'] as Map?)?['present'] == true;
  bool get humanReviewRequested => raw['human_review_requested'] == true;
  String get decisionReason => '${raw['decision_reason'] ?? ''}';
  bool get hasActiveSession => raw['active_session'] != null;
  int get attemptsDay => ((raw['attempts'] as Map?)?['day'] as num?)?.toInt() ?? 0;
  int get maxDay => ((raw['attempts'] as Map?)?['max_day'] as num?)?.toInt() ?? 3;
}

class BiometricApi {
  BiometricApi(this._base);
  final BaseApi _base;

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body}) async {
    final uri = Uri.parse('${_base.baseUrl}$path');
    final headers = await _base.headers;
    final encoded = body == null ? null : json.encode(body);
    final http.Response r;
    switch (method) {
      case 'POST':
        r = await _base.client.post(uri, headers: headers, body: encoded);
      case 'DELETE':
        r = await _base.client.delete(uri, headers: headers);
      default:
        r = await _base.client.get(uri, headers: headers);
    }
    return _decode(r);
  }

  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> d = const {};
    try {
      final parsed = json.decode(utf8.decode(r.bodyBytes));
      if (parsed is Map) d = parsed.cast<String, dynamic>();
    } catch (_) {}
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw BiometricApiException(r.statusCode, '${d['code'] ?? 'error'}', '${d['detail'] ?? 'Une erreur est survenue. Réessayez.'}', d);
    }
    return d;
  }

  Future<BiometricState> state() async => BiometricState(await _send('GET', '/kyc/biometric/'));

  Future<void> grantConsent(String version) async => _send('POST', '/kyc/biometric/consent/', body: {'version': version});

  Future<int> withdrawConsent() async => ((await _send('DELETE', '/kyc/biometric/consent/'))['captures_deleted'] as num?)?.toInt() ?? 0;

  Future<BiometricSessionInfo> startSession() async => BiometricSessionInfo.fromJson(await _send('POST', '/kyc/biometric/sessions/', body: const {}));

  Future<void> uploadCapture(BiometricSessionInfo s, {required int index, required String kind, required Uint8List bytes}) async {
    final req = http.MultipartRequest('POST', Uri.parse('${_base.baseUrl}/kyc/biometric/sessions/${s.id}/captures/'));
    final h = await _base.headers;
    h.remove('Content-Type');
    req.headers.addAll(h);
    req.headers['X-Biometric-Token'] = s.token;
    req.fields['index'] = '$index';
    req.fields['kind'] = kind;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'capture.jpg', contentType: MediaType('image', 'jpeg')));
    _decode(await http.Response.fromStream(await _base.client.send(req)));
  }

  /// Soumet la session. Renvoie `outcome` (passed | failed | inconclusive | pending_review | provider_error) ; aucun score.
  Future<Map<String, dynamic>> submit(BiometricSessionInfo s) async {
    final uri = Uri.parse('${_base.baseUrl}/kyc/biometric/sessions/${s.id}/submit/');
    final headers = await _base.headers;
    headers['X-Biometric-Token'] = s.token;
    return _decode(await _base.client.post(uri, headers: headers, body: '{}'));
  }

  Future<void> requestHumanReview(String reason) async => _send('POST', '/kyc/biometric/human-review/', body: {'reason': reason});
}
