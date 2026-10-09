// lib/screens/all_nearby_artisans_screen.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/browse/browse_parts.dart';
import 'package:flutter_tratra/services/location_service.dart';

class AllNearbyArtisansScreen extends StatefulWidget {
  const AllNearbyArtisansScreen({super.key});

  @override
  State<AllNearbyArtisansScreen> createState() =>
      _AllNearbyArtisansScreenState();
}

class _AllNearbyArtisansScreenState extends State<AllNearbyArtisansScreen> {
  /// Valeur historique transmise telle quelle à la fiche service quand l'API ne
  /// fournit pas d'image (arguments de navigation inchangés). Jamais affichée :
  /// `BrowseImage` la traite comme « pas d'image » et montre le repli de marque.
  static const _placeholder =
      'https://via.placeholder.com/300x200?text=Service';

  late final BaseApi _api;
  final LocationService _location = LocationService();

  bool _loading = true;
  bool _locating = true; // affichage seul : bouton « Réessayer » en cours
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
    if (!_locating) setState(() => _locating = true);
    try {
      _pos = await _location
          .getCurrentLocation()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      _pos = null;
    }
    if (!mounted) return;
    _locating = false;
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

    // Image : on ne prend QUE image_url ; si vide/invalide → valeur historique.
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

  /// Utilise uniquement `image_url`. Si vide/invalide → valeur historique.
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

  /// Libellé de prix fidèle au type de tarification renvoyé par l'API.
  String _priceText(Service s) {
    if (s.priceType == 'quote') return 'Sur devis';
    final amount = s.price ?? 0;
    if (amount <= 0) return 'Prix à confirmer';
    final digits = amount.toStringAsFixed(0);
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    return s.priceType == 'hourly'
        ? '$grouped FCFA/h'
        : '$grouped FCFA';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(
        title: 'Artisans à proximité',
        subtitle: _pos != null
            ? 'Dans un rayon de ${_radiusKm.toStringAsFixed(0)} km'
            : null,
      ),
      body: RefreshIndicator(
        color: TtColors.primaryDark,
        backgroundColor: TtColors.surface,
        onRefresh: _load,
        child: _buildBody(),
      ),
      bottomNavigationBar: _pos == null
          ? _LocationHint(onRetry: _init, loading: _locating)
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) return const _NearbySkeleton();

    if (_error != null) {
      return BrowseCenteredScroll(
        key: const ValueKey('nearby-error'),
        child: TratraEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Chargement impossible',
          description: browseErrorMessage(_error),
          actions: [
            TratraButton(
              label: 'Réessayer',
              leading: const Icon(Icons.refresh_rounded),
              // Sans position, on relance aussi la localisation (pas seulement la requête).
              onPressed: _pos == null ? _init : _load,
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      final located = _pos != null;
      return BrowseCenteredScroll(
        key: const ValueKey('nearby-empty'),
        child: TratraEmptyState(
          icon: located ? Icons.near_me_outlined : Icons.location_off_outlined,
          title: 'Aucun artisan trouvé',
          description: located
              ? 'Aucun service n’est proposé dans un rayon de ${_radiusKm.toStringAsFixed(0)} km autour de vous pour le moment.'
              : 'Nous n’avons pas pu vous localiser. Activez la localisation, ou parcourez le catalogue sans limite de zone.',
          actions: [
            TratraButton(
              label: 'Parcourir les catégories',
              leading: const Icon(Icons.category_outlined),
              onPressed: () =>
                  Navigator.pushNamed(context, RouteNames.allCategories),
            ),
            TratraButton(
              label: 'Voir tous les services',
              variant: TratraButtonVariant.outline,
              onPressed: () =>
                  Navigator.pushNamed(context, RouteNames.allServices),
            ),
          ],
        ),
      );
    }

    return BrowseFadeIn(
      key: const ValueKey('nearby-list'),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          TtSpace.s4,
          TtSpace.s4,
          TtSpace.s4,
          TtSpace.s6 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s3),
        itemBuilder: (_, i) {
          final s = _items[i];
          return _ArtisanRowCard(
            title: s.title.isNotEmpty ? s.title : 'Service proche',
            subtitle: s.categoryName.isNotEmpty ? s.categoryName : 'Proximité',
            priceText: _priceText(s),
            imageUrl: s.imageUrl,
            isUrgent: s.isUrgent,
            onTap: () => Navigator.pushNamed(
              context,
              RouteNames.serviceDetail,
              arguments: ServiceDetailArgs(s),
            ),
          );
        },
      ),
    );
  }
}

class _ArtisanRowCard extends StatelessWidget {
  const _ArtisanRowCard({
    required this.title,
    required this.subtitle,
    required this.priceText,
    required this.imageUrl,
    required this.isUrgent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String priceText;
  final String imageUrl;
  final bool isUrgent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      radius: TtRadius.panel,
      padding: const EdgeInsets.all(TtSpace.s3),
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: TtRadius.controlAll,
            child: BrowseImage(
              url: imageUrl,
              fallbackIcon: Icons.home_repair_service_outlined,
              width: 88,
              height: 88,
            ),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: TtSpace.s2,
                  runSpacing: TtSpace.s1,
                  children: [
                    TratraBadge(subtitle),
                    if (isUrgent)
                      const TratraBadge(
                        'Urgent',
                        tone: TratraTone.accent,
                        icon: Icons.bolt_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: TtSpace.s2),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h3)
                      .copyWith(fontSize: 15, height: 1.25),
                ),
                const SizedBox(height: TtSpace.s1),
                Text(
                  priceText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.title,
                          color: TtColors.primaryDark)
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: TtSpace.s2),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ],
      ),
    );
  }
}

// ===== Squelettes =====

class _NearbySkeleton extends StatelessWidget {
  const _NearbySkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement des services à proximité',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(TtSpace.s4),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s3),
            itemBuilder: (_, __) => const _NearbyRowSkeleton(),
          ),
        ),
      ),
    );
  }
}

class _NearbyRowSkeleton extends StatelessWidget {
  const _NearbyRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TtColors.surface,
        borderRadius: TtRadius.panelAll,
        border: Border.all(color: TtColors.lineSoft),
        boxShadow: TtShadows.soft,
      ),
      child: const Padding(
        padding: EdgeInsets.all(TtSpace.s3),
        child: Row(
          children: [
            TratraSkeletonBox(width: 88, height: 88),
            SizedBox(width: TtSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TratraSkeletonBox(width: 72, height: 18, radius: TtRadius.pill),
                  SizedBox(height: TtSpace.s3),
                  TratraSkeletonBox(height: 14),
                  SizedBox(height: TtSpace.s2),
                  TratraSkeletonBox(width: 120, height: 14),
                  SizedBox(height: TtSpace.s3),
                  TratraSkeletonBox(width: 90, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Bandeau de localisation =====

class _LocationHint extends StatelessWidget {
  const _LocationHint({required this.onRetry, required this.loading});

  final VoidCallback onRetry;

  /// Recherche de position en cours : le bouton affiche un spinner et ignore les appuis.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(top: BorderSide(color: TtColors.lineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(TtSpace.s3),
          child: TratraAlert(
            tone: TratraAlertTone.warning,
            icon: Icons.location_off_outlined,
            title: 'Position indisponible',
            message: 'Activez la localisation pour de meilleurs résultats.',
            action: Align(
              alignment: Alignment.centerLeft,
              child: TratraButton(
                label: 'Réessayer',
                variant: TratraButtonVariant.outline,
                size: TratraButtonSize.sm,
                loading: loading,
                onPressed: onRetry,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
