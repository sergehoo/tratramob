// lib/services/booking_service.dart
import 'dart:convert';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/booking.dart';

class BookingService extends BaseApi {
  BookingService(BaseApi api, {super.client});

  Future<Booking> create(Booking booking) async {
    final r = await client.post(
      Uri.parse('$baseUrl/bookings/'),
      headers: await headers,
      body: json.encode(booking.toJson()),
    );
    if (r.statusCode != 201) handleError(r);
    return Booking.fromJson(decodeBody(r));
  }

  /// `/bookings/` renvoie les réservations où le compte est client OU artisan :
  /// un compte unique filtre donc par rôle (`clientId` : mes réservations,
  /// `handymanId` : mes missions).
  Future<List<Booking>> list({String? clientId, String? handymanId}) async {
    final query = <String, String>{
      if (clientId != null && clientId.isNotEmpty) 'client': clientId,
      if (handymanId != null && handymanId.isNotEmpty) 'handyman': handymanId,
    };
    final uri = Uri.parse('$baseUrl/bookings/').replace(queryParameters: query.isEmpty ? null : query);
    final r = await client.get(uri, headers: await headers);
    if (r.statusCode != 200) handleError(r);
    final decoded = decodeBody(r);
    final list = extractResults(decoded);
    return list.map((e) => Booking.fromJson(e)).toList();
  }

  Future<Booking> detail(String id) async {
    final r = await client.get(Uri.parse('$baseUrl/bookings/$id/'),
        headers: await headers);
    if (r.statusCode != 200) handleError(r);
    return Booking.fromJson(decodeBody(r));
  }

  /// Change le statut via la MACHINE À ÉTATS backend (action `transition`),
  /// et non un PATCH direct (le champ `status` est en lecture seule côté API).
  /// Statuts valides : confirmed | in_progress | completed | cancelled.
  Future<Booking> transition(String id, String status) async {
    final r = await client.post(
      Uri.parse('$baseUrl${AppConstants.bookingTransition(id)}'),
      headers: await headers,
      body: json.encode({'status': status}),
    );
    if (r.statusCode != 200) handleError(r);
    return Booking.fromJson(decodeBody(r));
  }

  /// Conservé pour compatibilité : délègue désormais à la transition d'état.
  Future<Booking> updateStatus(String id, String status) => transition(id, status);

  /// Annulation = transition d'état "cancelled" (applique la politique de
  /// pénalité côté backend ; un DELETE ne déclencherait pas l'escrow/refund).
  Future<Booking> cancel(String id) => transition(id, 'cancelled');
}
