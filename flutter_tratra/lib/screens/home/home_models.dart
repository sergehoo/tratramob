// lib/screens/home/home_models.dart
//
// Données et formatage de l'accueil client. Aucune règle métier : uniquement la lecture
// tolérante de la réponse de l'API et l'affichage (prix, distance, URL de média).
import 'package:flutter_tratra/design/design.dart' show trustBadgeCodes;
import 'package:flutter_tratra/models/service.dart';

/// Réécrit les URL de médias vers l'hôte public (même logique qu'avant le découpage).
String homeFixMediaUrl(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  var url = raw.trim();

  if (url.startsWith('/')) return 'https://minio.tratra.net$url';

  url = url.replaceFirst('http://minio:9000', 'https://minio.tratra.net');
  url = url.replaceFirst('https://minio:9000', 'https://minio.tratra.net');

  url = url.replaceFirst('http://tratra.net', 'https://minio.tratra.net');
  url = url.replaceFirst('https://tratra.net', 'https://minio.tratra.net');

  if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
  return url;
}

double? _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

/// Résumé public de l'artisan, tel que l'API le joint déjà à chaque service
/// (`artisan` + `handyman_detail` + `distance_km`). Tout est optionnel : un champ absent
/// n'est simplement pas affiché, rien n'est inventé.
class HomeArtisanBrief {
  const HomeArtisanBrief({
    this.displayName,
    this.commune,
    this.rating,
    this.verified = false,
    this.online = false,
    this.photoUrl,
    this.distanceKm,
    this.badges = const [],
    this.trustScore,
  });

  final String? displayName;
  final String? commune;

  /// Note moyenne réelle (> 0 uniquement, sinon `null`).
  final double? rating;
  final bool verified;
  final bool online;
  final String? photoUrl;
  final double? distanceKm;

  /// Tratra Trust : badges ACTUELS (codes VERIFIE / EXPERT / SUR) et score (null tant qu'il n'est pas calculable).
  final List<String> badges;
  final int? trustScore;

  bool get hasName => (displayName ?? '').trim().isNotEmpty;

  static HomeArtisanBrief? fromServiceJson(Map<String, dynamic> map) {
    final artisan = map['artisan'];
    final detail = map['handyman_detail'];
    final distance = _asDouble(map['distance_km']);
    if (artisan is! Map && detail is! Map && distance == null) return null;

    final a = artisan is Map ? artisan : const <dynamic, dynamic>{};
    final d = detail is Map ? detail : const <dynamic, dynamic>{};

    String? text(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    final rating = _asDouble(a['rating']);
    final photo = homeFixMediaUrl(text(a['photo']));

    return HomeArtisanBrief(
      displayName: text(a['display_name']) ?? text(d['display_name']),
      commune: text(a['commune']),
      rating: (rating != null && rating > 0) ? rating : null,
      verified: a['is_verified'] == true,
      online: a['online'] == true,
      photoUrl: photo.isEmpty ? null : photo,
      distanceKm: distance,
      badges: trustBadgeCodes(a['badges']),
      trustScore: a['trust_score'] is num ? (a['trust_score'] as num).round() : null,
    );
  }
}

/// Un service de l'accueil + le résumé public de son artisan (si l'API le fournit).
class HomeServiceEntry {
  const HomeServiceEntry(this.service, [this.artisan]);
  final Service service;
  final HomeArtisanBrief? artisan;
}

/// Format monétaire lisible : `12 500` (espace insécable comme séparateur de milliers).
String homeFormatFcfa(num value) {
  final digits = value.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buf.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) buf.write(' ');
  }
  return value < 0 ? '-$buf' : buf.toString();
}

/// Libellé de prix fidèle au type de tarification du service (jamais « 0 FCFA » inventé).
String homePriceLabel(Service s) {
  if (s.isQuoteBased) return 'Sur devis';
  final p = s.price;
  if (p == null || p <= 0) return 'Prix non précisé';
  final base = '${homeFormatFcfa(p)} FCFA';
  return s.isHourly ? '$base/h' : base;
}

/// Distance lisible : `850 m`, `2,3 km`, `14 km`.
String homeFormatKm(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '${text.replaceAll('.', ',')} km';
}
