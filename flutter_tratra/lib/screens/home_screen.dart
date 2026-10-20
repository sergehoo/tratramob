// lib/screens/home_screen.dart
//
// Accueil de l'app client. Ce fichier ne contient que l'état et les actions de l'écran ;
// l'interface (design system Tratra) est découpée dans lib/screens/home/.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/models/hero_slide_model.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/services/location_service.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'home/home_card_builders.dart';
import 'home/home_data.dart';
import 'home/home_filters.dart';
import 'home/home_hero.dart';
import 'home/home_models.dart';
import 'home/home_motion.dart';
import 'home/home_sections.dart';
import 'home/home_sheets.dart';
import 'home/home_slides.dart';

// Classes publiques historiques de cet écran : les imports existants continuent de fonctionner.
export 'home/home_cards.dart' show ArtisanCardPremium, ServiceCardPremium;
export 'home/home_hero.dart' show SearchBarPremium;

class HomeScreen extends StatefulWidget {
  /// `embedded` : onglet « Explorer » de l'espace unifié (la navigation basse est celle du tableau de bord).
  const HomeScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ====== Services réseau ======
  late final BaseApi _api;
  late final HomeDataSource _data;
  final LocationService _locationService = LocationService();

  // ====== État (données) ======
  List<HomeServiceEntry> _services = [];
  List<HomeServiceEntry> _nearby = [];
  List<Category> _categories = [];
  List<HeroSlideModel> _slides = const [];
  bool _slidesLoaded = false;
  Position? _currentPosition;

  // ====== État (interface) ======
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  final Map<String, bool> _favoriteServices = {};
  final ScrollController _scroll = ScrollController();

  // ====== Filtres & recherche ======
  String _searchText = '';
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  Category? _selectedCategory;
  bool _onlyNearby = false;
  String _ordering = '-created_at';
  final double _nearbyRadiusKm = 15;

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    _data = HomeDataSource(_api);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // =========================================================
  //                        DONNÉES
  // =========================================================

  Future<List<HomeServiceEntry>> _fetchServices() => _data.fetchServices(
        ordering: _ordering,
        searchText: _searchText,
        onlyNearby: _onlyNearby,
        radiusKm: _nearbyRadiusKm,
        category: _selectedCategory,
        position: _currentPosition,
      );

  Future<List<HomeServiceEntry>> _fetchNearby(Position pos) =>
      _data.fetchNearby(pos, radiusKm: _nearbyRadiusKm, category: _selectedCategory);

  /// Vrai après un premier chargement : les suivants (tirer pour actualiser, réessayer) redemandent le catalogue au serveur.
  bool _loadedOnce = false;

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

      final pos = _currentPosition;
      final results = await Future.wait<Object>([
        _data.fetchCategories(refresh: _loadedOnce),
        _fetchServices(),
        if (pos != null) _fetchNearby(pos) else Future.value(<HomeServiceEntry>[]),
      ]);
      if (!mounted) return;

      final categories = results[0] as List<Category>;
      final services = results[1] as List<HomeServiceEntry>;
      final nearby = results[2] as List<HomeServiceEntry>;

      final slides = await _data.fetchSlides();
      if (!mounted) return;

      _loadedOnce = true;
      setState(() {
        _categories = categories;
        _services = services;
        _nearby = nearby;
        _slides = slides;
        _slidesLoaded = true;
      });
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

  Future<void> _onRefresh() async {
    await _reloadWithFilters();
    try {
      final slides = await _data.fetchSlides();
      if (mounted) {
        setState(() {
          _slides = slides;
          _slidesLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _reloadWithFilters() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final services = await _fetchServices();
      var nearby = _nearby;
      final pos = _currentPosition;
      if (pos != null) {
        nearby = await _fetchNearby(pos);
      }

      if (!mounted) return;
      setState(() {
        _services = services;
        _nearby = nearby;
      });
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

  // =========================================================
  //                        ACTIONS
  // =========================================================

  Future<void> _handleCta(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'open_category':
        final id = params['category_id'];
        // Cible dans le catalogue complet (pas seulement les métiers mis en avant) ; introuvable → le catalogue entier plutôt qu'un autre métier.
        final cat = id == null ? null : _data.catalogCategory(id.toString());
        if (cat != null) {
          _onSelectCategory(cat);
        } else {
          _showAllCategories();
        }
        break;
      case 'open_categories':
        _showAllCategories();
        break;
      case 'open_artisans':
        _showAllArtisans();
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

  void _shareService(Service s) {
    final txt = 'Regarde ce service "${s.title}" sur Tratra 🔧 ${homePriceLabel(s)}';
    SharePlus.instance.share(ShareParams(text: txt));
  }

  void _toggleFavoriteService(String id) {
    HapticFeedback.lightImpact();
    setState(() => _favoriteServices[id] = !(_favoriteServices[id] ?? false));
  }

  void _createQuickRequest() {
    HapticFeedback.mediumImpact();
    showHomeQuickRequestSheet(
      context,
      categories: _categories,
      onCategory: _onSelectCategory,
      onUrgent: _showAllUrgentServices,
      onAllServices: _showAllServices,
    );
  }

  void _onChangeLocation() {
    showHomeLocationSheet(
      context,
      hasPosition: _currentPosition != null,
      onRefresh: _loadData,
    );
  }

  void _onNavTap(int index) {
    switch (index) {
      case 0:
        if (!_scroll.hasClients) return;
        if (homeReduceMotion(context)) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(0, duration: TtMotion.slow, curve: TtMotion.emphasized);
        }
      case 1:
        Navigator.pushNamed(context, RouteNames.search);
      case 2:
        Navigator.pushNamed(context, RouteNames.booking);
      case 3:
        Navigator.pushNamed(context, RouteNames.profile);
    }
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

  void _openProfile() {
    Navigator.pushNamed(context, RouteNames.profile);
  }

  void _navigateToServiceDetail(Service service) {
    Navigator.pushNamed(context, RouteNames.serviceDetail,
        arguments: ServiceDetailArgs(service));
  }

  void _openBooking(Service service) {
    Navigator.pushNamed(context, RouteNames.booking,
        arguments: BookingArgs(service));
  }

  // =========================================================
  //                        INTERFACE
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final firstName = context.select<Session, String?>((s) => s.user?.firstName);
    if (_hasError) return _buildError();

    final slides = [
      for (final s in _slides)
        HomeSlide(
          title: s.title,
          subtitle: s.subtitle,
          image: homeFixMediaUrl(s.image),
          ctaLabel: s.ctaLabel,
          onTap: () => _handleCta(s.ctaAction, s.ctaParams),
        ),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,              // icônes claires : sur le haut sombre du bandeau d'accueil comme sur le bandeau de défilement
        child: Stack(children: [
          RefreshIndicator(
            color: TtColors.primaryDark,
            backgroundColor: TtColors.surface,
            onRefresh: _onRefresh,
            child: CustomScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: HomeHero(
                    greetingName: firstName,
                    locationLabel: _currentPosition == null ? 'Position inactive' : 'Autour de moi',
                    locationActive: _currentPosition != null,
                    onLocationTap: _onChangeLocation,
                    onProfileTap: _openProfile,
                    searchController: _searchCtrl,
                    onSearchChanged: _onSearchChanged,
                    actions: [
                      HomeHeroAction(
                        icon: Icons.bolt_rounded,
                        label: 'Urgence',
                        accent: true,
                        onTap: _showAllUrgentServices,
                      ),
                      HomeHeroAction(icon: Icons.handyman_outlined, label: 'Services', onTap: _showAllServices),
                      HomeHeroAction(icon: Icons.near_me_rounded, label: 'Proches', onTap: _showAllArtisans),
                      HomeHeroAction(icon: Icons.grid_view_rounded, label: 'Catégories', onTap: _showAllCategories),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: TtSpace.s4),
                    child: HomeFilterPanel(
                      categories: _categories,
                      selected: _selectedCategory,
                      onlyNearby: _onlyNearby,
                      canNearby: _currentPosition != null,
                      ordering: _ordering,
                      onSelectCategory: _onSelectCategory,
                      onToggleNearby: _onToggleNearby,
                      onChangeOrdering: _onChangeOrdering,
                      onRetryLocation: _loadData,
                    ),
                  ),
                ),
                if (_isLoading && !_slidesLoaded)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: TtSpace.s5),
                      child: HomeSlidesSkeleton(),
                    ),
                  )
                else if (slides.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: TtSpace.s5),
                      child: HomeSlides(key: ValueKey(slides.length), slides: slides),
                    ),
                  ),
                SliverToBoxAdapter(child: HomeUrgentBanner(onTap: _showAllUrgentServices)),
                ..._categoriesSection(),
                ..._nearbySection(),
                ..._servicesSection(),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          ),
          // Pas de barre d'application ici : dès que la page défile, un bandeau sombre occupe la zone de la barre d'état, sinon les
          // filtres et les cartes passent sous l'heure et les icônes du téléphone.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: _scroll,
                builder: (context, _) {
                  final scrolled = _scroll.hasClients && _scroll.offset > 4;
                  return AnimatedContainer(
                    key: const ValueKey('status-bar-scrim'),
                    duration: TtMotion.fast,
                    color: scrolled ? TtColors.night : TtColors.night.withValues(alpha: 0),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: widget.embedded
          ? null
          : TratraBottomNav(
        currentIndex: 0,
        onTap: _onNavTap,
        items: const [
          TratraNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Accueil'),
          TratraNavItem(icon: Icons.search_rounded, label: 'Recherche'),
          TratraNavItem(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month,
            label: 'Réservations',
          ),
          TratraNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profil'),
        ],
      ),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(borderRadius: TtRadius.pillAll, boxShadow: TtShadows.glowAccent),
        child: FloatingActionButton.extended(
          onPressed: _createQuickRequest,
          tooltip: 'Trouver un pro',
          icon: const Icon(Icons.search_rounded),
          label: const Text('Trouver un pro'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildError() {
    final detail = _errorMessage.replaceFirst('Exception: ', '').trim();
    return Scaffold(
      body: SafeArea(
        child: TratraEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Impossible de charger l’accueil',
          description: detail.isEmpty
              ? 'Vérifiez votre connexion puis réessayez.'
              : 'Vérifiez votre connexion puis réessayez.\n($detail)',
          actions: [
            TratraButton(
              label: 'Réessayer',
              leading: const Icon(Icons.refresh_rounded),
              onPressed: _loadData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _swap(String key, Widget child) => AnimatedSwitcher(
        duration: homeDuration(context),
        child: KeyedSubtree(key: ValueKey(key), child: child),
      );

  List<Widget> _categoriesSection() {
    final Widget body;
    if (_isLoading && _categories.isEmpty) {
      body = _swap('loading', const HomeSkeletonRow(height: 156, itemWidth: 148));
    } else if (_categories.isEmpty) {
      body = _swap(
        'empty',
        HomeSectionEmpty(
          icon: Icons.category_outlined,
          title: 'Aucun métier pour le moment',
          description: 'Les métiers s’affichent dès qu’ils sont disponibles. Vérifiez votre connexion ou réessayez.',
          actionLabel: 'Réessayer',
          onAction: _loadData,
        ),
      );
    } else {
      body = _swap(
        'list',
        HomeHorizontalList(
          height: 156,
          itemCount: _categories.length,
          itemBuilder: (_, i) {
            final c = _categories[i];
            return HomeCategoryCard(
              category: c,
              selected: _selectedCategory?.id == c.id,
              onTap: () => _onSelectCategory(c),
            );
          },
        ),
      );
    }
    return [
      SliverToBoxAdapter(
        child: TratraSectionHeader(
          title: 'Métiers',
          subtitle: 'Choisissez un métier',
          actionLabel: 'Tout voir',
          onAction: _showAllCategories,
        ),
      ),
      SliverToBoxAdapter(child: body),
    ];
  }

  List<Widget> _nearbySection() {
    final hasPosition = _currentPosition != null;
    final Widget body;
    if (_isLoading) {
      body = _swap('loading', const HomeSkeletonRow(height: 268, itemWidth: 268));
    } else if (_nearby.isEmpty) {
      body = _swap(
        'empty',
        hasPosition
            ? HomeSectionEmpty(
                icon: Icons.near_me_disabled_outlined,
                title: 'Aucun pro à proximité',
                description:
                    'Aucun service publié dans un rayon de ${_nearbyRadiusKm.toStringAsFixed(0)} km pour le moment.',
                actionLabel: 'Voir tous les pros',
                onAction: _showAllArtisans,
              )
            : HomeSectionEmpty(
                icon: Icons.location_off_outlined,
                title: 'Localisation inactive',
                description: 'Activez la localisation de votre téléphone pour voir les pros proches de vous.',
                actionLabel: 'Réessayer la localisation',
                onAction: _loadData,
              ),
      );
    } else {
      body = _swap(
        'list',
        HomeHorizontalList(
          height: 268,
          itemCount: _nearby.length,
          itemBuilder: (_, i) => _nearbyCard(_nearby[i]),
        ),
      );
    }
    return [
      SliverToBoxAdapter(
        child: TratraSectionHeader(
          title: 'Pros à proximité',
          subtitle: hasPosition
              ? 'Autour de votre position, dans un rayon de ${_nearbyRadiusKm.toStringAsFixed(0)} km'
              : 'Activez la localisation pour voir les pros proches',
          actionLabel: 'Voir tout',
          onAction: _showAllArtisans,
        ),
      ),
      SliverToBoxAdapter(child: body),
    ];
  }

  List<Widget> _servicesSection() {
    final Widget body;
    if (_isLoading) {
      body = _swap('loading', const HomeSkeletonRow(height: 320, itemWidth: 280));
    } else if (_services.isEmpty) {
      final filtered = _selectedCategory != null || _searchText.trim().isNotEmpty;
      final String actionLabel;
      final VoidCallback onAction;
      if (_selectedCategory != null) {
        actionLabel = 'Toutes les catégories';
        onAction = () => _onSelectCategory(null);
      } else if (_searchText.trim().isNotEmpty) {
        actionLabel = 'Effacer la recherche';
        onAction = () {
          _searchCtrl.clear();
          _onSearchChanged('');
        };
      } else {
        actionLabel = 'Réessayer';
        onAction = _loadData;
      }
      body = _swap(
        'empty',
        HomeSectionEmpty(
          icon: Icons.search_off_rounded,
          title: 'Aucun service trouvé',
          description: filtered
              ? 'Aucun service ne correspond à votre sélection. Modifiez votre recherche ou votre catégorie.'
              : 'Aucun service n’est publié pour le moment. Vérifiez votre connexion ou réessayez.',
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      );
    } else {
      body = _swap(
        'list',
        HomeHorizontalList(
          height: 320,
          itemCount: _services.length,
          itemBuilder: (_, i) => _serviceCard(_services[i]),
        ),
      );
    }
    return [
      SliverToBoxAdapter(
        child: TratraSectionHeader(
          title: 'Services',
          subtitle: _servicesSubtitle(),
          actionLabel: 'Voir tout',
          onAction: _showAllServices,
        ),
      ),
      SliverToBoxAdapter(child: body),
    ];
  }

  /// Sous-titre fidèle au tri réellement appliqué (jamais « les plus réservés »).
  String _servicesSubtitle() {
    if (_onlyNearby && _currentPosition != null) return 'Triés par distance autour de vous';
    switch (_ordering) {
      case 'price':
        return 'Du moins cher au plus cher';
      case '-price':
        return 'Du plus cher au moins cher';
      default:
        return 'Les plus récents en premier';
    }
  }

  Widget _serviceCard(HomeServiceEntry e) => homeServiceCard(
        e,
        isFavorite: _favoriteServices[e.service.id] ?? false,
        onFavorite: () => _toggleFavoriteService(e.service.id),
        onShare: () => _shareService(e.service),
        onTap: () => _navigateToServiceDetail(e.service),
        onBook: () => _openBooking(e.service),
      );

  Widget _nearbyCard(HomeServiceEntry e) => homeNearbyCard(
        e,
        isFavorite: _favoriteServices[e.service.id] ?? false,
        onFavorite: () => _toggleFavoriteService(e.service.id),
        onShare: () => _shareService(e.service),
        onOpen: () => _navigateToServiceDetail(e.service),
      );
}
