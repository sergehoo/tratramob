// lib/services/booking_api.dart
import 'dart:async';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/booking.dart';

class BookingApi {
  final BaseApi api;
  final Map<String, List<Booking>> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  BookingApi(this.api);

  /// POST /bookings/
  ///
  /// `idempotencyKey` : un renvoi après coupure ou plantage retrouve la même réservation (aucun doublon).
  /// Les erreurs du serveur gardent leur type ([ApiException]) pour que l'écran distingue un doublon d'un échec.
  Future<Booking> create(BookingCreateRequest req, {String? idempotencyKey}) async {
    try {
      final uri = Uri.parse('${api.baseUrl}${AppConstants.bookingsEndpoint}/');
      final headers = {...await api.getHeaders(withAuth: true), if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey};
      final body = api.encodeBody(req.toJson());

      final response = await api.client.post(uri, headers: headers, body: body);

      if (response.statusCode != 201 && response.statusCode != 200) {
        await api.handleError(response);
      }

      final decoded = api.decodeBody(response);
      final booking = Booking.fromJson(Map<String, dynamic>.from(decoded));

      // Invalider le cache après création
      _cache.clear();

      return booking;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('Échec de la création de réservation: ${e.toString()}');
    }
  }

  /// GET /bookings/?ordering=-created_at avec cache intelligent
  Future<List<Booking>> listMine(
      {int pageSize = 50, bool forceRefresh = false}) async {
    const cacheKey = 'my_bookings';

    // Vérifier le cache
    if (!forceRefresh &&
        _cache.containsKey(cacheKey) &&
        _cacheTimestamps.containsKey(cacheKey) &&
        DateTime.now().difference(_cacheTimestamps[cacheKey]!) <
            _cacheDuration) {
      return _cache[cacheKey]!;
    }

    try {
      final uri = Uri.parse('${api.baseUrl}${AppConstants.bookingsEndpoint}/')
          .replace(queryParameters: {
        'page_size': pageSize.toString(),
        'ordering': '-created_at',
      });

      final response = await api.client
          .get(uri, headers: await api.getHeaders(withAuth: true));

      if (response.statusCode != 200) await api.handleError(response);

      final decoded = api.decodeBody(response);
      final results = api.extractResults(decoded);
      final bookings = results
          .map<Booking>((e) => Booking.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Mettre en cache
      _cache[cacheKey] = bookings;
      _cacheTimestamps[cacheKey] = DateTime.now();

      return bookings;
    } catch (e) {
      // Retourner le cache même s'il est expiré en cas d'erreur
      if (_cache.containsKey(cacheKey)) {
        return _cache[cacheKey]!;
      }
      rethrow;
    }
  }

  // Autres méthodes restent similaires mais avec meilleure gestion d'erreurs...

  /// Méthode pour vider le cache
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}
