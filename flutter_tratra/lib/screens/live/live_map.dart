// lib/screens/live/live_map.dart
//
// Carte interactive du suivi (flutter_map, fond OpenStreetMap) : artisan, client (s'il partage sa position),
// lieu d'intervention et itinéraire réels. Aucun repère sans position reçue du serveur.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/live/live_state.dart';

/// Gabarit des tuiles : OpenStreetMap par défaut ; à remplacer par un fournisseur adapté au volume en production
/// (`--dart-define=MAP_TILES=https://.../{z}/{x}/{y}.png`).
const String kMapTiles = String.fromEnvironment('MAP_TILES', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

class LiveMap extends StatefulWidget {
  const LiveMap({super.key, required this.snapshot, this.height = 280});
  final LiveSnapshot snapshot;
  final double height;

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  final MapController _controller = MapController();
  bool _ready = false;
  String _fitKey = '';

  List<LatLng> get _points {
    final s = widget.snapshot;
    return [
      if (s.destination != null) LatLng(s.destination!.$1, s.destination!.$2),
      if (s.client != null) LatLng(s.client!.lat, s.client!.lng),
      if (s.artisan != null) LatLng(s.artisan!.lat, s.artisan!.lng),
      ...?s.route?.polyline.map((p) => LatLng(p.$1, p.$2)),
    ];
  }

  void _fit() {
    final pts = _points;
    if (!_ready || pts.isEmpty) return;
    final key = pts.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').join('|');
    if (key == _fitKey) return;
    _fitKey = key;
    if (pts.length == 1) {
      _controller.move(pts.first, 15);
    } else {
      _controller.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(36), maxZoom: 16));
    }
  }

  @override
  void didUpdateWidget(covariant LiveMap old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  Marker _dot(LatLng at, Color color, Color ring, String label) => Marker(
        point: at,
        width: 26,
        height: 26,
        child: Semantics(
          label: label,
          child: Container(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: ring, width: 3), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final route = s.route?.polyline.map((p) => LatLng(p.$1, p.$2)).toList() ?? const <LatLng>[];
    return ClipRRect(
      borderRadius: BorderRadius.circular(TtRadius.panel),
      child: SizedBox(
        height: widget.height,
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: const LatLng(5.36, -4.0083),
            initialZoom: 12,
            // Pas de glisser à un doigt : la carte occupe un tiers de l'écran et piégerait le défilement de la page
          // (constaté sur téléphone). Le cadrage suit les repères ; pincer / double-toucher suffit pour zoomer.
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
            onMapReady: () {
              _ready = true;
              _fit();
            },
          ),
          children: [
            TileLayer(urlTemplate: kMapTiles, userAgentPackageName: 'net.tratra.app'),
            if (route.length > 1) PolylineLayer(polylines: [Polyline(points: route, strokeWidth: 5, color: TtColors.primary.withValues(alpha: 0.85))]),
            MarkerLayer(markers: [
              if (s.destination != null) _dot(LatLng(s.destination!.$1, s.destination!.$2), TtColors.night, TtColors.accent, 'Lieu d’intervention'),
              if (s.client != null) _dot(LatLng(s.client!.lat, s.client!.lng), TtColors.accent, Colors.white, 'Client'),
              if (s.artisan != null) _dot(LatLng(s.artisan!.lat, s.artisan!.lng), s.artisan!.stale ? TtColors.fog : TtColors.primary, Colors.white, 'Artisan'),
            ]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('© contributeurs OpenStreetMap')]),
          ],
        ),
      ),
    );
  }
}
