// lib/screens/all_urgent_services_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/service_list/service_list_kit.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

class AllUrgentServicesScreen extends StatefulWidget {
  const AllUrgentServicesScreen({super.key});

  @override
  State<AllUrgentServicesScreen> createState() =>
      _AllUrgentServicesScreenState();
}

class _AllUrgentServicesScreenState extends State<AllUrgentServicesScreen> {
  late final BaseApi _api;

  // États
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Service> _items = [];
  int _currentPage = 1;
  bool _hasMore = true;

  // Filtres & recherche
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _ordering = '-created_at';
  double _minPrice = 0;
  double _maxPrice = 100000;
  String? _selectedCategory;
  List<String> _categories = [];

  // Inputs prix
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    _loadInitialData();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadInitialData();
    });
  }

  Future<void> _loadCategories() async {
    try {
      // Catalogue COMMUN (même réponse que le site) : métiers puis prestations, dans l'ordre de l'administration.
      final catalog = await CatalogRepository.shared(_api).load();
      if (!mounted) return;
      setState(() => _categories = catalog.names);
    } catch (_) {
      // Catégories optionnelles → silencieux
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
      _hasMore = true;
    });

    await _loadData(reset: true);
  }

  Future<void> _loadMoreData() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);
    await _loadData();
  }

  Future<void> _loadData({bool reset = false}) async {
    try {
      final queryParams = <String, String>{
        'page_size': '20',
        'ordering': _ordering,
        'page': reset ? '1' : (_currentPage + 1).toString(),
        'urgent': 'true',
        if (_searchController.text.trim().isNotEmpty)
          'search': _searchController.text.trim(),
        if (_minPrice > 0) 'min_price': _minPrice.toStringAsFixed(0),
        if (_maxPrice < 100000) 'max_price': _maxPrice.toStringAsFixed(0),
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty)
          'category__name': _selectedCategory!,
      };

      final uri = Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/')
          .replace(queryParameters: queryParams);

      final response = await _getPublic(uri);
      if (response.statusCode != 200) {
        _api.handleError(response);
      }

      final decoded = _api.decodeBody(response);
      final results = _api.extractResults(decoded);
      final rawPagination = _api.extractPagination(decoded);

      final newItems = results.map<Service>(_serviceFromBackend).toList();

      if (!mounted) return;

      // Pagination safe (aucune supposition sur la structure)
      dynamic nextVal;
      if (rawPagination['next'] != null) {
        nextVal = rawPagination['next'];
      } else if (decoded is Map && decoded['next'] != null) {
        nextVal = decoded['next'];
      } else if (decoded is Map &&
          decoded['pagination'] is Map &&
          (decoded['pagination'] as Map)['next'] != null) {
        nextVal = (decoded['pagination'] as Map)['next'];
      }

      setState(() {
        if (reset) {
          _items = newItems;
          _currentPage = 1;
        } else {
          _items.addAll(newItems);
          _currentPage++;
        }
        _hasMore = nextVal != null && nextVal.toString().isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<http.Response> _getPublic(Uri uri) async {
    final client = _api.client;
    try {
      var response =
          await client.get(uri, headers: await _api.getHeaders(withAuth: true));
      if (response.statusCode == 401) {
        response = await client.get(uri,
            headers: await _api.getHeaders(withAuth: false));
      }
      return response;
    } catch (_) {
      rethrow;
    }
  }

  Service _serviceFromBackend(dynamic json) {
    final data = (json as Map<String, dynamic>? ?? const {});
    final id = (data['id'] ?? '').toString();
    final title = (data['title'] ?? '') as String? ?? '';
    final category = _extractCategory(data);

    // Image TLS-safe (uniquement image_url -> sinon placeholder)
    final imageUrl = _extractImageUrlTLSafe(data);

    // Nombres safe
    final price = double.tryParse('${data['price'] ?? '0'}') ?? 0.0;
    final rating = double.tryParse('${data['rating'] ?? '0'}') ?? 0.0;
    final reviewCount = (data['review_count'] as int?) ?? 0;

    // Dates safe
    final createdAt =
        DateTime.tryParse('${data['created_at'] ?? ''}') ?? DateTime.now();
    final updatedAt =
        DateTime.tryParse('${data['updated_at'] ?? ''}') ?? DateTime.now();

    return Service(
      id: id,
      title: title,
      description: (data['description'] ?? '').toString(),
      category: category,
      imageUrl: imageUrl,
      price: price,
      rating: rating,
      reviewCount: reviewCount,
      discountedPrice: null,
      duration: const Duration(),
      // Liste filtrée côté serveur (`urgent=true`) : artisan en ligne maintenant, hors congé.
      isUrgent: true,
      includedServices: const [],
      requiredTools: const [],
      priceType: (data['price_type'] ?? 'fixed').toString(),
      handymanId: (data['handyman'] ?? '').toString(),
      categoryId: (data['category'] ?? '').toString(),
      categoryName: category,
      isActive: (data['is_active'] ?? true) == true, // bool sûr
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String _extractCategory(Map<String, dynamic> data) {
    final categoryDetail = data['category_detail'] as Map?;
    if (categoryDetail != null) {
      return (categoryDetail['name'] ?? '').toString();
    }
    return (data['category_name'] ?? '').toString();
  }

  /// TLS-safe : on n'utilise que `image_url` ; si absent/invalide → chaîne vide
  /// (l'interface affiche une vignette de repli de la marque, jamais d'image factice).
  String _extractImageUrlTLSafe(Map<String, dynamic> data) {
    final raw = (data['image_url'] ?? '').toString().trim();
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return '';
    }
    return raw;
  }

  void _applyPriceFilter() {
    final min = double.tryParse(_minPriceController.text) ?? 0;
    final max = double.tryParse(_maxPriceController.text) ?? 100000;

    if (min <= max) {
      setState(() {
        _minPrice = min;
        _maxPrice = max;
      });
      _loadInitialData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le prix minimum doit être inférieur au prix maximum'),
          backgroundColor: TtColors.danger,
        ),
      );
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
      _minPrice = 0;
      _maxPrice = 100000;
      _selectedCategory = null;
      _ordering = '-created_at';
    });
    _loadInitialData();
  }

  void _showFilterDialog() {
    showServiceFilterSheet(
      context,
      minPriceController: _minPriceController,
      maxPriceController: _maxPriceController,
      selectedCategory: _selectedCategory,
      categories: _categories,
      ordering: _ordering,
      onApply: (category, ordering) {
        // Tri et catégorie choisis dans la feuille, puis prix + rechargement (inchangé).
        setState(() {
          _selectedCategory = category;
          _ordering = ordering;
        });
        _applyPriceFilter();
      },
      onClear: _clearFilters,
    );
  }

  Future<void> _onRefresh() async {
    await _loadInitialData();
  }

  void _onServiceTap(Service service) {
    Navigator.pushNamed(
      context,
      RouteNames.serviceDetail,
      arguments: ServiceDetailArgs(service),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return TratraAppBar(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _UrgentMark(),
          const SizedBox(width: TtSpace.s3),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Services urgents',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h3),
                ),
                Text(
                  'Artisans en ligne maintenant',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_hasActiveFilters)
          IconButton(
            icon: const Icon(Icons.filter_alt_off_outlined),
            tooltip: 'Supprimer les filtres',
            onPressed: _clearFilters,
          ),
      ],
    );
  }

  bool get _hasActiveFilters {
    return _searchController.text.isNotEmpty ||
        _minPrice > 0 ||
        _maxPrice < 100000 ||
        _selectedCategory != null ||
        _ordering != '-created_at';
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ServiceListHeader(
          controller: _searchController,
          searchHint: 'Rechercher un service urgent…',
          onSearchChanged: _onSearchChanged,
          onSearchClear: () {
            _searchController.clear();
            _loadInitialData();
          },
          onOpenFilters: _showFilterDialog,
          activeFilterCount: _activeFilterCount,
          activeFilters: _activeFilters(),
        ),
        Expanded(
          child: RefreshIndicator(
            color: TtColors.primary,
            backgroundColor: TtColors.surface,
            onRefresh: _onRefresh,
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  /// Réglages de la feuille « Filtres et tri » actuellement actifs (prix, catégorie, tri).
  int get _activeFilterCount =>
      ((_minPrice > 0 || _maxPrice < 100000) ? 1 : 0) +
      (_selectedCategory != null ? 1 : 0) +
      (_ordering != '-created_at' ? 1 : 0);

  String get _priceFilterLabel {
    if (_minPrice > 0 && _maxPrice < 100000) {
      return 'Prix : ${formatFcfaAmount(_minPrice)} – ${formatFcfaAmount(_maxPrice)} FCFA';
    }
    if (_minPrice > 0) return 'Prix : dès ${formatFcfaAmount(_minPrice)} FCFA';
    return 'Prix : jusqu’à ${formatFcfaAmount(_maxPrice)} FCFA';
  }

  List<ServiceActiveFilter> _activeFilters() {
    if (!_hasActiveFilters) return const [];

    final filters = <ServiceActiveFilter>[];

    if (_searchController.text.isNotEmpty) {
      filters.add(
        ServiceActiveFilter('Recherche : ${_searchController.text}', () {
          _searchController.clear();
          _loadInitialData();
        }),
      );
    }

    if (_minPrice > 0 || _maxPrice < 100000) {
      filters.add(
        ServiceActiveFilter(_priceFilterLabel, () {
          _minPriceController.clear();
          _maxPriceController.clear();
          setState(() {
            _minPrice = 0;
            _maxPrice = 100000;
          });
          _loadInitialData();
        }),
      );
    }

    if (_selectedCategory != null) {
      filters.add(
        ServiceActiveFilter('Catégorie : $_selectedCategory', () {
          setState(() => _selectedCategory = null);
          _loadInitialData();
        }),
      );
    }

    if (_ordering != '-created_at') {
      filters.add(
        ServiceActiveFilter('Tri : ${serviceOrderingLabel(_ordering)}', () {
          setState(() => _ordering = '-created_at');
          _loadInitialData();
        }),
      );
    }

    return filters;
  }

  Widget _buildEmpty() {
    if (_hasActiveFilters) {
      return TratraEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Aucun service urgent ne correspond',
        description:
            'Aucun résultat pour ces critères. Modifiez ou retirez vos filtres pour élargir la recherche.',
        actions: [
          TratraButton(
            label: 'Effacer les filtres',
            leading: const Icon(Icons.filter_alt_off_outlined),
            onPressed: _clearFilters,
          ),
        ],
      );
    }
    return TratraEmptyState(
      icon: Icons.bolt_rounded,
      title: 'Aucun artisan disponible maintenant',
      description:
          'Les services apparaissent ici dès qu’un artisan vérifié est en ligne et disponible. Actualisez ou consultez tous les services.',
      actions: [
        TratraButton(
          label: 'Voir tous les services',
          onPressed: () => Navigator.pushNamed(context, RouteNames.allServices),
        ),
        TratraButton(
          label: 'Actualiser',
          variant: TratraButtonVariant.outline,
          leading: const Icon(Icons.refresh_rounded),
          onPressed: _loadInitialData,
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading && _items.isEmpty) {
      return const ServiceRowSkeleton();
    }

    if (_error != null) {
      return ServiceListCenteredScroll(
        child: ServiceListErrorState(
          message: _error!,
          onRetry: _loadInitialData,
        ),
      );
    }

    if (_items.isEmpty) {
      return ServiceListCenteredScroll(child: _buildEmpty());
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
        if (scrollNotification is ScrollEndNotification &&
            scrollNotification.metrics.pixels ==
                scrollNotification.metrics.maxScrollExtent &&
            _hasMore &&
            !_loadingMore) {
          _loadMoreData();
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = serviceListGutter(constraints.maxWidth);
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                gutter, TtSpace.s4, gutter, TtSpace.s6 + bottomInset),
            itemCount: _items.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _items.length && _hasMore) {
                return const ServiceRowLoadingCell();
              }

              final service = _items[index];
              return ServiceRowCard(
                service: service,
                onTap: () => _onServiceTap(service),
              );
            },
          );
        },
      ),
    );
  }
}

/// Pastille éclair jaune de la barre d'application (identité « urgence »).
class _UrgentMark extends StatelessWidget {
  const _UrgentMark();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: DecoratedBox(
        decoration:
            BoxDecoration(color: TtColors.accent, shape: BoxShape.circle),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.bolt_rounded, size: 20, color: TtColors.ink),
        ),
      ),
    );
  }
}
