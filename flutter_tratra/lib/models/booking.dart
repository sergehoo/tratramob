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

    Service? svc;
    if (json['service'] is Map<String, dynamic>) {
      svc = Service.fromJson(json['service'] as Map<String, dynamic>);
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
      bookingTime: (json['booking_time'] ?? '').toString().isEmpty
          ? null
          : (json['booking_time'] as String),
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
      amount: _toD(json['amount']),
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
      if (bookingTime != null) 'booking_time': bookingTime,
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
  final DateTime date;
  final String time;
  final String address;
  final String? notes;
  final String? city;
  final String? postalCode;

  BookingCreateRequest({
    required this.serviceId,
    required this.handymanId,
    required this.date,
    required this.time,
    required this.address,
    this.notes,
    this.city,
    this.postalCode,
  });

  Map<String, dynamic> toJson() {
    return {
      "service": serviceId,
      "handyman": handymanId,
      "booking_date": date.toIso8601String(),
      "booking_time": time,
      "address": address,
      if (city != null && city!.isNotEmpty) "city": city,
      if (postalCode != null && postalCode!.isNotEmpty)
        "postal_code": postalCode,
      if (notes != null && notes!.isNotEmpty) "description": notes,
    };
  }
}
