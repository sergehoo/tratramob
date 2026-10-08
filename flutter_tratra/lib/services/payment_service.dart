// lib/services/payment_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';

class PaymentService extends BaseApi {
  PaymentService(BaseApi api, {super.client});

  /// Initie un paiement (escrow) pour une réservation.
  /// Contrat backend: { booking_id, method, minutes, category_id?, coupon_code? }
  /// Réponse: { payment_id, provider, provider_ref, status }
  Future<Map<String, dynamic>> initiate({
    required int bookingId,
    required String method,      // 'om' | 'mtn' | 'card' | 'cash' | ...
    int minutes = 60,
    int? categoryId,
    String? couponCode,
  }) async {
    final body = <String, dynamic>{
      'booking_id': bookingId,
      'method': method,
      'minutes': minutes,
    };
    if (categoryId != null) body['category_id'] = categoryId;
    if (couponCode != null && couponCode.isNotEmpty) body['coupon_code'] = couponCode;

    final r = await client.post(
      Uri.parse('$baseUrl/payments/initiate/'),
      headers: await headers,
      body: json.encode(body),
    );
    if (r.statusCode != 201 && r.statusCode != 200) handleError(r);
    return decodeBody(r);
  }

  /// Prévisualise une réduction coupon: { code, amount } -> { valid, discount, net }
  Future<Map<String, dynamic>> validateCoupon(String code, num amount) async {
    final r = await client.post(
      Uri.parse('$baseUrl/coupons/validate/'),
      headers: await headers,
      body: json.encode({'code': code, 'amount': amount}),
    );
    if (r.statusCode != 200) handleError(r);
    return decodeBody(r);
  }
}
