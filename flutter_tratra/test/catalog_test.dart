// Catalogue commun des métiers : même arbre, mêmes noms, mêmes icônes que le site (`GET /handy/catalog/`), cache maîtrisé.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/screens/home/home_icons.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

Map<String, dynamic> row(int id, String name, String slug,
        {int? parent, int? trade, int position = 100, bool featured = false, int offers = 0, int total = 0, String? iconKey, int order = 0, int prestations = 0, String description = ''}) =>
    {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'icon': iconKey == null ? null : 'fa-solid fa-$iconKey',
      'icon_key': iconKey,
      'parent': parent,
      'trade': trade ?? id,
      'kind': parent == null ? 'trade' : 'service',
      'position': position,
      'order': order,
      'is_featured': featured,
      'is_active': true,
      'offers_count': offers,
      'offers_total': total,
      'prestations_count': prestations,
    };

/// Réponse type du serveur : Jardinage et Cuisine (avec prestations), Nounou (actif, SANS prestation ni offre).
Map<String, dynamic> payload({String version = 'v1', bool featured = true}) => {
      'count': 7,
      'version': version,
      'results': [
        row(7, 'Jardinage', 'jardinage', position: 10, featured: featured, total: 2, iconKey: 'tree', order: 0, prestations: 2),
        row(71, 'Élagage léger', 'elagage-leger', parent: 7, trade: 7, offers: 1, total: 1, order: 1),
        row(72, 'Entretien de fleurs', 'entretien-de-fleurs', parent: 7, trade: 7, offers: 1, total: 1, iconKey: 'seedling', order: 2),
        row(9, 'Cuisine', 'cuisine', position: 20, featured: featured, total: 1, iconKey: 'utensils', order: 3, prestations: 2, description: 'Repas à domicile'),
        row(91, 'Chef privé', 'chef-prive', parent: 9, trade: 9, offers: 1, total: 1, order: 4),
        row(92, 'Cours de cuisine', 'cours-de-cuisine', parent: 9, trade: 9, order: 5),
        row(12, 'Nounou', 'nounou', position: 30, iconKey: 'baby', order: 6),
      ],
    };

class Fixture {
  Fixture(this.handler) {
    api = BaseApi(client: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }));
    now = DateTime(2026, 10, 19, 10);
    repo = CatalogRepository(api, now: () => now);
  }
  final Future<http.Response> Function(http.Request) handler;
  final List<http.Request> requests = [];
  late final BaseApi api;
  late final CatalogRepository repo;
  late DateTime now;
}

http.Response ok(Map<String, dynamic> body, {String etag = 'W/"v1"'}) => http.Response(jsonEncode(body), 200, headers: {'etag': etag, 'content-type': 'application/json'});

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('arbre', () {
    final catalog = Catalog.fromJson(payload());

    test('Jardinage, Cuisine et Nounou : mêmes noms, arborescence et offres que le serveur', () {
      expect(catalog.trades.map((c) => c.name), ['Jardinage', 'Cuisine', 'Nounou']);
      expect(catalog.prestationsOf('7').map((c) => c.name), ['Élagage léger', 'Entretien de fleurs']);
      expect(catalog.prestationsOf('9').map((c) => c.name), ['Chef privé', 'Cours de cuisine']);
      expect(catalog.byId('7')!.offersTotal, 2);
      expect(catalog.byId('9')!.description, 'Repas à domicile');
      expect(catalog.byId('72')!.isTrade, isFalse);
      expect(catalog.byId('72')!.parent, '7');
      expect(catalog.byId('7')!.isTrade, isTrue);
    });

    test('un métier actif sans offre ni prestation n’est jamais masqué', () {
      final nounou = catalog.trades.firstWhere((c) => c.slug == 'nounou');
      expect(nounou.offersTotal, 0);
      expect(catalog.prestationsOf(nounou.id), isEmpty);
    });

    test('accueil : métiers mis en avant, sinon les premiers du catalogue', () {
      expect(catalog.homeTrades().map((c) => c.name), ['Jardinage', 'Cuisine']);
      final none = Catalog.fromJson(payload(featured: false));
      expect(none.homeTrades(fallbackLimit: 2).map((c) => c.name), ['Jardinage', 'Cuisine']);
      expect(none.homeTrades().map((c) => c.name), ['Jardinage', 'Cuisine', 'Nounou']);
    });

    test('les noms de filtres suivent l’ordre du catalogue (métier puis prestations)', () {
      expect(catalog.names.take(3), ['Jardinage', 'Élagage léger', 'Entretien de fleurs']);
    });

    test('une réponse vide ou illisible donne un catalogue vide, jamais une erreur', () {
      expect(Catalog.fromJson({}).items, isEmpty);
      expect(Catalog.fromJson({'results': 'x'}).items, isEmpty);
    });
  });

  group('icônes', () {
    test('Jardinage, Cuisine et Nounou ont leur icône du vocabulaire commun', () {
      final catalog = Catalog.fromJson(payload());
      expect(categoryIconFor(catalog.byId('7')!.iconKey), categoryIconByKey['tree']);
      expect(categoryIconFor(catalog.byId('9')!.iconKey), categoryIconByKey['utensils']);
      expect(categoryIconFor(catalog.byId('12')!.iconKey), categoryIconByKey['baby']);
    });

    test('une clé inconnue ou absente donne l’icône par défaut', () {
      expect(categoryIconFor('inconnue'), defaultCategoryIcon);
      expect(categoryIconFor(null), defaultCategoryIcon);
    });

    test('contrat avec le serveur : chaque clé d’icône du vocabulaire commun est dessinée (et rien d’autre)', () {
      // Le dépôt serveur est un dossier voisin : le contrôle est ignoré si le test tourne ailleurs.
      final file = File('../../tratra/handy/catalog.py');
      if (!file.existsSync()) return;
      final src = file.readAsStringSync();
      final body = src.substring(src.indexOf('ICON_KEYS = ('), src.indexOf('DEFAULT_ICON_KEY'));
      final keys = RegExp(r'"([a-z0-9-]+)"').allMatches(body).map((m) => m.group(1)!).toSet();
      expect(keys.length, greaterThan(100));
      expect(keys.difference(categoryIconByKey.keys.toSet()), isEmpty);
      expect(categoryIconByKey.keys.toSet().difference(keys), isEmpty);
    });
  });

  group('cache maîtrisé', () {
    test('premier appel : réseau, sans jeton ; appels suivants dans les 5 minutes : aucun appel', () async {
      final f = Fixture((_) async => ok(payload()));
      final first = await f.repo.load();
      expect(first.trades.length, 3);
      expect(f.requests.single.url.path, endsWith('/catalog/'));
      expect(f.requests.single.headers.containsKey('Authorization'), isFalse);
      await f.repo.load();
      f.now = f.now.add(const Duration(minutes: 4));
      await f.repo.load();
      expect(f.requests.length, 1);
    });

    test('plusieurs écrans en même temps : un seul appel réseau', () async {
      final f = Fixture((_) async => ok(payload()));
      final all = await Future.wait([f.repo.load(), f.repo.load(), f.repo.load()]);
      expect(f.requests.length, 1);
      expect(all.map((c) => c.version).toSet(), {'v1'});
    });

    test('au-delà de 5 minutes : revalidation par ETag, 304 = aucun retéléchargement', () async {
      final f = Fixture((req) async => req.headers['If-None-Match'] == 'W/"v1"' ? http.Response('', 304) : ok(payload()));
      final first = await f.repo.load();
      f.now = f.now.add(const Duration(minutes: 6));
      final second = await f.repo.load();
      expect(f.requests.length, 2);
      expect(f.requests.last.headers['If-None-Match'], 'W/"v1"');
      expect(identical(first, second), isTrue); // même catalogue, rien de re-décodé
      f.now = f.now.add(const Duration(minutes: 4)); // le 304 a rafraîchi l'horloge du cache
      await f.repo.load();
      expect(f.requests.length, 2);
    });

    test('catalogue modifié : la nouvelle version remplace l’ancienne', () async {
      var version = 'v1';
      final f = Fixture((_) async => ok(payload(version: version), etag: 'W/"$version"'));
      await f.repo.load();
      version = 'v2';
      final updated = await f.repo.load(forceRefresh: true);
      expect(updated.version, 'v2');
      expect(f.repo.cached!.version, 'v2');
    });

    test('panne réseau : la dernière version connue reste affichée ; sans cache, l’erreur remonte', () async {
      var down = false;
      final f = Fixture((_) async => down ? http.Response('boom', 503) : ok(payload()));
      await f.repo.load();
      down = true;
      f.now = f.now.add(const Duration(hours: 1));
      expect((await f.repo.load()).trades.length, 3);
      SharedPreferences.setMockInitialValues({}); // premier lancement : aucun cache disque
      final cold = Fixture((_) async => http.Response('boom', 503));
      await expectLater(cold.repo.load(), throwsA(anything));
    });

    test('le catalogue survit au redémarrage de l’application (cache disque) et se revalide', () async {
      final f = Fixture((_) async => ok(payload()));
      await f.repo.load();
      final restarted = Fixture((req) async => req.headers['If-None-Match'] == 'W/"v1"' ? http.Response('', 304) : ok(payload(version: 'v9')));
      restarted.now = f.now.add(const Duration(hours: 2));
      final catalog = await restarted.repo.load();
      expect(catalog.version, 'v1'); // servi depuis le disque, validé par ETag
      expect(restarted.requests.single.headers['If-None-Match'], 'W/"v1"');
    });

    test('un cache disque illisible est ignoré : le réseau prend le relais', () async {
      SharedPreferences.setMockInitialValues({'tratra.catalog.v1': '{pas du json'});
      final f = Fixture((_) async => ok(payload()));
      expect((await f.repo.load()).trades.length, 3);
    });

    test('un jeton expiré ne peut pas faire échouer le catalogue public', () async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'expiré'});
      final f = Fixture((_) async => ok(payload()));
      await f.repo.load();
      expect(f.requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });
}
