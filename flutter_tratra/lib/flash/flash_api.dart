// lib/flash/flash_api.dart
//
// API Tratra Flash (`/handy/flash/…`). Les règles (qui peut accepter, délais, attribution unique) restent côté serveur ; les écritures
// envoient une `Idempotency-Key` stable par intention : un double appui ou un renvoi après coupure ne répond jamais deux fois.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';

/// Proposition de mission telle que le professionnel la voit (avant acceptation : ni nom, ni téléphone, ni adresse du client).
class FlashOffer {
  FlashOffer(this.raw);
  final Map<String, dynamic> raw;

  int get id => int.tryParse('${raw['id']}') ?? 0;
  int get requestId => int.tryParse('${raw['request']}') ?? 0;
  String get status => '${raw['status'] ?? 'pending'}';
  bool get pending => status == 'pending';
  bool get accepted => status == 'accepted';
  bool get quoteMode => raw['mode'] == 'quote';
  String get category => '${raw['category'] ?? 'Mission'}';
  String get zone => '${raw['zone'] ?? ''}';
  String get whenLabel => '${raw['when_label'] ?? ''}';
  String get amountLabel => '${raw['amount_label'] ?? ''}';
  bool get immediate => '${raw['immediate']}' == '1' || raw['immediate'] == true;
  String get description => '${raw['description'] ?? ''}';
  double? get distanceKm => double.tryParse('${raw['distance_km'] ?? ''}');
  int get secondsLeft => int.tryParse('${raw['seconds_left'] ?? ''}') ?? 0;
  int? get bookingId => int.tryParse('${raw['booking'] ?? ''}');
  String get address => '${raw['address'] ?? ''}';
  String get clientName => '${raw['client_name'] ?? ''}';
  int? get quoteAmount => int.tryParse('${raw['quote_amount'] ?? ''}');
  Map<String, dynamic> get clientReputation => raw['client_reputation'] is Map ? (raw['client_reputation'] as Map).cast<String, dynamic>() : const {};
  List<Map<String, String>> get declineReasons => ((raw['decline_reasons'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => {'code': '${e['code']}', 'label': '${e['label']}'})
      .toList();
  List<Map<String, dynamic>> get why => ((raw['why'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

class FlashApiError implements Exception {
  FlashApiError(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => message;
}

class FlashApi {
  FlashApi(this._base);
  final BaseApi _base;

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, String? key}) async {
    final uri = Uri.parse('${_base.baseUrl}$path');
    final headers = {...await _base.headers, if (key != null) 'Idempotency-Key': key};
    final http.Response r = method == 'POST'
        ? await _base.client.post(uri, headers: headers, body: json.encode(body ?? const {}))
        : await _base.client.get(uri, headers: headers);
    final decoded = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw FlashApiError(r.statusCode, '${map['code'] ?? 'error'}', '${map['detail'] ?? 'Action impossible pour le moment.'}');
    }
    return map;
  }

  List<Map<String, dynamic>> _results(Map<String, dynamic> m) =>
      ((m['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  // ── Professionnel ──────────────────────────────────────────────────────────────────────────────────────────────────────────
  Future<FlashOffer> offer(int id) async => FlashOffer(await _send('GET', '/flash/offers/$id/'));
  Future<List<FlashOffer>> offers({bool pendingOnly = false}) async =>
      _results(await _send('GET', '/flash/offers/${pendingOnly ? '?status=pending' : ''}')).map(FlashOffer.new).toList();
  Future<FlashOffer> accept(int id) async => FlashOffer(await _send('POST', '/flash/offers/$id/accept/', key: 'flash-accept-$id'));
  Future<FlashOffer> decline(int id, {String reason = ''}) async =>
      FlashOffer(await _send('POST', '/flash/offers/$id/decline/', body: {'reason': reason}, key: 'flash-decline-$id'));
  Future<FlashOffer> quote(int id, int amount, String message) async => FlashOffer(
      await _send('POST', '/flash/offers/$id/quote/', body: {'amount': amount, 'message': message}, key: 'flash-quote-$id-$amount'));
  Future<Map<String, dynamic>> availability() => _send('GET', '/flash/availability/');
  /// Bouton Disponible / Indisponible (point d'accès historique), puis état détaillé (éligibilité, silences, propositions en attente).
  Future<Map<String, dynamic>> setAvailability(bool online) async {
    await _send('POST', '/handymen/presence/', body: {'online': online});
    return availability();
  }

  // ── Client ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> requests() async => _results(await _send('GET', '/flash/requests/'));
  Future<Map<String, dynamic>> request(int id) => _send('GET', '/flash/requests/$id/');
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> body, String key) => _send('POST', '/flash/requests/', body: body, key: key);
  Future<Map<String, dynamic>> cancelRequest(int id) => _send('POST', '/flash/requests/$id/cancel/', key: 'flash-cancel-$id');
  Future<Map<String, dynamic>> relaunch(int id, String key, {int? amount}) =>
      _send('POST', '/flash/requests/$id/relaunch/', body: {if (amount != null) 'amount': amount}, key: key);
  Future<Map<String, dynamic>> chooseQuote(int requestId, int offerId) =>
      _send('POST', '/flash/requests/$requestId/quotes/$offerId/accept/', key: 'flash-choose-$requestId-$offerId');
}
