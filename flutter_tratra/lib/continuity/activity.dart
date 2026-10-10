// lib/continuity/activity.dart
//
// Activité en cours telle que le serveur la décrit (GET /me/activities/) : réservation, mission, demande Business ou contrat.
// Jamais de coordonnées ni d'adresse complète ; le détail se charge à l'ouverture, avec les contrôles habituels.

class Activity {
  const Activity({
    required this.kind,
    required this.id,
    required this.role,
    required this.status,
    required this.statusLabel,
    required this.title,
    required this.counterpart,
    required this.deeplink,
    required this.resumeLabel,
    this.version,
    this.bookingDate,
    this.city,
    this.updatedAt,
    this.active = true,
  });

  final String kind; // booking | mission | business_request | contract
  final int id;
  final String role; // client | handyman | requester | principal | worker
  final String status;
  final String statusLabel;
  final String title;
  final String counterpart;
  final String deeplink; // tratra://booking/12
  final String resumeLabel; // « Reprendre ma mission », « Suivre ma réservation »…
  final int? version;
  final DateTime? bookingDate;
  final String? city;
  final DateTime? updatedAt;
  final bool active;

  bool get isMission => kind == 'mission';
  String get key => '$kind:$id';

  static DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse('$v');

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        kind: '${j['kind'] ?? 'booking'}',
        id: j['id'] is num ? (j['id'] as num).toInt() : int.tryParse('${j['id']}') ?? 0,
        role: '${j['role'] ?? ''}',
        status: '${j['status'] ?? ''}',
        statusLabel: '${j['status_label'] ?? j['status'] ?? ''}',
        title: '${j['title'] ?? 'Intervention'}',
        counterpart: '${j['counterpart'] ?? ''}',
        deeplink: '${j['deeplink'] ?? 'tratra://notifications'}',
        resumeLabel: '${j['resume_label'] ?? 'Reprendre'}',
        version: j['version'] is num ? (j['version'] as num).toInt() : null,
        bookingDate: _dt(j['booking_date']),
        city: j['city'] == null ? null : '${j['city']}',
        updatedAt: _dt(j['updated_at']),
        active: j['active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'role': role,
        'status': status,
        'status_label': statusLabel,
        'title': title,
        'counterpart': counterpart,
        'deeplink': deeplink,
        'resume_label': resumeLabel,
        'version': version,
        'booking_date': bookingDate?.toIso8601String(),
        'city': city,
        'updated_at': updatedAt?.toIso8601String(),
        'active': active,
      };
}
