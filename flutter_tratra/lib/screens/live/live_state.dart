// lib/screens/live/live_state.dart
//
// Instantané du suivi en direct d'une mission (GET /bookings/{id}/live/ et flux WebSocket) : ce que voit CE
// participant. Tout vient du serveur ; rien n'est déduit ni inventé côté mobile.
import 'package:flutter/foundation.dart';

double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};

@immutable
class LivePos {
  const LivePos({required this.lat, required this.lng, this.accuracy, required this.ageSeconds, required this.stale});
  final double lat;
  final double lng;
  final double? accuracy;
  final int ageSeconds;
  final bool stale;

  static LivePos? from(dynamic v) {
    final m = _m(v);
    final lat = _d(m['lat']), lng = _d(m['lng']);
    if (lat == null || lng == null) return null;
    return LivePos(lat: lat, lng: lng, accuracy: _d(m['accuracy']), ageSeconds: _i(m['age_seconds']) ?? 0, stale: m['stale'] == true);
  }
}

@immutable
class LiveRoute {
  const LiveRoute({required this.etaMinutes, required this.distanceM, required this.polyline, required this.source});
  final int etaMinutes;
  final int distanceM;
  final List<(double, double)> polyline;

  /// `osrm` : itinéraire routier réel ; `estimate` : estimation à vol d'oiseau.
  final String source;

  bool get isEstimate => source != 'osrm';

  static LiveRoute? from(dynamic v) {
    if (v is! Map) return null;
    final m = v.cast<String, dynamic>();
    final eta = _i(m['eta_minutes']);
    if (eta == null) return null;
    final pts = ((m['polyline'] as List?) ?? const [])
        .whereType<List>()
        .where((p) => p.length >= 2 && _d(p[0]) != null && _d(p[1]) != null)
        .map((p) => (_d(p[0])!, _d(p[1])!))
        .toList();
    return LiveRoute(etaMinutes: eta, distanceM: _i(m['distance_m']) ?? 0, polyline: pts, source: '${m['source']}');
  }
}

@immutable
class LiveSnapshot {
  const LiveSnapshot({
    required this.bookingId,
    required this.role,
    required this.phase,
    required this.windowOpen,
    required this.artisanSharing,
    required this.clientSharing,
    required this.canStartRoute,
    required this.canArrive,
    required this.canShare,
    this.artisan,
    this.client,
    this.destination,
    this.destinationSource,
    this.route,
  });

  final int bookingId;
  final String role; // artisan | client
  final String phase; // pending | confirmed | en_route | arrived | in_progress | completed | cancelled
  final bool windowOpen;
  final bool artisanSharing;
  final bool clientSharing;
  final bool canStartRoute;
  final bool canArrive;
  final bool canShare;
  final LivePos? artisan;
  final LivePos? client;
  final (double, double)? destination;
  final String? destinationSource;
  final LiveRoute? route;

  bool get isArtisan => role == 'artisan';
  bool get isOpen => const {'confirmed', 'en_route', 'arrived', 'in_progress'}.contains(phase);

  factory LiveSnapshot.fromJson(Map<String, dynamic> j) {
    final consent = _m(j['consent']);
    final can = _m(j['can']);
    final dest = _m(j['destination']);
    final dLat = _d(dest['lat']), dLng = _d(dest['lng']);
    return LiveSnapshot(
      bookingId: _i(j['booking_id']) ?? 0,
      role: '${j['role']}',
      phase: '${j['phase']}',
      windowOpen: j['window_open'] == true,
      artisanSharing: consent['artisan'] == true,
      clientSharing: consent['client'] == true,
      canStartRoute: can['start_route'] == true,
      canArrive: can['arrive'] == true,
      canShare: can['share_position'] == true,
      artisan: LivePos.from(_m(j['artisan'])['position']),
      client: LivePos.from(_m(j['client'])['position']),
      destination: (dLat != null && dLng != null) ? (dLat, dLng) : null,
      destinationSource: dest['source'] as String?,
      route: LiveRoute.from(j['route']),
    );
  }
}

String formatEta(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String formatDistance(int meters) =>
    meters < 1000 ? '${(meters / 10).round() * 10} m' : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

String ageLabel(int seconds) {
  if (seconds < 10) return 'à l’instant';
  if (seconds < 60) return 'il y a $seconds s';
  return 'il y a ${(seconds / 60).round()} min';
}
