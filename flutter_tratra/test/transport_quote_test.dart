import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/screens/booking_flow/transport_estimate.dart';

void main() {
  test('un 409 transport_changed renvoie le devis recalculé par le serveur', () {
    final e = ApiException(409, 'x', body: json.encode({'code': 'transport_changed', 'quote': {'amount': 4000, 'applicable': true, 'reason': 'rate', 'distance_km': 8.0, 'multiplier': 2, 'band': {'name': 'Matin', 'rate_per_km': 250.0}}}));
    final q = changedTransportQuote(e)!;
    expect(q.amount, 4000);
    expect(q.description, '8.0 km (aller-retour) · tranche « Matin » 250.0 FCFA/km');
    expect(changedTransportQuote(ApiException(409, 'x', body: json.encode({'code': 'duplicate_booking'}))), isNull);
    expect(changedTransportQuote(ApiException(400, 'x', body: '{}')), isNull);
  });

  test('descriptions honnêtes : seuil, forfait et déplacement inutile', () {
    expect(TransportQuoteData({'reason': 'within_threshold', 'threshold_km': 1.0, 'applicable': true}).description, contains('offert'));
    expect(TransportQuoteData({'fallback': true, 'fallback_reason': 'distance_unavailable', 'applicable': true}).description, contains('Distance indisponible'));
    expect(TransportQuoteData({'applicable': false, 'reason': 'no_travel'}).description, contains('ne nécessite pas'));
  });
}
