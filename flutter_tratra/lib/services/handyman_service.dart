// lib/services/handyman_service.dart
//
// Service du parcours ARTISAN : présence, gains/versements, compte de
// versement, KYC (documents), abonnement Pro. Branché sur l'API découplée.
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';

class HandymanService extends BaseApi {
  HandymanService(BaseApi api, {super.client});

  // ----- Présence (dispo temps réel) -----
  /// POST /handymen/presence/ { online } -> { online }
  /// 403 si le profil n'est pas vérifié (KYC).
  Future<bool> setPresence(bool online) async {
    final r = await client.post(
      Uri.parse('$baseUrl${AppConstants.presenceEndpoint}'),
      headers: await headers,
      body: json.encode({'online': online}),
    );
    if (r.statusCode != 200) handleError(r);
    final data = decodeBody(r);
    return data is Map && data['online'] == true;
  }

  // ----- Gains / versements -----
  /// GET /payouts/available/ -> montant disponible au retrait.
  Future<num> availableEarnings() async {
    final r = await client.get(
      Uri.parse('$baseUrl${AppConstants.payoutsAvailableEndpoint}'),
      headers: await headers,
    );
    if (r.statusCode != 200) handleError(r);
    final data = decodeBody(r);
    final v = (data is Map) ? (data['available'] ?? data['amount']) : null;
    if (v is num) return v;
    return num.tryParse('${v ?? 0}') ?? 0;
  }

  /// POST /payouts/ { amount } -> demande de versement.
  Future<Map<String, dynamic>> requestPayout(num amount) async {
    final r = await client.post(
      Uri.parse('$baseUrl${AppConstants.payoutsEndpoint}/'),
      headers: await headers,
      body: json.encode({'amount': amount}),
    );
    if (r.statusCode != 201 && r.statusCode != 200) handleError(r);
    return Map<String, dynamic>.from(decodeBody(r) as Map);
  }

  // ----- Compte de versement (Mobile Money / banque) -----
  /// GET /payout-account/ -> {} si non configuré.
  Future<Map<String, dynamic>?> getPayoutAccount() async {
    final r = await client.get(
      Uri.parse('$baseUrl${AppConstants.payoutAccountEndpoint}'),
      headers: await headers,
    );
    if (r.statusCode != 200) handleError(r);
    final data = decodeBody(r);
    if (data is Map && data.isNotEmpty) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  /// POST /payout-account/ { provider, account_ref } -> upsert.
  Future<Map<String, dynamic>> upsertPayoutAccount({
    required String provider,
    required String accountRef,
  }) async {
    final r = await client.post(
      Uri.parse('$baseUrl${AppConstants.payoutAccountEndpoint}'),
      headers: await headers,
      body: json.encode({'provider': provider, 'account_ref': accountRef}),
    );
    if (r.statusCode != 200 && r.statusCode != 201) handleError(r);
    return Map<String, dynamic>.from(decodeBody(r) as Map);
  }

  // ----- KYC (documents) -----
  /// GET /handyman-docs/ -> documents de l'artisan courant.
  Future<List<Map<String, dynamic>>> listDocuments() async {
    final r = await client.get(
      Uri.parse('$baseUrl${AppConstants.handymanDocsEndpoint}/'),
      headers: await headers,
    );
    if (r.statusCode != 200) handleError(r);
    return extractResults(decodeBody(r))
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// POST multipart /handyman-docs/ (document_type, file, description?).
  Future<Map<String, dynamic>> uploadDocument({
    required String documentType,
    required String filePath,
    String? description,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl${AppConstants.handymanDocsEndpoint}/'),
    );
    // En multipart, on laisse http poser le Content-Type (avec boundary).
    final h = await headers;
    h.remove('Content-Type');
    req.headers.addAll(h);
    req.fields['document_type'] = documentType;
    if (description != null && description.isNotEmpty) {
      req.fields['description'] = description;
    }
    req.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await client.send(req);
    final r = await http.Response.fromStream(streamed);
    if (r.statusCode != 201 && r.statusCode != 200) handleError(r);
    return Map<String, dynamic>.from(decodeBody(r) as Map);
  }

  // ----- Abonnements (Pro Artisan) -----
  /// GET /subscription-plans/?audience=handyman
  Future<List<Map<String, dynamic>>> plans({String? audience}) async {
    final q = (audience != null) ? '?audience=$audience' : '';
    final r = await client.get(
      Uri.parse('$baseUrl${AppConstants.subscriptionPlansEndpoint}/$q'),
      headers: await headers,
    );
    if (r.statusCode != 200) handleError(r);
    return extractResults(decodeBody(r))
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// GET /subscriptions/current/ -> { active:false } ou l'abonnement actif.
  Future<Map<String, dynamic>> currentSubscription() async {
    final r = await client.get(
      Uri.parse('$baseUrl${AppConstants.subscriptionsEndpoint}/current/'),
      headers: await headers,
    );
    if (r.statusCode != 200) handleError(r);
    return Map<String, dynamic>.from(decodeBody(r) as Map);
  }

  /// POST /subscriptions/ { plan } -> souscrit (annule l'éventuel précédent).
  Future<Map<String, dynamic>> subscribe(int planId) async {
    final r = await client.post(
      Uri.parse('$baseUrl${AppConstants.subscriptionsEndpoint}/'),
      headers: await headers,
      body: json.encode({'plan': planId}),
    );
    if (r.statusCode != 201 && r.statusCode != 200) handleError(r);
    return Map<String, dynamic>.from(decodeBody(r) as Map);
  }
}
