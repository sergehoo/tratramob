// lib/screens/home_screen.dart
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/models/hero_slide_model.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ====== Palette (Premium / Material3 friendly) ======
  static const _bg = Color(0xFFF7F8FA);
  static const _card = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF00B14F);
  static const _accentDark = Color(0xFF008E40);
  static const _accentYellow = Color(0xFFFFC107);
  static const _textPrimary = Color(0xFF0F172A);
  static const _textSecondary = Color(0xFF64748B);
  static const _border = Color(0xFFE7E9EE);
  static const _promo = Color(0xFFFF5252);
  static const _rating = Color(0xFFFFA000);

  // ====== Carrousel Hero ======
  final List<_HeroSlide> _heroSlides = [];
  List<HeroSlideModel> _rawSlides = const [];

  // ====== Services réseau ======
  late final BaseApi _api;
  final LocationService _locationService = LocationService();

  // ====== State (données) ======
  List<Service> _services = [];
  List<Service> _nearby = [];
  List<Category> _categories = [];
  Position? _currentPosition;

  // ====== UI State ======
  int _heroIndex = 0;
  List<_UrgentItem> _urgentItems = [];
  bool _urgentLoading = true;

  String? _videoUrl;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showPromoBanner = true;

  final Map<String, bool> _favoriteServices = {};

  // ====== Filtres & recherche ======
  String _searchText = '';
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  Category? _selectedCategory;
  bool _onlyNearby = false;
  String _ordering = '-created_at';
  final double _nearbyRadiusKm = 15;

  // ====== Navigation state ======
  int _navIndex = 0;

  // ====== Mapping d’icônes ======
  static const Map<String, IconData> _slugToMaterial = {
    'plomberie': Icons.plumbing,
    'electricite': Icons.electrical_services,
    'électricité': Icons.electrical_services,
    'peinture': Icons.format_paint,
    'menuiserie': Icons.carpenter,
    'nettoyage': Icons.cleaning_services,
    'demenagement': Icons.local_shipping,
    'déménagement': Icons.local_shipping,
    'jardinage': Icons.yard_outlined,
    'bricolage': Icons.build,
    'informatique': Icons.computer,
    'carrelage': Icons.grid_on,
  };

  static const Map<String, IconData> _faMap = {
    'fa-road': FontAwesomeIcons.road,
    'fa-music': FontAwesomeIcons.music,
    'fa-laptop-code': FontAwesomeIcons.laptopCode,
    'fa-tools': FontAwesomeIcons.screwdriverWrench,
    'fa-border-style': FontAwesomeIcons.borderAll,
    'fa-wrench': FontAwesomeIcons.wrench,
    'fa-hammer': FontAwesomeIcons.hammer,
    'fa-broom': FontAwesomeIcons.broom,
    'fa-truck': FontAwesomeIcons.truck,
    'fa-brush': FontAwesomeIcons.brush,
    'fa-leaf': FontAwesomeIcons.leaf,
    'fa-bolt': FontAwesomeIcons.boltLightning,
    'fa-tree': FontAwesomeIcons.tree,
    'fa-paint-roller': FontAwesomeIcons.paintRoller,
    'fa-screwdriver-wrench': FontAwesomeIcons.screwdriverWrench,
    'fa-house': FontAwesomeIcons.house,
  };

  static const List<Color> _palette = [
    Color(0xFF2196F3),
    _accentYellow,
    Color(0xFF9C27B0),
    Color(0xFF795548),
    Color(0xFF00BCD4),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFF9E9E9E),
  ];

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  //                        DATA (GARDÉE)
  //  -> Tu peux conserver tes méthodes existantes telles quelles.
  // =========================================================

  Future<void> _loadData() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
      });

      try {
        _currentPosition = await _locationService
            .getCurrentLocation()
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        _currentPosition = null;
      }

      final futures = <Future>[
        _fetchCategories(),
        _fetchServicesFiltered(),
        if (_currentPosition != null)
          _fetchServicesNearby(_currentPosition!)
        else
          Future.value(<Service>[]),
      ];

      final results = await Future.wait(futures);
      if (!mounted) return;

      _categories = results[0] as List<Category>;
      _services = results[1] as List<Service>;
      _nearby = results[2] as List<Service>;

      final slides = await _fetchSlides();
      _rawSlides = slides;
      _heroSlides
        ..clear()
        ..addAll(slides.map((s) => _HeroSlide(
              title: s.title,
              subtitle: s.subtitle,
              image: fixMediaUrl(s.image),
              gradient: _parseHexToColorList(s.gradient),
              ctaLabel: s.ctaLabel,
              onTap: () => _handleCta(s.ctaAction, s.ctaParams),
            )));

      await _loadUrgentSummary();

      _videoUrl = null;
      if ((_videoUrl ?? '').isNotEmpty) {
        _videoController =
            VideoPlayerController.networkUrl(Uri.parse(_videoUrl!));
        await _videoController!.initialize();
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: false,
          looping: false,
          allowMuting: true,
          materialProgressColors: ChewieProgressColors(),
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Category>> _fetchCategories() async {
    final uri = Uri.parse('${_api.baseUrl}${AppConstants.categoriesEndpoint}/')
        .replace(queryParameters: {'page_size': '100', 'is_active': 'true'});

    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);

    final decoded = _api.decodeBody(r);
    final list = _api.extractResults(decoded);
    return list.map<Category>((e) => Category.fromJson(e)).toList();
  }

  Future<List<Service>> _fetchServicesFiltered() async {
    if (_onlyNearby && _currentPosition != null) {
      final uri =
          Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/nearby/')
              .replace(queryParameters: {
        'lat': '${_currentPosition!.latitude}',
        'lng': '${_currentPosition!.longitude}',
        'radius_km': '$_nearbyRadiusKm',
        'page_size': '12',
        if (_selectedCategory != null)
          'category_id': _selectedCategory!.id,
        if (_searchText.trim().isNotEmpty) 'search': _searchText.trim(),
      });

      final r = await _getPublic(uri);
      if (r.statusCode != 200) _api.handleError(r);
      final decoded = _api.decodeBody(r);
      final list = _api.extractResults(decoded);
      return list.map<Service>(_serviceFromBackend).toList();
    }

    final qp = <String, String>{
      'is_active': 'true',
      'page_size': '12',
      'ordering': _ordering,
      if (_selectedCategory != null) 'category': _selectedCategory!.id,
      if (_searchText.trim().isNotEmpty) 'search': _searchText.trim(),
    };

    final uri = Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/')
        .replace(queryParameters: qp);

    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);
    final decoded = _api.decodeBody(r);
    final list = _api.extractResults(decoded);
    return list.map<Service>(_serviceFromBackend).toList();
  }

  Future<List<Service>> _fetchServicesNearby(Position pos) async {
    final uri =
        Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/nearby/')
            .replace(queryParameters: {
      'lat': '${pos.latitude}',
      'lng': '${pos.longitude}',
      'radius_km': '$_nearbyRadiusKm',
      'page_size': '12',
      if (_selectedCategory != null) 'category_id': _selectedCategory!.id,
    });

    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);
    final decoded = _api.decodeBody(r);
    final list = _api.extractResults(decoded);
    return list.map<Service>(_serviceFromBackend).toList();
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
    final map = (json as Map<String, dynamic>? ?? const {});
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
    final imageUrl = fixMediaUrl(pickedImage);

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

  List<Color> _parseHexToColorList(List<String> hexes) {
    Color fromHex(String h) {
      final v = h.replaceAll('#', '');
      if (v.length == 3) {
        final r = v[0], g = v[1], b = v[2];
        return Color(int.parse('FF$r$r$g$g$b$b', radix: 16));
      }
      if (v.length == 6) return Color(int.parse('FF$v', radix: 16));
      return const Color(0xFF00B14F);
    }

    if (hexes.length >= 2) return [fromHex(hexes[0]), fromHex(hexes[1])];
    return const [Color(0xFF00B14F), Color(0xFF00D25F)];
  }

  Future<List<HeroSlideModel>> _fetchSlides() async {
    final uri = Uri.parse('${_api.baseUrl}/slides/');
    final r = await _getPublic(uri);
    if (r.statusCode != 200) _api.handleError(r);
    final decoded = _api.decodeBody(r);

    final dynamic payload =
        decoded is Map<String, dynamic> ? (decoded['results'] ?? []) : decoded;

    final list = (payload as List)
        .map((e) => HeroSlideModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return list;
  }

  void _handleCta(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'open_category':
        final id = params['category_id'];
        if (id != null && _categories.isNotEmpty) {
          final cat = _categories.firstWhere(
            (c) => c.id == id.toString() || c.id == id,
            orElse: () => _categories.first,
          );
          _onSelectCategory(cat);
        } else {
          _showAllCategories();
        }
        break;
      case 'open_categories':
        _showAllCategories();
        break;
      case 'open_artisans':
        _showPopularArtisans();
        break;
      case 'open_services':
        _showAllServices();
        break;
      case 'open_url':
        final url = params['url']?.toString();
        if (url != null && url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Impossible d’ouvrir le lien'),
            ));
          }
        }
        break;
      default:
        _showAllServices();
        break;
    }
  }

  Future<void> _loadUrgentSummary() async {
    if (!mounted) return;
    setState(() => _urgentLoading = true);
    try {
      final Map<String, List<Service>> byCat = {};
      for (final s in _services) {
        final key = (s.categoryId).toLowerCase();
        byCat.putIfAbsent(key, () => []).add(s);
      }
      final top = byCat.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      final top3 = top.take(3).toList();

      final List<_UrgentItem> items = [];
      for (var i = 0; i < top3.length; i++) {
        final catKey = top3[i].key;
        final display = _displayCategoryName(catKey);
        final color = _palette[i % _palette.length];
        final icon = _slugToMaterial[catKey] ?? Icons.home_repair_service;
        items.add(_UrgentItem(
          title: '$display urgent',
          subtitle: 'Intervention rapide • ${top3[i].value.length} pros dispo',
          icon: icon,
          color: color,
          available: top3[i].value.length,
        ));
      }
      if (mounted) setState(() => _urgentItems = items);
    } finally {
      if (mounted) setState(() => _urgentLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    await _reloadWithFilters();
    try {
      final slides = await _fetchSlides();
      _rawSlides = slides;
      _heroSlides
        ..clear()
        ..addAll(slides.map((s) => _HeroSlide(
              title: s.title,
              subtitle: s.subtitle,
              image: fixMediaUrl(s.image),
              gradient: _parseHexToColorList(s.gradient),
              ctaLabel: s.ctaLabel,
              onTap: () => _handleCta(s.ctaAction, s.ctaParams),
            )));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _reloadWithFilters() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final services = await _fetchServicesFiltered();
      List<Service> nearby = _nearby;
      if (_currentPosition != null) {
        nearby = await _fetchServicesNearby(_currentPosition!);
      }

      if (!mounted) return;
      setState(() {
        _services = services;
        _nearby = nearby;
      });
      await _loadUrgentSummary();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSelectCategory(Category? c) {
    HapticFeedback.selectionClick();
    setState(() => _selectedCategory = c);
    _reloadWithFilters();
  }

  void _onToggleNearby(bool value) {
    HapticFeedback.selectionClick();
    setState(() => _onlyNearby = value);
    _reloadWithFilters();
  }

  void _onChangeOrdering(String value) {
    HapticFeedback.selectionClick();
    setState(() => _ordering = value);
    _reloadWithFilters();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchText = text);
      _reloadWithFilters();
    });
  }

  String _displayCategoryName(String raw) {
    if (raw.isEmpty) return 'Service';
    final lower = raw.toLowerCase();
    if (lower.contains('electric')) return 'Électricité';
    if (lower.contains('plomb')) return 'Plomberie';
    if (lower.contains('peint')) return 'Peinture';
    if (lower.contains('menuis')) return 'Menuiserie';
    if (lower.contains('demen') || lower.contains('démén')) {
      return 'Déménagement';
    }
    if (lower.contains('netto')) return 'Nettoyage';
    if (lower.contains('jardin')) return 'Jardinage';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  // =========================================================
  //                        UI (REFACTOR PREMIUM)
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_hasError) {
      return Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _ErrorState(
                message: _errorMessage,
                onRetry: _loadData,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            _PremiumAppBar(
              accent: _accent,
              title: 'Tratra Pro',
              locationText: _currentPosition == null
                  ? 'Abidjan'
                  : 'Lat ${_currentPosition!.latitude.toStringAsFixed(3)} • '
                      'Lng ${_currentPosition!.longitude.toStringAsFixed(3)}',
              onLocationTap: _onChangeLocation,
              onNotifTap: _onOpenNotificationsStatic,
              onProfileTap: () {},
              searchController: _searchCtrl,
              onSearchChanged: _onSearchChanged,
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _isLoading
                      ? const _SkeletonHero(height: 190)
                      : _heroSlides.isEmpty
                          ? _TrustBanner(
                              accent: _accent,
                              title: 'Trouvez un artisan fiable près de vous',
                              subtitle:
                                  'Des pros vérifiés • Paiement sécurisé • Support',
                              primaryLabel: 'Trouver un pro',
                              secondaryLabel: 'Urgence',
                              onPrimary: _showAllServices,
                              onSecondary: _showAllUrgentServices,
                            )
                          : _HeroSection(
                              slides: _heroSlides,
                              index: _heroIndex,
                              onIndexChanged: (i) =>
                                  setState(() => _heroIndex = i),
                              accent: _accent,
                            ),
                ),
              ),
            ),

            // Filters: catégories + nearby + ordering
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: _FilterPanel(
                  accent: _accent,
                  accentDark: _accentDark,
                  card: _card,
                  border: _border,
                  textPrimary: _textPrimary,
                  textSecondary: _textSecondary,
                  categories: _categories,
                  selected: _selectedCategory,
                  onlyNearby: _onlyNearby,
                  canNearby: _currentPosition != null,
                  ordering: _ordering,
                  onSelectCategory: _onSelectCategory,
                  onToggleNearby: _onToggleNearby,
                  onChangeOrdering: _onChangeOrdering,
                ),
              ),
            ),

            if (_showPromoBanner)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _PromoCard(
                    accent: _accent,
                    yellow: _accentYellow,
                    onClose: () => setState(() => _showPromoBanner = false),
                    onUseCode: _usePromoCode,
                    onShare: () =>
                        Share.share('Je viens d’économiser 20% sur Tratra 🎉'),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _QuickActionsRow(
                  accent: _accent,
                  urgentColor: _promo,
                  onUrgent: _showAllUrgentServices,
                  onQuote: _showAllServices,
                  onNearby: _showAllArtisans,
                  onVerified: _showPopularArtisans,
                ),
              ),
            ),

            _SectionHeaderSliver(
              title: 'Urgence',
              subtitle: 'Interventions rapides, disponibles maintenant',
              action: 'Voir tout',
              onTap: _showAllUrgentServices,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 0, 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _urgentLoading
                      ? const _SkeletonRow(height: 122)
                      : _urgentItems.isEmpty
                          ? const _EmptyCard(
                              title: 'Aucune urgence disponible',
                              subtitle:
                                  'Essayez une autre catégorie ou élargissez le rayon.',
                            )
                          : SizedBox(
                              height: 122,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _urgentItems.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) {
                                  final it = _urgentItems[i];
                                  return _UrgentCard(
                                    title: it.title,
                                    subtitle: it.subtitle,
                                    icon: it.icon,
                                    color: it.color,
                                    onTap: _showAllUrgentServices,
                                  );
                                },
                              ),
                            ),
                ),
              ),
            ),

            _SectionHeaderSliver(
              title: 'Catégories',
              subtitle: 'Choisissez un métier',
              action: 'Tout voir',
              onTap: _showAllCategories,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 0, 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _isLoading
                      ? const _SkeletonRow(height: 140)
                      : _categories.isEmpty
                          ? const _EmptyCard(
                              title: 'Aucune catégorie',
                              subtitle:
                                  'Vérifiez votre connexion ou réessayez.',
                            )
                          : SizedBox(
                              height: 140,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _categories.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) {
                                  final c = _categories[i];
                                  final slug = (c.slug).toLowerCase();
                                  final color = _palette[i % _palette.length];
                                  final image = (c.imageUrl.isNotEmpty)
                                      ? fixMediaUrl(c.imageUrl)
                                      : 'https://via.placeholder.com/600x400?text=Category';

                                  Widget iconWidget =
                                      _buildCategoryIconFromApi(c.icon, color);
                                  if (iconWidget is Icon &&
                                      (iconWidget.icon == Icons.category)) {
                                    iconWidget = Icon(
                                        _materialIconForSlug(slug),
                                        color: Colors.white,
                                        size: 22);
                                  }

                                  return _CategoryCardPremium(
                                    title: c.name,
                                    imageUrl: image,
                                    color: color,
                                    icon: iconWidget,
                                    onTap: () => _onSelectCategory(c),
                                  );
                                },
                              ),
                            ),
                ),
              ),
            ),

            _SectionHeaderSliver(
              title: 'Pros à proximité',
              subtitle: _currentPosition == null
                  ? 'Activez la localisation pour voir les pros proches'
                  : 'Meilleurs pros autour de vous',
              action: 'Voir tout',
              onTap: _showAllArtisans,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 0, 4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _isLoading
                      ? const _SkeletonRow(height: 270)
                      : _nearby.isEmpty
                          ? const _EmptyCard(
                              title: 'Aucun pro à proximité',
                              subtitle:
                                  'Élargissez le rayon ou réessayez plus tard.',
                            )
                          : SizedBox(
                              height: 270,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _nearby.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) {
                                  final s = _nearby[i];
                                  final img = s.imageUrl.isNotEmpty
                                      ? fixMediaUrl(s.imageUrl)
                                      : 'https://via.placeholder.com/600x400?text=Pro';

                                  return ArtisanCardPremium(
                                    title: s.title.isNotEmpty
                                        ? s.title
                                        : 'Artisan proche',
                                    subtitle: s.categoryName.isNotEmpty
                                        ? s.categoryName
                                        : 'Proximité',
                                    imageUrl: img,
                                    priceText:
                                        '${(s.price ?? 0).toStringAsFixed(0)} FCFA/h',
                                    isFavorite:
                                        _favoriteServices[s.id] ?? false,
                                    onFavorite: () =>
                                        _toggleFavoriteService(s.id),
                                    onShare: () => _shareService(s),
                                    onPrimary: () =>
                                        _navigateToServiceDetail(s),
                                    badgeText: 'Vérifié',
                                  );
                                },
                              ),
                            ),
                ),
              ),
            ),

            _SectionHeaderSliver(
              title: 'Services populaires',
              subtitle: 'Les plus réservés',
              action: 'Voir tout',
              onTap: _showAllServices,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 0, 22),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _isLoading
                      ? const _SkeletonRow(height: 320)
                      : _services.isEmpty
                          ? const _EmptyCard(
                              title: 'Aucun service',
                              subtitle: 'Essayez une autre catégorie.',
                            )
                          : SizedBox(
                              height: 320,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _services.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, i) {
                                  final s = _services[i];
                                  final img = s.imageUrl.isNotEmpty
                                      ? fixMediaUrl(s.imageUrl)
                                      : 'https://via.placeholder.com/600x400?text=Service';

                                  final isFav =
                                      _favoriteServices[s.id] ?? false;

                                  return ServiceCardPremium(
                                    title: s.title.isNotEmpty
                                        ? s.title
                                        : 'Service',
                                    category: s.categoryName.isNotEmpty
                                        ? s.categoryName
                                        : 'Divers',
                                    imageUrl: img,
                                    basePrice: (s.price ?? 0).toDouble(),
                                    discountedPrice:
                                        (s.discountedPrice ?? s.price ?? 0)
                                            .toDouble(),
                                    rating: (s.rating ?? 4.8).toDouble(),
                                    isFavorite: isFav,
                                    onFavorite: () =>
                                        _toggleFavoriteService(s.id),
                                    onShare: () => _shareService(s),
                                    onTap: () => _navigateToServiceDetail(s),
                                    onBook: () => Navigator.pushNamed(
                                      context,
                                      RouteNames.booking,
                                      arguments: BookingArgs(s),
                                    ),
                                    badgeText:
                                        (s.isUrgent == true) ? 'Urgent' : null,
                                  );
                                },
                              ),
                            ),
                ),
              ),
            ),

            if (_chewieController != null) ...[
              _SectionHeaderSliver(
                title: 'En vidéo',
                subtitle: 'Découvrir comment ça marche',
                action: 'Lecture',
                onTap: () {},
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
                  child: _VideoCard(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio == 0
                          ? 16 / 9
                          : _videoController!.value.aspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Chewie(controller: _chewieController!),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            SliverToBoxAdapter(
                child: SizedBox(
                    height: theme.platform == TargetPlatform.iOS ? 24 : 10)),
          ],
        ),
      ),

      // Premium nav (Material 3)
      bottomNavigationBar: _PremiumBottomNav(
        index: _navIndex,
        accent: _accent,
        onChanged: (i) => setState(() => _navIndex = i),
      ),

      floatingActionButton: _PremiumFab(
        accent: _accent,
        onTap: _createQuickRequest,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // =========================================================
  //                   ACTIONS / NAV / HELPERS
  // =========================================================

  static void _onOpenNotificationsStatic() {}

  void _shareService(Service s) {
    final txt =
        'Regarde ce service "${s.title}" sur Tratra 🔧 ${(s.price ?? 0).toStringAsFixed(0)} FCFA';
    Share.share(txt);
  }

  void _toggleFavoriteService(String id) {
    HapticFeedback.lightImpact();
    setState(() => _favoriteServices[id] = !(_favoriteServices[id] ?? false));
  }

  void _usePromoCode() {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Code promo BIENVENUE appliqué !'),
      backgroundColor: _accent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _createQuickRequest() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nouvelle demande',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choisissez un type d’intervention',
              style: TextStyle(color: _textSecondary),
            ),
            const SizedBox(height: 14),
            _QuickRequestTile(
              icon: Icons.plumbing,
              title: 'Plomberie',
              subtitle: 'Fuite, robinet, chauffe-eau…',
              accent: _accent,
              onTap: () => Navigator.pop(context),
            ),
            _QuickRequestTile(
              icon: Icons.electrical_services,
              title: 'Électricité',
              subtitle: 'Prises, tableau, panne…',
              accent: _accent,
              onTap: () => Navigator.pop(context),
            ),
            _QuickRequestTile(
              icon: Icons.home_repair_service,
              title: 'Dépannage urgent',
              subtitle: 'Intervention immédiate',
              accent: _promo,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ]),
        ),
      ),
    );
  }

  void _onChangeLocation() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Changer de localisation',
              style: TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.place),
              title: const Text('Abidjan • Cocody'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.place),
              title: const Text('Abidjan • Plateau'),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Utiliser ma position actuelle'),
            ),
          ]),
        ),
      ),
    );
  }

  void _showAllUrgentServices() {
    Navigator.pushNamed(context, RouteNames.allUrgentServices);
  }

  void _showAllCategories() {
    Navigator.pushNamed(context, RouteNames.allCategories);
  }

  void _showAllArtisans() {
    Navigator.pushNamed(context, RouteNames.allNearbyArtisans);
  }

  void _showAllServices() {
    Navigator.pushNamed(context, RouteNames.allServices);
  }

  void _showPopularArtisans() {}

  void _navigateToServiceDetail(Service service) {
    Navigator.pushNamed(context, RouteNames.serviceDetail,
        arguments: ServiceDetailArgs(service));
  }

  Widget _buildCategoryIconFromApi(String? apiIcon, Color color) {
    if (apiIcon != null && apiIcon.trim().isNotEmpty) {
      final parts = apiIcon.trim().split(RegExp(r'\s+'));
      final faName = parts.isNotEmpty ? parts.last : '';
      final iconData = _faMap[faName];
      if (iconData != null) {
        return FaIcon(iconData, color: Colors.white, size: 22);
      }
    }
    return const Icon(Icons.category, color: Colors.white, size: 22);
  }

  IconData _materialIconForSlug(String slug) =>
      _slugToMaterial[slug] ?? Icons.category;

  String fixMediaUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    var url = raw.trim();

    if (url.startsWith('/')) return 'https://minio.tratra.net$url';

    url = url.replaceFirst('http://minio:9000', 'https://minio.tratra.net');
    url = url.replaceFirst('https://minio:9000', 'https://minio.tratra.net');

    url = url.replaceFirst('http://tratra.net', 'https://minio.tratra.net');
    url = url.replaceFirst('https://tratra.net', 'https://minio.tratra.net');

    if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
    return url;
  }
}

// ===================== PREMIUM UI WIDGETS =====================

class _PremiumAppBar extends StatelessWidget {
  const _PremiumAppBar({
    required this.accent,
    required this.title,
    required this.locationText,
    required this.onLocationTap,
    required this.onNotifTap,
    required this.onProfileTap,
    required this.searchController,
    required this.onSearchChanged,
  });

  final Color accent;
  final String title;
  final String locationText;
  final VoidCallback onLocationTap;
  final VoidCallback onNotifTap;
  final VoidCallback onProfileTap;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: _HomeScreenState._card,
      surfaceTintColor: Colors.white,
      elevation: 0,
      pinned: true,
      floating: false,
      expandedHeight: 138,
      collapsedHeight: 72,
      titleSpacing: 16,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Image.asset(
                'assets/images/tratra_logo_final.webp',
                width: 34,
                height: 34,
                errorBuilder: (_, __, ___) => const Icon(Icons.handyman,
                    color: _HomeScreenState._accent, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _HomeScreenState._textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: onLocationTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.place, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          locationText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _HomeScreenState._textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down,
                          size: 14, color: _HomeScreenState._textSecondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNotifTap,
            icon: const Icon(Icons.notifications_outlined,
                color: _HomeScreenState._textPrimary),
            tooltip: 'Notifications',
          ),
          IconButton(
            onPressed: onProfileTap,
            icon: const Icon(Icons.account_circle_outlined,
                color: _HomeScreenState._textPrimary),
            tooltip: 'Compte',
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SearchBarPremium(
            controller: searchController,
            onChanged: onSearchChanged,
            accent: accent,
          ),
        ),
      ),
    );
  }
}

class SearchBarPremium extends StatelessWidget {
  const SearchBarPremium({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.accent,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _HomeScreenState._border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: _HomeScreenState._textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: _HomeScreenState._textPrimary,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: accent,
              decoration: InputDecoration(
                hintText: 'Plombier, électricien, peinture…',
                hintStyle:
                    const TextStyle(color: _HomeScreenState._textSecondary),
                border: InputBorder.none,
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: _HomeScreenState._textSecondary),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                          HapticFeedback.selectionClick();
                        },
                      )
                    : null,
              ),
            ),
          ),
          const VerticalDivider(color: Colors.black12, width: 1, thickness: 1),
          const SizedBox(width: 8),
          const Tooltip(
            message: 'Scanner un code',
            child: Icon(Icons.qr_code_scanner,
                color: _HomeScreenState._textSecondary),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.slides,
    required this.index,
    required this.onIndexChanged,
    required this.accent,
  });

  final List<_HeroSlide> slides;
  final int index;
  final ValueChanged<int> onIndexChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CarouselSlider.builder(
          itemCount: slides.length,
          options: CarouselOptions(
            height: 190,
            viewportFraction: 0.92,
            enlargeCenterPage: true,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
            onPageChanged: (i, _) => onIndexChanged(i),
          ),
          itemBuilder: (_, i, __) {
            final s = slides[i];
            return InkWell(
              onTap: s.onTap,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    colors: s.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.08),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    )
                  ],
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(s.image),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.38),
                      BlendMode.darken,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        s.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: s.onTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: accent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.flash_on, size: 18),
                            label: Text(
                              s.ctaLabel,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _Pill(
                            text: 'Pros vérifiés',
                            icon: Icons.verified,
                            bg: Colors.white.withOpacity(.20),
                            fg: Colors.white,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 6,
              width: i == index ? 20 : 8,
              decoration: BoxDecoration(
                color: i == index ? accent : accent.withOpacity(0.25),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.accent,
    required this.accentDark,
    required this.card,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.categories,
    required this.selected,
    required this.onlyNearby,
    required this.canNearby,
    required this.ordering,
    required this.onSelectCategory,
    required this.onToggleNearby,
    required this.onChangeOrdering,
  });

  final Color accent;
  final Color accentDark;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  final List<Category> categories;
  final Category? selected;
  final bool onlyNearby;
  final bool canNearby;
  final String ordering;

  final ValueChanged<Category?> onSelectCategory;
  final ValueChanged<bool> onToggleNearby;
  final ValueChanged<String> onChangeOrdering;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // category chips
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              if (idx == 0) {
                final isSelected = selected == null;
                return ChoiceChip(
                  label: const Text('Toutes'),
                  selected: isSelected,
                  onSelected: (_) => onSelectCategory(null),
                  selectedColor: accent.withOpacity(.12),
                  labelStyle: TextStyle(
                    color: isSelected ? accentDark : textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                );
              }
              final c = categories[idx - 1];
              final isSelected = selected?.id == c.id;
              return ChoiceChip(
                label: Text(c.name, overflow: TextOverflow.ellipsis),
                selected: isSelected,
                onSelected: (_) => onSelectCategory(c),
                selectedColor: accent.withOpacity(.12),
                labelStyle: TextStyle(
                  color: isSelected ? accentDark : textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              );
            },
          ),
        ),

        const SizedBox(height: 10),

        // proximity + ordering
        Row(
          children: [
            InkWell(
              onTap: () => onToggleNearby(!onlyNearby),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.place,
                        color: onlyNearby ? accent : textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Proximité',
                      style: TextStyle(
                        color: onlyNearby ? accentDark : textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!canNearby)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.info_outline,
                            size: 16, color: _HomeScreenState._textSecondary),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: ordering,
                    icon: const Icon(Icons.unfold_more),
                    items: const [
                      DropdownMenuItem(
                          value: '-created_at', child: Text('Plus récents')),
                      DropdownMenuItem(
                          value: 'price', child: Text('Prix croissant')),
                      DropdownMenuItem(
                          value: '-price', child: Text('Prix décroissant')),
                    ],
                    onChanged: (v) => onChangeOrdering(v ?? '-created_at'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.accent,
    required this.yellow,
    required this.onClose,
    required this.onUseCode,
    required this.onShare,
  });

  final Color accent;
  final Color yellow;
  final VoidCallback onClose;
  final VoidCallback onUseCode;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, yellow],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                '🎉 Première commande',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '-20% avec le code BIENVENUE',
                style: TextStyle(
                    color: Colors.white.withOpacity(.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: onUseCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Utiliser le code',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share),
                    label: const Text('Partager'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.accent,
    required this.urgentColor,
    required this.onUrgent,
    required this.onQuote,
    required this.onNearby,
    required this.onVerified,
  });

  final Color accent;
  final Color urgentColor;
  final VoidCallback onUrgent;
  final VoidCallback onQuote;
  final VoidCallback onNearby;
  final VoidCallback onVerified;

  @override
  Widget build(BuildContext context) {
    final items = <_QuickActionPremium>[
      _QuickActionPremium(
        icon: Icons.flash_on,
        title: 'Urgence',
        subtitle: 'Intervenir vite',
        color: urgentColor,
        onTap: onUrgent,
      ),
      _QuickActionPremium(
        icon: Icons.calculate_outlined,
        title: 'Devis',
        subtitle: 'Estimer le coût',
        color: accent,
        onTap: onQuote,
      ),
      _QuickActionPremium(
        icon: Icons.place,
        title: 'Proches',
        subtitle: 'Autour de moi',
        color: Colors.indigo,
        onTap: onNearby,
      ),
      _QuickActionPremium(
        icon: Icons.verified,
        title: 'Vérifiés',
        subtitle: 'Pros certifiés',
        color: Colors.deepPurple,
        onTap: onVerified,
      ),
    ];

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final q = items[i];
          return _QuickActionCard(q: q);
        },
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.q});
  final _QuickActionPremium q;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        q.onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _HomeScreenState._card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _HomeScreenState._border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: q.color.withOpacity(.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(q.icon, color: q.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _HomeScreenState._textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    q.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _HomeScreenState._textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: _HomeScreenState._textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SectionHeaderSliver extends StatelessWidget {
  const _SectionHeaderSliver({
    required this.title,
    required this.subtitle,
    this.action,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _HomeScreenState._textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _HomeScreenState._textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ]),
            ),
            if (action != null)
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: const [
                      Text(
                        'Voir tout',
                        style: TextStyle(
                          color: _HomeScreenState._accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right,
                          size: 18, color: _HomeScreenState._accent),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UrgentCard extends StatelessWidget {
  const _UrgentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _HomeScreenState._card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _HomeScreenState._border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _HomeScreenState._textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _HomeScreenState._textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: _HomeScreenState._textSecondary),
          ],
        ),
      ),
    );
  }
}

class _CategoryCardPremium extends StatelessWidget {
  const _CategoryCardPremium({
    required this.title,
    required this.imageUrl,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String imageUrl;
  final Color color;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: _HomeScreenState._card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _HomeScreenState._border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              child: SizedBox(
                height: 84,
                width: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.grey.shade300),
                    ),
                    Container(color: Colors.black.withOpacity(.18)),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(child: icon),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _HomeScreenState._textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceCardPremium extends StatelessWidget {
  const ServiceCardPremium({
    super.key,
    required this.title,
    required this.category,
    required this.imageUrl,
    required this.basePrice,
    required this.discountedPrice,
    required this.rating,
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    required this.onTap,
    required this.onBook,
    this.badgeText,
  });

  final String title;
  final String category;
  final String imageUrl;
  final double basePrice;
  final double discountedPrice;
  final double rating;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onTap;
  final VoidCallback onBook;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = discountedPrice < basePrice;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: _HomeScreenState._card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _HomeScreenState._border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header image
            SizedBox(
              height: 140,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey.shade200),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(.10),
                            Colors.black.withOpacity(.35),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Row(
                      children: [
                        if (badgeText != null)
                          _BadgePill(
                              text: badgeText!, bg: _HomeScreenState._promo),
                        if (hasDiscount) ...[
                          if (badgeText != null) const SizedBox(width: 8),
                          const _BadgePill(
                              text: '- Promo', bg: _HomeScreenState._promo),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _BadgePill(
                      text: '⭐ ${rating.toStringAsFixed(1)}',
                      bg: Colors.white.withOpacity(.92),
                      fg: _HomeScreenState._rating,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        _CircleIconButton(
                          icon: isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          bg: Colors.white.withOpacity(.92),
                          fg: isFavorite
                              ? _HomeScreenState._promo
                              : _HomeScreenState._textPrimary,
                          onTap: onFavorite,
                        ),
                        const SizedBox(width: 8),
                        _CircleIconButton(
                          icon: Icons.share,
                          bg: Colors.white.withOpacity(.92),
                          fg: _HomeScreenState._accent,
                          onTap: onShare,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _HomeScreenState._textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _HomeScreenState._textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasDiscount)
                        Text(
                          '${basePrice.toStringAsFixed(0)} FCFA',
                          style: const TextStyle(
                            color: _HomeScreenState._textSecondary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      Text(
                        '${(hasDiscount ? discountedPrice : basePrice).toStringAsFixed(0)} FCFA',
                        style: const TextStyle(
                          color: _HomeScreenState._accentDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: onBook,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _HomeScreenState._accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Réserver',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArtisanCardPremium extends StatelessWidget {
  const ArtisanCardPremium({
    super.key,
    required this.title,
    required this.subtitle,
    required this.priceText,
    required this.imageUrl,
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    required this.onPrimary,
    this.badgeText,
  });

  final String title;
  final String subtitle;
  final String priceText;
  final String imageUrl;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onPrimary;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: _HomeScreenState._card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _HomeScreenState._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // image
          SizedBox(
            height: 130,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey.shade200),
                      errorWidget: (_, __, ___) =>
                          Container(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(.06),
                          Colors.black.withOpacity(.32),
                        ],
                      ),
                    ),
                  ),
                ),
                if (badgeText != null)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _BadgePill(
                        text: badgeText!, bg: _HomeScreenState._accent),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Row(
                    children: [
                      _CircleIconButton(
                        icon:
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                        bg: Colors.white.withOpacity(.92),
                        fg: isFavorite
                            ? _HomeScreenState._promo
                            : _HomeScreenState._textPrimary,
                        onTap: onFavorite,
                      ),
                      const SizedBox(width: 8),
                      _CircleIconButton(
                        icon: Icons.share,
                        bg: Colors.white.withOpacity(.92),
                        fg: _HomeScreenState._accent,
                        onTap: onShare,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _HomeScreenState._textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _HomeScreenState._textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Text(
                  priceText,
                  style: const TextStyle(
                    color: _HomeScreenState._textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _HomeScreenState._accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: onPrimary,
                  child: const Text('Contacter',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumBottomNav extends StatelessWidget {
  const _PremiumBottomNav({
    required this.index,
    required this.accent,
    required this.onChanged,
  });

  final int index;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: _HomeScreenState._card,
        indicatorColor: accent.withOpacity(.12),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onChanged,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil'),
          NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Recherche'),
          NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: 'Réservations'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat),
              label: 'Messages'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profil'),
        ],
      ),
    );
  }
}

class _PremiumFab extends StatelessWidget {
  const _PremiumFab({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.add),
      label:
          const Text('Demande', style: TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

// ===== Small premium atoms =====

class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.text,
    required this.bg,
    this.fg = Colors.white,
  });

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 20),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.text,
      required this.icon,
      required this.bg,
      required this.fg});
  final String text;
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _HomeScreenState._card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _HomeScreenState._border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _HomeScreenState._card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _HomeScreenState._border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _HomeScreenState._accent.withOpacity(.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                const Icon(Icons.info_outline, color: _HomeScreenState._accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: _HomeScreenState._textPrimary,
                      fontWeight: FontWeight.w900,
                    )),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _HomeScreenState._textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: height >= 260 ? 260 : 280,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _SkeletonHero extends StatelessWidget {
  const _SkeletonHero({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}

class _TrustBanner extends StatelessWidget {
  const _TrustBanner({
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final Color accent;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [accent, accent.withOpacity(.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                height: 1.1,
              )),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(.92),
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(primaryLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSecondary,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(secondaryLabel,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _QuickRequestTile extends StatelessWidget {
  const _QuickRequestTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: accent.withOpacity(.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: accent),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: _HomeScreenState._textSecondary)),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _HomeScreenState._card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _HomeScreenState._border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 36),
          const SizedBox(height: 10),
          const Text(
            'Une erreur est survenue',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _HomeScreenState._textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _HomeScreenState._textSecondary),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: _HomeScreenState._accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Réessayer',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

// ===================== INTERNAL TYPES =====================

class _UrgentItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int available;

  _UrgentItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.available,
  });
}

class _QuickActionPremium {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  _QuickActionPremium({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _HeroSlide {
  final String title;
  final String subtitle;
  final String image;
  final List<Color> gradient;
  final String ctaLabel;
  final VoidCallback onTap;

  _HeroSlide({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.gradient,
    required this.ctaLabel,
    required this.onTap,
  });
}
