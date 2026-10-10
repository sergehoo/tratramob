// Tratra Live : instantané du suivi, formats et cartes — fidèles au serveur, rien d'inventé côté mobile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/live/live_cards.dart';
import 'package:flutter_tratra/screens/live/live_controller.dart';
import 'package:flutter_tratra/screens/live/live_state.dart';

Map<String, dynamic> _json({
  String role = 'client',
  String phase = 'en_route',
  bool artisanSharing = true,
  bool clientSharing = false,
  Map<String, dynamic>? artisan,
  Map<String, dynamic>? route,
  Map<String, dynamic>? destination = const {'lat': 5.36, 'lng': -4.0083, 'source': 'booking'},
}) =>
    {
      'booking_id': 11,
      'role': role,
      'phase': phase,
      'status': phase == 'en_route' || phase == 'arrived' ? 'confirmed' : phase,
      'window_open': true,
      'consent': {'artisan': artisanSharing, 'client': clientSharing},
      'can': {'start_route': role == 'artisan' && phase == 'confirmed', 'arrive': role == 'artisan' && (phase == 'confirmed' || phase == 'en_route'), 'share_position': phase == 'confirmed' || phase == 'en_route'},
      'artisan': {'sharing': artisanSharing, 'position': artisan},
      'client': {'sharing': clientSharing, 'position': null},
      'destination': destination,
      'route': route,
    };

const _pos = {'lat': 5.37, 'lng': -4.012, 'accuracy': 12.0, 'age_seconds': 4, 'stale': false};
const _estimate = {
  'eta_minutes': 3,
  'distance_m': 1180,
  'source': 'estimate',
  'polyline': [
    [5.37, -4.012],
    [5.36, -4.0083]
  ],
};

void main() {
  group('LiveSnapshot', () {
    test('lit positions, itinéraire estimé et actions autorisées', () {
      final s = LiveSnapshot.fromJson(_json(artisan: _pos, route: _estimate));
      expect(s.phase, 'en_route');
      expect(s.isOpen, isTrue);
      expect(s.artisan!.lat, 5.37);
      expect(s.artisan!.stale, isFalse);
      expect(s.route!.etaMinutes, 3);
      expect(s.route!.isEstimate, isTrue);
      expect(s.route!.polyline, hasLength(2));
      expect(s.destination, (5.36, -4.0083));
      expect(s.canStartRoute, isFalse);
    });

    test('artisan : « en route » proposé seulement à l’artisan, avant le trajet', () {
      final s = LiveSnapshot.fromJson(_json(role: 'artisan', phase: 'confirmed', artisanSharing: false, destination: null));
      expect(s.canStartRoute, isTrue);
      expect(s.canArrive, isTrue);
      expect(s.destination, isNull);
      expect(s.artisan, isNull);
      expect(s.route, isNull);
    });

    test('payload partiel ou incohérent : aucun repère inventé', () {
      final s = LiveSnapshot.fromJson({'booking_id': 1, 'role': 'client', 'phase': 'completed', 'artisan': {'position': {'lat': 'x'}}});
      expect(s.artisan, isNull);
      expect(s.route, isNull);
      expect(s.isOpen, isFalse);
    });
  });

  group('formats', () {
    test('ETA, distance et ancienneté', () {
      expect(formatEta(3), '3 min');
      expect(formatEta(65), '1 h 05');
      expect(formatDistance(1180), '1,2 km');
      expect(formatDistance(420), '420 m');
      expect(ageLabel(4), 'à l’instant');
      expect(ageLabel(45), 'il y a 45 s');
      expect(ageLabel(200), 'il y a 3 min');
    });
  });

  group('cartes', () {
    Widget host(LiveController c) => MaterialApp(
          theme: TratraTheme.light(),
          home: Scaffold(body: SingleChildScrollView(child: LivePanel(controller: c))),
        );

    LiveController controllerWith(Map<String, dynamic> json, {bool offline = false}) {
      final c = LiveController(BaseApi(), 11);
      c.state = LiveSnapshot.fromJson(json);
      c.offline = offline;
      return c;
    }

    testWidgets('mission confirmée sans localisation : aucune carte, aucun faux ETA', (t) async {
      final c = controllerWith(_json(phase: 'confirmed', artisanSharing: false, destination: null));
      await t.pumpWidget(host(c));
      expect(find.text('Confirmée'), findsOneWidget);
      expect(find.text('Arrivée estimée'), findsNothing);
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('en route : ETA et distance réelles, estimation signalée honnêtement', (t) async {
      final c = controllerWith(_json(artisan: _pos, route: _estimate));
      await t.pumpWidget(host(c));
      expect(find.text('Arrivée estimée'), findsOneWidget);
      expect(find.text('3 min'), findsOneWidget);
      expect(find.text('1,2 km'), findsOneWidget);
      expect(find.textContaining('Estimation à vol d’oiseau'), findsOneWidget);
    });

    testWidgets('lieu inconnu : pas de distance ni d’heure d’arrivée calculées', (t) async {
      final c = controllerWith(_json(artisan: _pos, destination: null));
      await t.pumpWidget(host(c));
      expect(find.textContaining('n’est pas localisé'), findsOneWidget);
      expect(find.text('Arrivée estimée'), findsNothing);
    });

    testWidgets('position ancienne et connexion perdue sont signalées', (t) async {
      final stale = {..._pos, 'stale': true, 'age_seconds': 200};
      final c = controllerWith(_json(artisan: stale, route: _estimate), offline: true);
      await t.pumpWidget(host(c));
      expect(find.text('Position ancienne'), findsOneWidget);
      expect(find.textContaining('il y a 3 min'), findsOneWidget);
      expect(find.text('Connexion perdue'), findsOneWidget);
    });

    testWidgets('artisan suspendu : le client le voit sans position', (t) async {
      final c = controllerWith(_json(artisanSharing: false));
      await t.pumpWidget(host(c));
      expect(find.textContaining('suspendu le partage'), findsOneWidget);
    });
  });
}
