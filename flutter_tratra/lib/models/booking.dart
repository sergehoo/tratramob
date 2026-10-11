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

  /// Artisan (résumé public joint par l'API) : nom affiché, id du profil (passeport) et badges Tratra Trust ACTUELS.
  final String? artisanName;
  final String? artisanProfileId;
  final List<String> artisanBadges;

  /// Version vue par ce téléphone : renvoyée avec chaque changement de statut pour détecter une écriture concurrente.
  final int version;

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
    this.artisanName,
    this.artisanProfileId,
    this.artisanBadges = const [],
    this.version = 1,
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

    final artisan = serviceData is Map && serviceData['artisan'] is Map ? Map<String, dynamic>.from(serviceData['artisan'] as Map) : null;
    const knownBadges = {'VERIFIE', 'EXPERT', 'SUR'};
    final badges = ((artisan?['badges'] as List?) ?? const [])
        .map((e) => e is Map ? '${e['code']}' : '$e')
        .where(knownBadges.contains)
        .toList();

    return Booking(
      version: json['version'] is num ? (json['version'] as num).toInt() : 1,
      artisanName: (artisan?['display_name'] ?? '').toString().isEmpty ? null : artisan!['display_name'].toString(),
      artisanProfileId: artisan?['id']?.toString(),
      artisanBadges: badges,
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

  /// Coordonnées FACULTATIVES du lieu (position de l'appareil, avec accord) : alimentent l'heure d'arrivée du suivi.
  final double? latitude;
  final double? longitude;

  /// Montant de déplacement que le client a vu : le serveur RECALCULE ; un écart donne un 409 `transport_changed`.
  final int? expectedTransportFee;

  BookingCreateRequest._({
    required this.serviceId,
    required this.handymanId,
    required this.scheduledAt,
    required this.address,
    required this.city,
    required this.postalCode,
    this.notes,
    this.latitude,
    this.longitude,
    this.expectedTransportFee,
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
    double? latitude,
    double? longitude,
    int? expectedTransportFee,
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
      latitude: (latitude != null && longitude != null) ? latitude : null,
      longitude: (latitude != null && longitude != null) ? longitude : null,
      expectedTransportFee: (latitude != null && longitude != null) ? expectedTransportFee : null,
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
      if (latitude != null && longitude != null) ...{'lat': latitude, 'lng': longitude},
      if (expectedTransportFee != null) 'expected_transport_fee': expectedTransportFee,
      if (notes != null && notes!.isNotEmpty) "description": notes,
    };
  }
}
