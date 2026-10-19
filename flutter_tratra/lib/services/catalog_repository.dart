// lib/services/catalog_repository.dart
//
// Catalogue COMMUN des métiers : `GET /handy/catalog/`, la même réponse que le site. Aucun métier n'est écrit en dur dans l'application.
//
//   MÉTIER     catégorie racine (« Jardinage », « Cuisine », « Nounou »)
//   PRESTATION sous-catégorie d'un métier
//   OFFRE      service publié par un professionnel (compté dans `offersTotal`)
//
// Cache maîtrisé : mémoire + disque (SharedPreferences), frais pendant 5 minutes ; au-delà, revalidation par `ETag` (réponse 304 = aucun
// retéléchargement). En cas de panne réseau, la dernière version connue reste affichée (jamais un écran vide si le catalogue a déjà été vu).
// Un seul appel réseau à la fois, même si plusieurs écrans le demandent en même temps.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durée pendant laquelle le catalogue en cache est servi sans interroger le serveur.
const Duration catalogFreshFor = Duration(minutes: 5);

/// Nombre de métiers affichés à l'accueil si l'administration n'en a mis aucun en avant (jamais un accueil vide).
const int catalogFallbackFeatured = 10;

const String _prefsKey = 'tratra.catalog.v1';

class Catalog {
  Catalog(this.items, {this.version = ''});

  /// Entrées à plat, dans l'ordre d'affichage du serveur (métier, puis ses prestations).
  final List<Category> items;
  final String version;

  List<Category> get trades => [for (final c in items) if (c.isTrade) c];

  /// Prestations (sous-catégories) d'un métier, dans l'ordre du catalogue.
  List<Category> prestationsOf(String tradeId) => [for (final c in items) if (!c.isTrade && c.trade == tradeId) c];

  /// Métiers mis en avant par l'administration ; à défaut, les premiers du catalogue.
  List<Category> homeTrades({int fallbackLimit = catalogFallbackFeatured}) {
    final all = trades;
    final featured = [for (final c in all) if (c.isFeatured) c];
    return featured.isNotEmpty ? featured : all.take(fallbackLimit).toList();
  }

  Category? byId(String id) {
    for (final c in items) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Noms de toutes les catégories (métiers puis prestations) : listes de filtres.
  List<String> get names => [for (final c in items) if (c.name.isNotEmpty) c.name];

  factory Catalog.fromJson(Map<String, dynamic> json) {
    final results = json['results'];
    final rows = results is List ? results : const [];
    return Catalog(
      [for (final r in rows) if (r is Map) Category.fromJson(Map<String, dynamic>.from(r))],
      version: json['version']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'results': [for (final c in items) c.toJson()],
      };
}

class CatalogRepository {
  CatalogRepository(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final BaseApi _api;
  final DateTime Function() _now;

  static final Expando<CatalogRepository> _shared = Expando<CatalogRepository>('catalog');

  /// Instance unique par client d'API : tous les écrans partagent le même cache.
  static CatalogRepository shared(BaseApi api) => _shared[api] ??= CatalogRepository(api);

  Catalog? _memory;
  String? _etag;
  DateTime? _checkedAt;
  bool _diskRead = false;
  Future<Catalog>? _inflight;

  /// Dernière version connue (mémoire ou disque déjà lu), sans réseau.
  Catalog? get cached => _memory;

  /// Catalogue à jour : cache frais → aucun appel ; sinon revalidation (ETag) ; panne → dernière version connue.
  Future<Catalog> load({bool forceRefresh = false}) {
    return _inflight ??= _load(forceRefresh).whenComplete(() => _inflight = null);
  }

  bool get _fresh => _checkedAt != null && _now().difference(_checkedAt!) < catalogFreshFor;

  Future<Catalog> _load(bool force) async {
    await _readDisk();
    final known = _memory;
    if (!force && known != null && _fresh) return known;
    try {
      return await _fetch();
    } catch (_) {
      if (known != null) return known; // panne réseau ou serveur : la dernière version connue reste affichée
      rethrow;
    }
  }

  Future<Catalog> _fetch() async {
    final uri = Uri.parse('${_api.baseUrl}/catalog/');
    final headers = {...await _api.getHeaders(withAuth: false), if (_etag != null && _memory != null) 'If-None-Match': _etag!};
    final r = await _api.client.get(uri, headers: headers); // public : aucun jeton, un jeton expiré ne peut pas faire échouer le catalogue
    if (r.statusCode == 304 && _memory != null) {
      _checkedAt = _now();
      await _writeDisk();
      return _memory!;
    }
    if (r.statusCode != 200) _api.handleError(r);
    final decoded = _api.decodeBody(r);
    if (decoded is! Map) throw const FormatException('catalogue illisible');
    final catalog = Catalog.fromJson(Map<String, dynamic>.from(decoded));
    _memory = catalog;
    _etag = r.headers['etag'];
    _checkedAt = _now();
    await _writeDisk();
    return catalog;
  }

  Future<void> _readDisk() async {
    if (_diskRead) return;
    _diskRead = true;
    if (_memory != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final catalog = Catalog.fromJson(Map<String, dynamic>.from(data['catalog'] as Map));
      if (catalog.items.isEmpty) return;
      _memory = catalog;
      _etag = data['etag']?.toString();
      _checkedAt = DateTime.tryParse('${data['checkedAt']}');
    } catch (_) {
      // cache illisible : ignoré, le réseau prend le relais
    }
  }

  Future<void> _writeDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({'etag': _etag, 'checkedAt': _checkedAt?.toIso8601String(), 'catalog': _memory!.toJson()}),
      );
    } catch (_) {
      // disque indisponible : le cache mémoire suffit
    }
  }
}
