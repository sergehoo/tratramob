// Référentiel des métiers : familles de navigation, synonymes de recherche et « J'ai une panne ».
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
import 'package:flutter_tratra/screens/panne_screen.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

Map<String, dynamic> row(int id, String name, String slug, {int? parent, int? family, List<String> keywords = const [], String? iconKey, int order = 0}) => {
      'id': id, 'name': name, 'slug': slug, 'description': '', 'icon_key': iconKey, 'parent': parent, 'trade': parent ?? id, 'position': 100,
      'order': order, 'is_featured': false, 'is_active': true, 'offers_count': 0, 'offers_total': 0, 'prestations_count': 0,
      'family': family, 'keywords': keywords,
    };

final payload = {
  'count': 6,
  'version': 'v2',
  'results': [
    row(1, 'Maintenance informatique', 'maintenance-informatique', family: 100, iconKey: 'computer', order: 0, keywords: ['ordinateur', 'pc']),
    row(11, 'Récupération de données', 'recuperation-de-donnees', parent: 1, family: 100, order: 1, keywords: ['fichiers perdus']),
    row(3, 'Électroménager', 'electromenager', family: 200, iconKey: 'blender', order: 2),
    row(31, 'Réparation de réfrigérateur et congélateur', 'reparation-frigo', parent: 3, family: 200, order: 3, keywords: ['frigo', 'ne refroidit plus']),
    row(9, 'Cuisine', 'cuisine', iconKey: 'utensils', order: 4),
    row(91, 'Chef privé', 'chef-prive', parent: 9, order: 5),
  ],
  'families': [
    {'id': 200, 'name': 'Électroménager & froid', 'slug': 'electromenager-froid', 'icon_key': 'snowflake', 'order': 1, 'trades': [3]},
    {'id': 100, 'name': 'Informatique & Numérique', 'slug': 'informatique-numerique', 'icon_key': 'laptop', 'order': 0, 'trades': [1]},
  ],
};

http.Response json200(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

BaseApi apiWith(Future<http.Response> Function(http.Request) handler) => BaseApi(client: MockClient(handler));

Widget host(BaseApi api, Widget home) => Provider<BaseApi>.value(value: api, child: MaterialApp(theme: TratraTheme.light(), home: home));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('catalogue : familles dans l’ordre du serveur, « autres métiers », synonymes dans la recherche', () {
    final catalog = Catalog.fromJson(payload);
    expect(catalog.families.map((f) => f.name), ['Informatique & Numérique', 'Électroménager & froid']);
    expect(catalog.tradesOf(catalog.families.first).map((c) => c.name), ['Maintenance informatique']);
    expect(catalog.tradesWithoutFamily.map((c) => c.name), ['Cuisine']);
    expect(catalog.search('frigo').map((c) => c.slug), ['reparation-frigo']);
    expect(catalog.synonymOf(catalog.byId('31')!, 'FRIGO'), 'frigo');
    expect(catalog.search('electro').first.slug, 'electromenager'); // le nom passe avant les synonymes
    final again = Catalog.fromJson(catalog.toJson()); // cache disque : familles et synonymes conservés
    expect(again.families.length, 2);
    expect(again.byId('31')!.keywords, ['frigo', 'ne refroidit plus']);
    expect(Catalog.fromJson({'results': payload['results']}).families, isEmpty); // ancien serveur : aucune famille, rien de perdu
  });

  testWidgets('« Tous les métiers » rangé par familles ; une famille filtre ; un synonyme trouve le métier', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(host(apiWith((_) async => json200(payload)), const AllCategoriesScreen()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('panne-banner')), findsOneWidget);
    expect(find.text('Autres métiers'), findsWidgets); // puce et section
    for (final name in ['Maintenance informatique', 'Électroménager', 'Cuisine']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    await t.ensureVisible(find.byKey(const ValueKey('family-200')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('family-200')));
    await t.pumpAndSettle();
    expect(find.text('Électroménager'), findsOneWidget);
    expect(find.text('Maintenance informatique'), findsNothing);
    await t.tap(find.byTooltip('Supprimer les filtres')); // retour à toutes les familles
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'frigo');
    await t.pumpAndSettle();
    expect(find.text('Électroménager'), findsOneWidget);
    expect(find.text('Cuisine'), findsNothing);
  });

  testWidgets('« J’ai une panne » : la description donne les prestations, puis les offres de la commune', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final requests = <Uri>[];
    final api = apiWith((r) async {
      requests.add(r.url);
      if (r.url.path.endsWith('/catalog/match/')) {
        return json200({'query_terms': ['frigo', 'refroidit'], 'trades': [3], 'results': [
          {'id': 31, 'name': 'Réparation de réfrigérateur et congélateur', 'kind': 'service', 'trade': 3, 'trade_name': 'Électroménager',
            'icon_key': 'blender', 'offers_total': 2, 'score': 7.5},
        ]});
      }
      return json200({'count': 0, 'next': null, 'previous': null, 'results': []});
    });
    await t.pumpWidget(host(api, const PanneScreen()));
    await t.pumpAndSettle();
    expect(t.widget<TratraButton>(find.byKey(const ValueKey('panne-submit'))).onPressed, isNull); // rien à analyser
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('panne-text')), matching: find.byType(TextField)), 'Mon frigo ne refroidit plus');
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('panne-commune')), matching: find.byType(TextField)), 'Cocody');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('panne-submit')));
    await t.pumpAndSettle();
    final match = requests.firstWhere((u) => u.path.endsWith('/catalog/match/'));
    expect(match.queryParameters['q'], 'Mon frigo ne refroidit plus');
    expect(find.text('Réparation de réfrigérateur et congélateur'), findsOneWidget);
    expect(find.text('Électroménager · 2 offres'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('panne-result-31')));
    await t.pumpAndSettle();
    final services = requests.lastWhere((u) => u.path.contains('/services'));
    expect(services.queryParameters['category__name'], 'Réparation de réfrigérateur et congélateur');
    expect(services.queryParameters['commune'], 'Cocody');
    expect(find.text('Commune : Cocody'), findsOneWidget);
  });

  testWidgets('« J’ai une panne » : problème non reconnu → message clair, aucun artisan inventé', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = apiWith((r) async => json200({'query_terms': [], 'trades': [], 'results': []}));
    await t.pumpWidget(host(api, const PanneScreen(initialText: 'blabla inconnu')));
    await t.pumpAndSettle();
    expect(find.text('Problème non reconnu'), findsOneWidget);
  });
}
