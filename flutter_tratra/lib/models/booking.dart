// ===============================
// lib/models/booking.dart ✅ (FIX toJson + getters supprimés)
// ===============================
import 'service.dart';

class Booking {
  final String id;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  final DateTime? bookingDate;
  final String? bookingTime;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? notes;

  final String clientId;
  final String handymanId;
  final String serviceId;

  final Service? service;
  final double? amount;

  Booking({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.clientId,
    required this.handymanId,
    required this.serviceId,
    this.bookingDate,
    this.bookingTime,
    this.address,
    this.city,
    this.postalCode,
    this.notes,
    this.service,
    this.amount,
  });

  /// Titre du service associé (pratique pour l'affichage des listes).
  String? get serviceTitle => service?.title;

  factory Booking.fromJson(Map<String, dynamic> json) {
    DateTime? _dt(v) => v == null ? null : DateTime.tryParse(v.toString());

    double? _toD(v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    // BookingSerializer renvoie l'ID dans `service` et le détail dans
    // `service_detail`. Accepte aussi l'ancien format imbriqué de l'app.
    final serviceData = json['service_detail'] ?? json['service'];
    Service? svc;
    if (serviceData is Map) {
      svc = Service.fromJson(Map<String, dynamic>.from(serviceData));
    }

    return Booking(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt: _dt(json['created_at']) ?? DateTime.now(),
      updatedAt: _dt(json['updated_at']) ?? DateTime.now(),
      clientId: (json['client'] ?? '').toString(),
      handymanId: (json['handyman'] ?? '').toString(),
      serviceId: (json['service'] is Map
              ? (json['service']['id'] ?? '')
              : json['service'] ?? '')
          .toString(),
      bookingDate: _dt(json['booking_date']),
      // `booking_time` n'existe plus dans l'API actuelle : l'heure fait partie
      // de booking_date. Garde la lecture de l'ancien format sans le réémettre.
      bookingTime: (json['booking_time'] ?? '').toString().isEmpty
          ? null
          : json['booking_time'].toString(),
      address: (json['address'] ?? '').toString().isEmpty
          ? null
          : (json['address'] as String),
      city: (json['city'] ?? '').toString().isEmpty
          ? null
          : (json['city'] as String),
      postalCode: (json['postal_code'] ?? '').toString().isEmpty
          ? null
          : (json['postal_code'] as String),
      notes: (json['description'] ?? json['notes'] ?? '').toString().isEmpty
          ? null
          : (json['description'] ?? json['notes']).toString(),
      service: svc,
      amount: _toD(json['total_price'] ?? json['amount'] ?? json['proposed_price']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'client': clientId,
      'handyman': handymanId,
      'service': serviceId,
      if (bookingDate != null) 'booking_date': bookingDate!.toIso8601String(),
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (postalCode != null) 'postal_code': postalCode,
      if (notes != null) 'description': notes,
    };
  }
}

class BookingCreateRequest {
  final String serviceId;
  final String handymanId;
  final DateTime scheduledAt;
  final String address;
  final String? notes;
  final String city;
  final String postalCode;

  BookingCreateRequest._({
    required this.serviceId,
    required this.handymanId,
    required this.scheduledAt,
    required this.address,
    required this.city,
    required this.postalCode,
    this.notes,
  });

  /// Transforme les sélecteurs date/heure de l'app en DateTime UTC : le
  /// backend Django stocke une seule valeur `booking_date` (Africa/Abidjan,
  /// UTC+0), pas un champ `booking_time` séparé.
  factory BookingCreateRequest.fromDateAndTime({
    required String serviceId,
    required String handymanId,
    required DateTime date,
    required int hour,
    required int minute,
    required String address,
    required String city,
    required String postalCode,
    String? notes,
  }) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('Heure de réservation invalide.');
    }
    final normalizedNotes = notes?.trim();

    String requiredValue(String value, String field) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        throw ArgumentError('$field est requis pour créer une réservation.');
      }
      return trimmed;
    }

    return BookingCreateRequest._(
      serviceId: requiredValue(serviceId, 'Le service'),
      handymanId: requiredValue(handymanId, "L'artisan"),
      scheduledAt: DateTime.utc(date.year, date.month, date.day, hour, minute),
      address: requiredValue(address, "L'adresse"),
      city: requiredValue(city, 'La ville'),
      postalCode: requiredValue(postalCode, 'Le code postal'),
      notes: normalizedNotes == null || normalizedNotes.isEmpty
          ? null
          : normalizedNotes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'service': serviceId,
      'handyman': handymanId,
      'booking_date': scheduledAt.toIso8601String(),
      'address': address,
      'city': city,
      'postal_code': postalCode,
      'type': 'scheduled',
      if (notes != null && notes!.isNotEmpty) "description": notes,
    };
  }
}
