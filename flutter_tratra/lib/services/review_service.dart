// lib/services/review_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/review.dart';

class ReviewService extends BaseApi {
  ReviewService(BaseApi api, {super.client});

  Future<Review> create(Review review) async {
    final r = await client.post(
      Uri.parse('$baseUrl/reviews/'),
      headers: await headers,
      body: json.encode(review.toJson()),
    );
    if (r.statusCode != 201) handleError(r);
    return Review.fromJson(decodeBody(r));
  }

  Future<List<Review>> forArtisan(String artisanId) async {
    final uri = Uri.parse('$baseUrl/reviews/').replace(queryParameters: {
      'artisan': artisanId,
    });
    final r = await client.get(uri, headers: await headers);
    if (r.statusCode != 200) handleError(r);
    final decoded = decodeBody(r);
    final list = extractResults(decoded);
    return list.map((e) => Review.fromJson(e)).toList();
  }
}
