// lib/services/match_service.dart
import 'dart:convert';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/artisan.dart';

class MatchService extends BaseApi {
  MatchService(BaseApi api, {super.client});

  Future<List<Artisan>> find({
    required String serviceType,
    required String location,
    DateTime? preferredTime,
    Map<String, dynamic>? preferences,
  }) async {
    final body = {
      'service_type': serviceType,
      'location': location,
      if (preferredTime != null)
        'preferred_time': preferredTime.toIso8601String(),
      ...?preferences,
    };

    final r = await client.post(
      Uri.parse('$baseUrl/match/'),
      headers: await headers,
      body: json.encode(body),
    );
    if (r.statusCode != 200) handleError(r);
    final list = decodeBody(r) as List;
    return list.map((e) => Artisan.fromJson(e)).toList();
  }
}
