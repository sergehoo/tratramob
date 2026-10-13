import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/models/booking.dart';

void main() {
  BookingCreateRequest build({double? lat, double? lng, String? commune, int? fee}) => BookingCreateRequest.fromDateAndTime(
        serviceId: '7', handymanId: '3', date: DateTime(2030, 1, 2), hour: 10, minute: 0, address: 'Rue 1', city: 'Abidjan', postalCode: '00225',
        latitude: lat, longitude: lng, commune: commune, expectedTransportFee: fee);

  test('une adresse enregistrée envoie son point, son quartier et le déplacement vu par le client', () {
    final j = build(lat: 5.36, lng: -4.0083, commune: ' Cocody ', fee: 1600).toJson();
    expect(j['lat'], 5.36);
    expect(j['lng'], -4.0083);
    expect(j['commune'], 'Cocody');
    expect(j['expected_transport_fee'], 1600);
  });

  test('sans point, ni montant de déplacement ni quartier superflu : rien d\'inventé', () {
    final j = build(commune: '  ', fee: 1600).toJson();
    expect(j.containsKey('lat'), isFalse);
    expect(j.containsKey('expected_transport_fee'), isFalse);   // pas de lieu : le serveur n'a rien à recalculer
    expect(j.containsKey('commune'), isFalse);
  });
}
