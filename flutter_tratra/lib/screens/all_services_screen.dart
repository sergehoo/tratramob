// lib/screens/all_services_screen.dart
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

class AllServicesScreen extends StatefulWidget {
  const AllServicesScreen({super.key});

  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  late final BaseApi _api;

  // État chargement / pagination
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Service> _items = [];
  int _currentPage = 1;
  bool _hasMore = true;

  // Recherche & filtres
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _ordering = '-created_at';
  double _minPrice = 0;
  double _maxPrice = 100000;
  String? _selectedCategory;
  List<String> _categories = [];

  // Inputs min/max prix
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    _loadInitial();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  // ======= Chargement & API =======

  Future<void> _loadCategories() async {
    try {
      final uri =
          Uri.parse('${_api.baseUrl}${AppConstants.categoriesEndpoint}/')
              .replace(queryParameters: {
        'page_size': '100',
        'is_active': 'true',
      });
      final res = await _getPublic(uri);
      if (res.statusCode == 200) {
        final decoded = _api.decodeBody(res);
        final results = _api.extractResults(decoded);
        if (!mounted) return;
        setState(() {
          _categories = results
              .map<String>((e) {
                final m = e as Map<String, dynamic>;
                return m['name']?.toString() ?? '';
              })
              .where((e) => e.isNotEmpty)
              .toList();
        });
      }
    } catch (_) {
      // Catégories optionnelles → silencieux
    }
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _currentPage = 1;
      _hasMore = true;
    });
    await _load(reset: true);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    await _load();
  }

  Future<void> _load({bool reset = false}) async {
    try {
      final qp = <String, String>{
        'is_active': 'true',
        'page_size': '20',
        'ordering': _ordering,
        'page': reset ? '1' : (_currentPage + 1).toString(),
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        if (_minPrice > 0) 'min_price': _minPrice.toStringAsFixed(0),
        if (_maxPrice < 100000) 'max_price': _maxPrice.toStringAsFixed(0),
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty)
          'category__name': _selectedCategory!,
      };

      final uri = Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/')
          .replace(queryParameters: qp);

      final r = await _getPublic(uri);
      if (r.statusCode != 200) {
        _api.handleError(r);
      }

      final decoded = _api.decodeBody(r);
      final list = _api.extractResults(decoded);
      final pagination = _api.extractPagination(decoded);

      final newItems = list.map<Service>(_serviceFromBackend).toList();

      if (!mounted) return;

      // Pagination "safe"
      dynamic nextVal;
      if (pagination['next'] != null) {
        nextVal = pagination['next'];
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
    final c = _api.client;
    var r = await c.get(uri, headers: await _api.getHeaders(withAuth: true));
    if (r.statusCode == 401) {
      r = await c.get(uri, headers: await _api.getHeaders(withAuth: false));
    }
    return r;
  }

  // ======= Mapping =======

  Service _serviceFromBackend(dynamic json) {
    final m = (json as Map<String, dynamic>? ?? const {});
    final id = (m['id'] ?? '').toString();
    final title = (m['title'] ?? '') as String? ?? '';
    final category =
        ((m['category_detail'] as Map?)?['name'] ?? m['category_name'] ?? '')
            .toString();

    // Image: TLS-safe → seulement `image_url`
    final imageUrl = _pickSafeImageUrl(m);

    final price = double.tryParse('${m['price'] ?? '0'}') ?? 0.0;
    final rating = double.tryParse('${m['rating'] ?? '0'}') ?? 0.0;

    return Service(
      id: id,
      title: title,
      description: (m['description'] ?? '').toString(),
      category: category,
      imageUrl: imageUrl,
      price: price,
      rating: rating,
      discountedPrice: null,
      duration: const Duration(),
      isUrgent: (m['is_urgent'] ?? false) == true,
      includedServices: const [],
      requiredTools: const [],
      priceType: (m['price_type'] ?? '').toString(),
      handymanId: '${m['handyman'] ?? ''}',
      categoryId: '${m['category'] ?? ''}',
      categoryName: category,
      isActive: (m['is_active'] ?? true) == true,
      createdAt:
          DateTime.tryParse('${m['created_at'] ?? ''}') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse('${m['updated_at'] ?? ''}') ?? DateTime.now(),
    );
  }

  /// Utilise seulement `image_url`. Si vide/invalide → chaîne vide : l'interface affiche
  /// une vignette de repli aux couleurs de la marque (jamais d'image factice).
  String _pickSafeImageUrl(Map<String, dynamic> m) {
    final raw = (m['image_url'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return '';
    }
    return raw;
  }

  // ======= UI =======

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadInitial();
    });
  }

  bool get _hasActiveFilters =>
      _search.text.isNotEmpty ||
      _minPrice > 0 ||
      _maxPrice < 100000 ||
      _selectedCategory != null ||
      _ordering != '-created_at';

  void _applyPriceFilter() {
    final min = double.tryParse(_minPriceController.text) ?? 0;
    final max = double.tryParse(_maxPriceController.text) ?? 100000;

    if (min <= max) {
      setState(() {
        _minPrice = min;
        _maxPrice = max;
      });
      _loadInitial();
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
      _search.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
      _minPrice = 0;
      _maxPrice = 100000;
      _selectedCategory = null;
      _ordering = '-created_at';
    });
    _loadInitial();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(
        title: 'Tous les services',
        actions: [
          // bouton clear si filtres actifs
          if (_hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: 'Supprimer les filtres',
              onPressed: _clearFilters,
            ),
          ServiceSortMenuButton(
            ordering: _ordering,
            onSelected: (v) {
              setState(() => _ordering = v);
              _loadInitial();
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barre de recherche (debounce), filtres, puces des filtres actifs
          ServiceListHeader(
            controller: _search,
            searchHint: 'Rechercher un service…',
            onSearchChanged: _onSearchChanged,
            onSearchClear: () {
              _search.clear();
              _loadInitial();
            },
            onOpenFilters: _showFilterDialog,
            activeFilterCount: _activeFilterCount,
            activeFilters: _activeFilters(),
          ),

          // Contenu
          Expanded(
            child: RefreshIndicator(
              color: TtColors.primary,
              backgroundColor: TtColors.surface,
              onRefresh: _loadInitial,
              child: _buildContent(),
            ),
          ),
        ],
      ),
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

    if (_search.text.isNotEmpty) {
      filters.add(ServiceActiveFilter('Recherche : ${_search.text}', () {
        _search.clear();
        _loadInitial();
      }));
    }

    if (_minPrice > 0 || _maxPrice < 100000) {
      filters.add(ServiceActiveFilter(_priceFilterLabel, () {
        _minPriceController.clear();
        _maxPriceController.clear();
        setState(() {
          _minPrice = 0;
          _maxPrice = 100000;
        });
        _loadInitial();
      }));
    }

    if (_selectedCategory != null) {
      filters.add(ServiceActiveFilter('Catégorie : $_selectedCategory', () {
        setState(() => _selectedCategory = null);
        _loadInitial();
      }));
    }

    if (_ordering != '-created_at') {
      filters.add(
          ServiceActiveFilter('Tri : ${serviceOrderingLabel(_ordering)}', () {
        setState(() => _ordering = '-created_at');
        _loadInitial();
      }));
    }

    return filters;
  }

  Widget _buildEmpty() {
    if (_hasActiveFilters) {
      return TratraEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Aucun service ne correspond',
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
      icon: Icons.handyman_outlined,
      title: 'Aucun service disponible pour le moment',
      description:
          'Les services publiés par les artisans apparaîtront ici. Actualisez ou parcourez les catégories.',
      actions: [
        TratraButton(
          label: 'Actualiser',
          leading: const Icon(Icons.refresh_rounded),
          onPressed: _loadInitial,
        ),
        TratraButton(
          label: 'Parcourir les catégories',
          variant: TratraButtonVariant.outline,
          onPressed: () =>
              Navigator.pushNamed(context, RouteNames.allCategories),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading && _items.isEmpty) {
      return const ServiceGridSkeleton();
    }

    if (_error != null) {
      return ServiceListCenteredScroll(
        child: ServiceListErrorState(message: _error!, onRetry: _loadInitial),
      );
    }

    if (_items.isEmpty) {
      return ServiceListCenteredScroll(child: _buildEmpty());
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.pixels == n.metrics.maxScrollExtent &&
            _hasMore &&
            !_loadingMore) {
          _loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s6 + bottomInset),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final grid =
                    ServiceGridLayout.of(context, constraints.crossAxisExtent);
                return SliverGrid(
                  gridDelegate: grid.delegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == _items.length && _hasMore) {
                        // Cellule "chargement de la suite"
                        return ServiceGridLoadingCell(
                            imageHeight: grid.imageHeight);
                      }
                      if (index >= _items.length) return null;
                      final s = _items[index];
                      return ServiceGridCard(
                        service: s,
                        imageHeight: grid.imageHeight,
                        onTap: () => Navigator.pushNamed(
                          context,
                          RouteNames.serviceDetail,
                          arguments: ServiceDetailArgs(s),
                        ),
                      );
                    },
                    childCount: _items.length + (_hasMore ? 1 : 0),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
