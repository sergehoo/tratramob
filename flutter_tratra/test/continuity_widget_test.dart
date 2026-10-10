// Bandeau « Activité en cours » : retrouver sa mission en un geste, état hors ligne jamais présenté comme à jour.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/continuity/activities_controller.dart';
import 'package:flutter_tratra/continuity/continuity_widgets.dart';
import 'package:flutter_tratra/design/design.dart';

Map<String, dynamic> _a(int id, String title, String status, {String kind = 'mission', String resume = 'Reprendre ma mission'}) => {
      'kind': kind,
      'id': id,
      'role': kind == 'mission' ? 'handyman' : 'client',
      'status': status,
      'status_label': status == 'in_progress' ? 'En cours' : 'Confirmé',
      'version': 2,
      'title': title,
      'counterpart': 'Awa K.',
      'city': 'Abidjan',
      'active': true,
      'deeplink': 'tratra://$kind/$id',
      'resume_label': resume,
    };

Future<ActivitiesController> _bound(List<Map<String, dynamic>> items, {bool failNext = false}) async {
  var fail = false;
  final c = ActivitiesController(
    retryBase: const Duration(hours: 1), // pas de relance automatique pendant le test
    fetch: (_) async {
      if (fail) throw Exception('réseau coupé');
      return {'server_time': '2026-10-10T10:30:00Z', 'activities': items, 'primary': items.isEmpty ? null : items.first};
    },
  );
  await c.bindUser('1');
  if (failNext) {
    fail = true;
    await c.refresh(force: true);
  }
  return c;
}

Widget _host(ActivitiesController c) => ChangeNotifierProvider<ActivitiesController>.value(
      value: c,
      child: MaterialApp(theme: TratraTheme.light(), home: const Scaffold(body: SingleChildScrollView(child: ActivityBanner()))),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('mission en cours : bouton « Reprendre ma mission », titre et statut réels', (t) async {
    final c = await _bound([_a(7, 'Dépannage fuite', 'in_progress')]);
    await t.pumpWidget(_host(c));
    expect(find.text('Activité en cours'), findsOneWidget);
    expect(find.text('Dépannage fuite'), findsOneWidget);
    expect(find.text('Reprendre ma mission'), findsOneWidget);
    expect(find.textContaining('Hors ligne'), findsNothing);
  });

  testWidgets('client : « Suivre ma réservation » ; plusieurs activités : liste complète accessible', (t) async {
    final c = await _bound([
      _a(1, 'Plomberie à domicile', 'confirmed', kind: 'booking', resume: 'Suivre ma réservation'),
      _a(2, 'Installation électrique', 'confirmed', kind: 'booking', resume: 'Suivre ma réservation'),
    ]);
    await t.pumpWidget(_host(c));
    expect(find.text('Suivre ma réservation'), findsOneWidget);
    await t.tap(find.text('Voir les 2 activités'));
    await t.pumpAndSettle();
    expect(find.text('Mes activités en cours'), findsOneWidget);
    expect(find.text('Installation électrique'), findsOneWidget);
  });

  testWidgets('hors ligne : dernier état connu affiché et clairement signalé comme non vérifié', (t) async {
    final c = await _bound([_a(7, 'Dépannage fuite', 'in_progress')], failNext: true);
    await t.pumpWidget(_host(c));
    expect(find.text('Dépannage fuite'), findsOneWidget); // la mission n'a pas disparu avec le réseau
    expect(find.textContaining('Hors ligne'), findsOneWidget);
    expect(find.textContaining('non vérifié'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // l'arbre est retiré avant la libération du contrôleur
    c.dispose(); // annule la relance automatique programmée
  });

  testWidgets('aucune activité : rien n’est affiché', (t) async {
    final c = await _bound([]);
    await t.pumpWidget(_host(c));
    expect(find.text('Activité en cours'), findsNothing);
    expect(find.byType(TratraCard), findsNothing);
  });

  testWidgets('mise à jour venue d’ailleurs : message affichable puis fermable', (t) async {
    final c = ActivitiesController(fetch: (_) async => {'server_time': '2026-10-10T10:30:00Z', 'activities': [], 'primary': null});
    await c.bindUser('1');
    c.clearNotice();
    await t.pumpWidget(_host(c));
    expect(find.byType(TratraAlert), findsNothing);
  });
}
