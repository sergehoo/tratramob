// Écran « Tous les métiers » : le catalogue COMMUN, avec Jardinage, Cuisine et Nounou (métier actif sans offre), recherche dans les prestations,
// prestations à l'ouverture d'un métier, panne réseau et cache.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/all_categories_screen.dart';

Map<String, dynamic> row(int id, String name, String slug, {int? parent, int total = 0, String? iconKey, int order = 0, int prestations = 0, bool featured = false}) => {
      'id': id, 'name': name, 'slug': slug, 'description': '', 'icon': iconKey == null ? null : 'fa-solid fa-$iconKey', 'icon_key': iconKey, 'parent': parent,
      'trade': parent ?? id, 'position': 100, 'order': order, 'is_featured': featured, 'is_active': true, 'offers_count': total, 'offers_total': total,
      'prestations_count': prestations,
    };

final catalogBody = jsonEncode({
  'count': 7,
  'version': 'v1',
  'results': [
    row(7, 'Jardinage', 'jardinage', total: 2, iconKey: 'tree', order: 0, prestations: 2, featured: true),
    row(71, 'Élagage léger', 'elagage-leger', parent: 7, total: 1, order: 1),
    row(72, 'Entretien de fleurs', 'entretien-de-fleurs', parent: 7, total: 1, order: 2),
    row(9, 'Cuisine', 'cuisine', total: 1, iconKey: 'utensils', order: 3, prestations: 2, featured: true),
    row(91, 'Chef privé', 'chef-prive', parent: 9, total: 1, order: 4),
    row(92, 'Cours de cuisine', 'cours-de-cuisine', parent: 9, order: 5),
    row(12, 'Nounou', 'nounou', iconKey: 'baby', order: 6),
  ],
});

Widget host(BaseApi api) => Provider<BaseApi>.value(value: api, child: MaterialApp(theme: TratraTheme.light(), home: const AllCategoriesScreen()));

BaseApi apiWith(Future<http.Response> Function(http.Request) handler) => BaseApi(client: MockClient(handler));

/// Réponse JSON en UTF-8 (comme le serveur) : sans charset, `http.Response` encoderait les accents en latin1.
http.Response json200(String body, {Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json; charset=utf-8', ...headers});

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('affiche Jardinage, Cuisine et Nounou avec leurs prestations et leurs offres ; Nounou reste visible sans offre', (t) async {
    final api = apiWith((_) async => json200(catalogBody, headers: {'etag': 'W/"v1"'}));
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    for (final name in ['Jardinage', 'Cuisine', 'Nounou']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('2 prestations'), findsNWidgets(2)); // Jardinage et Cuisine
    expect(find.text('Aucune offre'), findsOneWidget); // Nounou : actif, sans prestation ni offre
    expect(find.text('Élagage léger'), findsNothing); // les prestations s'ouvrent depuis la carte du métier
  });

  testWidgets('la recherche trouve un métier par le nom de l’une de ses prestations, sans tenir compte des accents', (t) async {
    final api = apiWith((_) async => json200(catalogBody));
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'elag');
    await t.pump();
    expect(find.text('Jardinage'), findsOneWidget);
    expect(find.text('Cuisine'), findsNothing);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pump();
    expect(find.text('Aucun métier'), findsOneWidget);
  });

  testWidgets('ouvrir un métier liste ses prestations avec leurs offres', (t) async {
    final api = apiWith((_) async => json200(catalogBody));
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Cuisine'));
    await t.pumpAndSettle();
    expect(find.text('Chef privé'), findsOneWidget);
    expect(find.text('Cours de cuisine'), findsOneWidget);
    expect(find.text('1 offre'), findsWidgets);
    expect(find.text('Voir les offres de Cuisine'), findsOneWidget);
  });

  testWidgets('panne sans cache : message clair et bouton Réessayer ; une fois le réseau revenu, le catalogue s’affiche', (t) async {
    var down = true;
    final api = apiWith((_) async => down ? http.Response('boom', 503) : json200(catalogBody));
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    expect(find.text('Chargement impossible'), findsOneWidget);
    down = false;
    await t.tap(find.text('Réessayer'));
    await t.pumpAndSettle();
    expect(find.text('Jardinage'), findsOneWidget);
  });

  testWidgets('catalogue vide : message d’attente, jamais de métier inventé', (t) async {
    final api = apiWith((_) async => json200(jsonEncode({'count': 0, 'results': []})));
    await t.pumpWidget(host(api));
    await t.pumpAndSettle();
    expect(find.text('Le catalogue des métiers arrive'), findsOneWidget);
    expect(find.text('Plomberie'), findsNothing);
  });
}
