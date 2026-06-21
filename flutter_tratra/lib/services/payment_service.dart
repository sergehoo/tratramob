// lib/services/payment_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tratra/core/base_api.dart';

class PaymentService extends BaseApi {
  PaymentService(BaseApi api, {http.Client? client}) : super(client: client);

  Future<Map<String, dynamic>> initiate({
    required double amount,
    required String serviceName,
  }) async {
    final r = await client.post(
      Uri.parse('$baseUrl/payments/initiate/'),
      headers: await headers,
      body: json.encode({'amount': amount, 'service_name': serviceName}),
    );
    if (r.statusCode != 200) handleError(r);
    return decodeBody(r);
  }
}
