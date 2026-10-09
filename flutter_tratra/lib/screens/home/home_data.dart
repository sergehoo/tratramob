// lib/screens/home/home_data.dart
//
// Accès aux données de l'accueil client : mêmes endpoints, mêmes paramètres, même
// stratégie d'authentification (jeton, puis repli anonyme sur 401) qu'avant le découpage.
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/models/hero_slide_model.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'home_models.dart';

class HomeDataSource {
  HomeDataSource(this._api);

  final BaseApi _api;

  Future<List<Category>> fetchCategories() async {
    final uri = Uri.parse('${_api.baseUrl}${AppConstants.categoriesEndpoint}/')
        .replace(queryParameters: {'page_size': '100', 'is_active': 'true'});

    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);

    final decoded = _api.decodeBody(r);
    final list = _api.extractResults(decoded);
    return list.map<Category>((e) => Category.fromJson(e)).toList();
  }

  /// Services de la sélection (tri / catégorie / recherche), ou proches de [position]
  /// quand [onlyNearby] est actif et que la position est connue.
  Future<List<HomeServiceEntry>> fetchServices({
    required String ordering,
    required String searchText,
    required bool onlyNearby,
    required double radiusKm,
    Category? category,
    Position? position,
  }) async {
    if (onlyNearby && position != null) {
      final uri =
          Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/nearby/')
              .replace(queryParameters: {
        'lat': '${position.latitude}',
        'lng': '${position.longitude}',
        'radius_km': '$radiusKm',
        'page_size': '12',
        if (category != null) 'category_id': category.id,
        if (searchText.trim().isNotEmpty) 'search': searchText.trim(),
      });
      return _fetchServiceList(uri);
    }

    final qp = <String, String>{
      'is_active': 'true',
      'page_size': '12',
      'ordering': ordering,
      if (category != null) 'category': category.id,
      if (searchText.trim().isNotEmpty) 'search': searchText.trim(),
    };

    final uri = Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/')
        .replace(queryParameters: qp);
    return _fetchServiceList(uri);
  }

  Future<List<HomeServiceEntry>> fetchNearby(
    Position position, {
    required double radiusKm,
    Category? category,
  }) async {
    final uri =
        Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/nearby/')
            .replace(queryParameters: {
      'lat': '${position.latitude}',
      'lng': '${position.longitude}',
      'radius_km': '$radiusKm',
      'page_size': '12',
      if (category != null) 'category_id': category.id,
    });
    return _fetchServiceList(uri);
  }

  Future<List<HeroSlideModel>> fetchSlides() async {
    final uri = Uri.parse('${_api.baseUrl}/slides/');
    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);
    final decoded = _api.decodeBody(r);

    final dynamic payload =
        decoded is Map<String, dynamic> ? (decoded['results'] ?? []) : decoded;

    return (payload as List)
        .map((e) => HeroSlideModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<HomeServiceEntry>> _fetchServiceList(Uri uri) async {
    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);
    final decoded = _api.decodeBody(r);
    final list = _api.extractResults(decoded);
    return list.map<HomeServiceEntry>(_entryFromBackend).toList();
  }

  Future<http.Response> _getPublic(Uri uri) async {
    final client = _api.client;
    var r =
        await client.get(uri, headers: await _api.getHeaders(withAuth: true));
    if (r.statusCode == 401) {
      r = await client.get(uri,
          headers: await _api.getHeaders(withAuth: false));
    }
    return r;
  }

  HomeServiceEntry _entryFromBackend(dynamic json) {
    final map = (json as Map<String, dynamic>? ?? const {});
    return HomeServiceEntry(
      _serviceFromBackend(map),
      HomeArtisanBrief.fromServiceJson(map),
    );
  }

  Service _serviceFromBackend(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString();
    final title = (map['title'] ?? '') as String? ?? '';
    final description = (map['description'] ?? '') as String? ?? '';

    final catDetail = (map['category_detail'] as Map?) ?? {};
    final categoryName =
        (catDetail['name'] ?? map['category_name'] ?? '').toString();

    final priceStr = (map['price'] ?? '0').toString();
    final price = double.tryParse(priceStr) ?? 0.0;

    final durationMinutes = (map['duration'] is int)
        ? (map['duration'] as int)
        : int.tryParse('${map['duration'] ?? 0}') ?? 0;

    String pickedImage = (map['image_url'] ?? '').toString();
    if (pickedImage.isEmpty) pickedImage = (map['banner'] ?? '').toString();
    if (pickedImage.isEmpty) {
      final images = (map['images'] as List?) ?? const [];
      if (images.isNotEmpty) {
        final first = (images.first as Map?) ?? {};
        pickedImage = (first['image'] ?? first['url'] ?? '').toString();
      }
    }
    final imageUrl = homeFixMediaUrl(pickedImage);

    return Service(
      id: id,
      title: title,
      description: description,
      category: categoryName,
      imageUrl: imageUrl,
      price: price,
      rating: 0,
      discountedPrice: null,
      duration: Duration(minutes: durationMinutes),
      isUrgent: false,
      includedServices: const [],
      requiredTools: const [],
      priceType: (map['price_type'] ?? '').toString(),
      handymanId: (map['handyman'] ?? '').toString(),
      categoryId: (map['category'] ?? '').toString(),
      categoryName: categoryName,
      isActive: (map['is_active'] ?? false) == true,
      createdAt:
          DateTime.tryParse('${map['created_at'] ?? ''}') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse('${map['updated_at'] ?? ''}') ?? DateTime.now(),
    );
  }
}
