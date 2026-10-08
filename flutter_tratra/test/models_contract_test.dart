import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/models/user.dart';

void main() {
  group('Booking API contract', () {
    test('encodes the selected date and time in booking_date only', () {
      final request = BookingCreateRequest.fromDateAndTime(
        serviceId: '17',
        handymanId: '42',
        date: DateTime(2026, 10, 4),
        hour: 9,
        minute: 30,
        address: 'Riviera 3',
        city: 'Abidjan',
        postalCode: '00225',
        notes: '  Interphone en panne  ',
      );

      final body = request.toJson();

      expect(request.scheduledAt, DateTime.utc(2026, 10, 4, 9, 30));
      expect(body['booking_date'], '2026-10-04T09:30:00.000Z');
      expect(body.containsKey('booking_time'), isFalse);
      expect(body['type'], 'scheduled');
      expect(body['description'], 'Interphone en panne');
    });

    test('rejects incomplete booking data before making a network request', () {
      expect(
        () => BookingCreateRequest.fromDateAndTime(
          serviceId: '17',
          handymanId: '',
          date: DateTime(2026, 10, 4),
          hour: 9,
          minute: 30,
          address: 'Riviera 3',
          city: 'Abidjan',
          postalCode: '00225',
        ),
        throwsArgumentError,
      );
    });

    test('reads the nested service returned by BookingSerializer', () {
      final booking = Booking.fromJson({
        'id': 8,
        'status': 'pending',
        'created_at': '2026-10-01T10:00:00Z',
        'updated_at': '2026-10-01T10:00:00Z',
        'booking_date': '2026-10-04T09:30:00Z',
        'client': 1,
        'handyman': 42,
        'service': 17,
        'service_detail': {
          'id': 17,
          'title': 'Plomberie',
          'description': 'Réparer une fuite',
          'price_type': 'fixed',
          'price': '6500',
          'handyman': 42,
          'category': 3,
          'is_active': true,
        },
        'total_price': '6500',
      });

      expect(booking.serviceTitle, 'Plomberie');
      expect(booking.serviceId, '17');
      expect(booking.amount, 6500);
    });
  });

  group('User API contract', () {
    test('maps Django profile fields and emits safe update fields', () {
      final user = User.fromJson({
        'id': 3,
        'email': 'client@example.test',
        'username': 'client',
        'first_name': 'Awa',
        'last_name': 'Kouassi',
        'phone': '+2250700000000',
        'profile_picture': 'https://cdn.example.test/avatar.jpg',
        'user_type': 'client',
      });

      expect(user.phoneNumber, '+2250700000000');
      expect(user.profileImage, 'https://cdn.example.test/avatar.jpg');
      expect(user.toProfileUpdateJson(), {
        'email': 'client@example.test',
        'username': 'client',
        'first_name': 'Awa',
        'last_name': 'Kouassi',
        'phone': '+2250700000000',
      });
      expect(user.toStorageJson()['id'], '3');
    });
  });
}
