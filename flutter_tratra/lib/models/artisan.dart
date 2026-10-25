// models/artisan.dart
class Artisan {
  final String id;
  final String name;
  final String profession;
  final double rating;
  final int reviews;
  final String imageUrl;
  final double distance;
  final bool isAvailable;
  final double hourlyRate;
  final bool isCertified;
  final String? responseTime;
  final int yearsExperience;
  final List<String> specialties;
  final String description;

  /// Tratra Trust : badges ACTUELS (codes) et score expliqué (null tant qu'il n'est pas calculable).
  final List<String> trustBadges;
  final int? trustScore;

  /// Compte du membre (anneau de ses statuts sur l'avatar) ; absent des anciennes réponses.
  final int? userId;

  Artisan({
    required this.id,
    required this.name,
    required this.profession,
    required this.rating,
    required this.reviews,
    required this.imageUrl,
    required this.distance,
    required this.isAvailable,
    required this.hourlyRate,
    required this.isCertified,
    this.responseTime,
    required this.yearsExperience,
    required this.specialties,
    required this.description,
    this.trustBadges = const [],
    this.trustScore,
    this.userId,
  });

  // Méthode fromJson — tolère le snake_case du backend Django DRF
  // (image_url, hourly_rate, ...) ET le camelCase, pour éviter la perte de données.
  factory Artisan.fromJson(Map<String, dynamic> json) {
    dynamic pick(List<String> keys) {
      for (final k in keys) {
        if (json[k] != null) return json[k];
      }
      return null;
    }

    double toDouble(dynamic v) =>
        v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
    int toInt(dynamic v) =>
        v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

    final full = pick(['full_name', 'name']);
    final firstLast =
        '${json['first_name'] ?? ''} ${json['last_name'] ?? ''}'.trim();

    return Artisan(
      id: (pick(['id']) ?? '').toString(),
      name: (full ?? (firstLast.isNotEmpty ? firstLast : '')).toString(),
      profession: (pick(['profession', 'bio']) ?? '').toString(),
      rating: toDouble(pick(['rating'])),
      reviews: toInt(pick(['reviews', 'completed_jobs'])),
      imageUrl: (pick(['image_url', 'imageUrl', 'photo', 'profile_picture']) ?? '')
          .toString(),
      distance: toDouble(pick(['distance_m', 'distance'])),
      isAvailable: (pick(['online', 'is_available', 'isAvailable']) ?? false) == true,
      hourlyRate: toDouble(pick(['hourly_rate', 'hourlyRate'])),
      isCertified:
          (pick(['is_approved', 'is_certified', 'isCertified']) ?? false) == true,
      responseTime: pick(['response_time', 'responseTime'])?.toString(),
      yearsExperience: toInt(pick(['experience_years', 'years_experience', 'yearsExperience'])),
      specialties: List<String>.from(pick(['specialties']) ?? const []),
      description: (pick(['description', 'bio']) ?? '').toString(),
      trustBadges: _trustCodes(json['badges']),
      trustScore: json['trust_score'] is num ? (json['trust_score'] as num).round() : null,
      userId: _userId(json),
    );
  }

  String? get specialty => null;

  String? get photoUrl => null;

  // Méthode toJson pour sérialiser (optionnelle)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'profession': profession,
      'rating': rating,
      'reviews': reviews,
      'imageUrl': imageUrl,
      'distance': distance,
      'isAvailable': isAvailable,
      'hourlyRate': hourlyRate,
      'isCertified': isCertified,
      'responseTime': responseTime,
      'yearsExperience': yearsExperience,
      'specialties': specialties,
      'description': description,
    };
  }
}

/// Codes de badges Tratra Trust depuis `[{code, label}, ...]` (codes inconnus ignorés).
List<String> _trustCodes(dynamic raw) {
  const known = {'NOUVEAU', 'VERIFIE', 'EXPERT', 'SUR'};
  if (raw is! List) return const [];
  return raw.map((e) => e is Map ? '${e['code']}' : '$e').where(known.contains).toList();
}

/// Compte rattaché : `user` (identifiant), `user_detail.id` ou `user_id` selon la réponse.
int? _userId(Map<String, dynamic> json) {
  final raw = json['user'] is num ? json['user'] : (json['user_detail'] is Map ? (json['user_detail'] as Map)['id'] : json['user_id']);
  return raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
}
