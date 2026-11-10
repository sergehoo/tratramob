// lib/flash/flash_api.dart
//
// API Tratra Flash (`/handy/flash/…`). Les règles (qui peut accepter, délais, attribution unique) restent côté serveur ; les écritures
// envoient une `Idempotency-Key` stable par intention : un double appui ou un renvoi après coupure ne répond jamais deux fois.
import 'dart:async';
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
  /// Proposition ciblée : le client a CHOISI ce professionnel (« Choisir mon professionnel »).
  bool get direct => '${raw['direct']}' == '1';
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
  /// Contre-offre du client en attente de réponse (mode Propositions) : montant, libellé, secondes restantes.
  Map<String, dynamic>? get counter => raw['counter'] is Map ? (raw['counter'] as Map).cast<String, dynamic>() : null;
  bool get countered => status == 'countered' && counter != null;
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
  FlashApi(this._base, {this.timeout = const Duration(seconds: 15)});
  final BaseApi _base;
  /// Délai maximal d'une requête : jamais de chargement infini (réseau coupé, Wi-Fi captif). Les écritures portent une
  /// `Idempotency-Key` : un renvoi après un délai dépassé ne répond jamais deux fois.
  final Duration timeout;

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, String? key}) async {
    final uri = Uri.parse('${_base.baseUrl}$path');
    final headers = {...await _base.headers, if (key != null) 'Idempotency-Key': key};
    final http.Response r = await switch (method) {
      'POST' => _base.client.post(uri, headers: headers, body: json.encode(body ?? const {})),
      'DELETE' => _base.client.delete(uri, headers: headers),
      _ => _base.client.get(uri, headers: headers),
    }.timeout(timeout);
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
  /// Contre-offre du client : l'accepter attribue la mission à ce montant ; la refuser garde la proposition initiale.
  Future<FlashOffer> acceptCounter(int id) async =>
      FlashOffer(await _send('POST', '/flash/offers/$id/counter/accept/', key: 'flash-counter-accept-$id'));
  Future<FlashOffer> declineCounter(int id) async =>
      FlashOffer(await _send('POST', '/flash/offers/$id/counter/decline/', key: 'flash-counter-decline-$id'));
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
  /// Accord du client pour élargir la recherche au-delà du seuil (30 km par défaut).
  Future<Map<String, dynamic>> extend(int id) => _send('POST', '/flash/requests/$id/extend/', key: 'flash-extend-$id');
  /// Contre-offre sur une proposition de prix (montant plus bas) ; ni sélection, ni confirmation.
  Future<Map<String, dynamic>> counter(int requestId, int offerId, int amount) => _send('POST',
      '/flash/requests/$requestId/quotes/$offerId/counter/', body: {'amount': amount}, key: 'flash-counter-$requestId-$offerId-$amount');
  Future<Map<String, dynamic>> chooseQuote(int requestId, int offerId) =>
      _send('POST', '/flash/requests/$requestId/quotes/$offerId/accept/', key: 'flash-choose-$requestId-$offerId');

  // ── Hybrid Matching ────────────────────────────────────────────────────────────────────────────────────────────────────────
  static String _query(Map<String, Object?> params) {
    final kept = {for (final e in params.entries) if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}'};
    return kept.isEmpty ? '' : '?${Uri(queryParameters: kept).query}';
  }

  /// Mode conseillé (immédiat → Smart Dispatch, planifié → choix, devis → Smart Dispatch, favori disponible → choix) et dernier choix.
  Future<Map<String, dynamic>> suggest(int categoryId, {DateTime? when, bool quote = false, double? lat, double? lng, String? commune}) =>
      _send('GET', '/flash/suggest/${_query({'category': categoryId, 'when': when?.toIso8601String(), 'mode': quote ? 'quote' : null, 'lat': lat, 'lng': lng, 'commune': commune})}');

  /// Professionnels disponibles à CHOISIR (profils, avis, badges ; favoris d'abord).
  Future<List<Map<String, dynamic>>> pros(int categoryId,
          {DateTime? when, double? lat, double? lng, String? commune, String sort = 'recommended', double? minRating, String? badge, bool favorites = false}) async =>
      _results(await _send('GET', '/flash/pros/${_query({'category': categoryId, 'when': when?.toIso8601String(), 'lat': lat, 'lng': lng, 'commune': commune, 'sort': sort, 'min_rating': minRating, 'badge': badge, 'favorites': favorites ? '1' : null})}'));

  /// Bascule confirmée entre « Trouvez-moi un professionnel » (auto) et « Choisir mon professionnel » (direct), sur la même demande.
  Future<Map<String, dynamic>> switchMode(int requestId, String to, {int? target, int? version}) => _send('POST', '/flash/requests/$requestId/switch/',
      body: {'to': to, 'confirm': true, if (target != null) 'target': target, if (version != null) 'expected_version': version},
      key: 'flash-switch-$requestId-$to-${target ?? 0}-${version ?? 0}');

  Future<List<Map<String, dynamic>>> favorites() async => _results(await _send('GET', '/me/favorites/'));
  Future<List<Map<String, dynamic>>> addFavorite(int handymanId) async =>
      _results(await _send('POST', '/me/favorites/', body: {'handyman': handymanId}, key: 'favorite-add-$handymanId'));
  Future<List<Map<String, dynamic>>> removeFavorite(int handymanId) async => _results(await _send('DELETE', '/me/favorites/$handymanId/'));
}
