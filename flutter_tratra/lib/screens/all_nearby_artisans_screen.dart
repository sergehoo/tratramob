// lib/screens/all_nearby_artisans_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/services/location_service.dart';
import 'package:http/http.dart' as http;

class AllNearbyArtisansScreen extends StatefulWidget {
  const AllNearbyArtisansScreen({super.key});

  @override
  State<AllNearbyArtisansScreen> createState() =>
      _AllNearbyArtisansScreenState();
}

class _AllNearbyArtisansScreenState extends State<AllNearbyArtisansScreen> {
  // UI
  static const _card = Color(0xFFFFFFFF);
  static const _bg = Color(0xFFF8F9FA);
  static const _border = Color(0xFFE5E5E5);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);
  static const _placeholder =
      'https://via.placeholder.com/300x200?text=Service';

  late final BaseApi _api;
  final LocationService _location = LocationService();

  bool _loading = true;
  String? _error;
  List<Service> _items = [];
  Position? _pos;

  final double _radiusKm = 25;

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    _init();
  }

  Future<void> _init() async {
    try {
      _pos = await _location
          .getCurrentLocation()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      _pos = null;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri =
          Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/nearby/')
              .replace(queryParameters: {
        if (_pos != null) 'lat': '${_pos!.latitude}',
        if (_pos != null) 'lng': '${_pos!.longitude}',
        'radius_km': '$_radiusKm',
        'page_size': '60',
      });

      final r = await _getPublic(uri);
      if (r.statusCode != 200) _api.handleError(r);
      final decoded = _api.decodeBody(r);
      final list = _api.extractResults(decoded);

      _items = list.map<Service>(_serviceFromBackend).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Service _serviceFromBackend(dynamic json) {
    final m = (json as Map<String, dynamic>? ?? const {});

    final id = (m['id'] ?? '').toString();
    final title = (m['title'] ?? '') as String? ?? '';

    final categoryName =
        ((m['category_detail'] as Map?)?['name'] ?? m['category_name'] ?? '')
            .toString();

    // 🔒 Image: on ne prend QUE image_url ; si vide/invalide → placeholder.
    final imageUrl = _pickSafeImageUrl(m);

    final price = double.tryParse('${m['price'] ?? '0'}') ?? 0.0;

    return Service(
      id: id,
      title: title,
      description: (m['description'] ?? '').toString(),
      category: categoryName,
      imageUrl: imageUrl,
      price: price,
      rating: 0,
      discountedPrice: null,
      duration: const Duration(),
      isUrgent: (m['is_urgent'] ?? false) == true,
      includedServices: const [],
      requiredTools: const [],
      priceType: (m['price_type'] ?? '').toString(),
      handymanId: '${m['handyman'] ?? ''}',
      categoryId: '${m['category'] ?? ''}',
      categoryName: categoryName,
      isActive: (m['is_active'] ?? true) == true,
      createdAt:
          DateTime.tryParse('${m['created_at'] ?? ''}') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse('${m['updated_at'] ?? ''}') ?? DateTime.now(),
    );
  }

  /// Utilise uniquement `image_url`. Si vide/invalide → placeholder.
  String _pickSafeImageUrl(Map<String, dynamic> m) {
    final raw = (m['image_url'] ?? '').toString().trim();
    if (raw.isEmpty) return _placeholder;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return _placeholder;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Artisans à proximité'),
        backgroundColor: _card,
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Erreur : $_error',
                          style: const TextStyle(color: Colors.red)),
                    )
                  ])
                : (_items.isEmpty)
                    ? ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Aucun artisan trouvé')),
                        SizedBox(height: 120),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final s = _items[i];
                          return _ArtisanRowCard(
                            title:
                                s.title.isNotEmpty ? s.title : 'Service proche',
                            subtitle: s.categoryName.isNotEmpty
                                ? s.categoryName
                                : 'Proximité',
                            priceText:
                                '${(s.price ?? 0).toStringAsFixed(0)} FCFA/h',
                            imageUrl: s.imageUrl.isNotEmpty
                                ? s.imageUrl
                                : _placeholder,
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.serviceDetail,
                              arguments: ServiceDetailArgs(s),
                            ),
                          );
                        },
                      ),
      ),
      bottomNavigationBar: _pos == null ? _LocationHint(onRetry: _init) : null,
    );
  }
}

class _ArtisanRowCard extends StatelessWidget {
  const _ArtisanRowCard({
    required this.title,
    required this.subtitle,
    required this.priceText,
    required this.imageUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String priceText;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFFE5E5E5);
    const card = Color(0xFFFFFFFF);
    const textPrimary = Color(0xFF1E272E);
    const textSecondary = Color(0xFF636E72);
    const accent = Color(0xFF00B14F);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(width: 90, height: 90, color: Colors.black12),
                errorWidget: (_, __, ___) => Container(
                  width: 90,
                  height: 90,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(priceText,
                        style: const TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationHint extends StatelessWidget {
  const _LocationHint({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFF3CD),
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF856404)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Activez la localisation pour de meilleurs résultats.',
                style: TextStyle(color: Color(0xFF856404)),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
