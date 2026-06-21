// lib/screens/all_urgent_services_screen.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/widgets/error_widget.dart';
import 'package:flutter_tratra/widgets/loading_widget.dart';
import 'package:flutter_tratra/widgets/empty_state_widget.dart';

class AllUrgentServicesScreen extends StatefulWidget {
  const AllUrgentServicesScreen({Key? key}) : super(key: key);

  @override
  State<AllUrgentServicesScreen> createState() =>
      _AllUrgentServicesScreenState();
}

class _AllUrgentServicesScreenState extends State<AllUrgentServicesScreen> {
  // Design constants
  static const _colors = _UrgentServicesColors();
  static const _dimens = _UrgentServicesDimens();
  static const _strings = _UrgentServicesStrings();

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
      final uri =
          Uri.parse('${_api.baseUrl}${AppConstants.categoriesEndpoint}/')
              .replace(queryParameters: {
        'page_size': '100',
        'is_active': 'true',
      });

      final response = await _getPublic(uri);
      if (response.statusCode == 200) {
        final decoded = _api.decodeBody(response);
        final results = _api.extractResults(decoded);

        if (!mounted) return;
        setState(() {
          _categories = results
              .map<String>((category) {
                final data = category as Map<String, dynamic>;
                return data['name']?.toString() ?? '';
              })
              .where((name) => name.isNotEmpty)
              .toList();
        });
      }
    } catch (_) {
      // Les catégories sont optionnelles : on ignore silencieusement.
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
        return;
      }

      final decoded = _api.decodeBody(response);
      final results = _api.extractResults(decoded);
      final rawPagination = _api.extractPagination(decoded);

      final newItems = results.map<Service>(_serviceFromBackend).toList();

      if (!mounted) return;

      // Pagination safe (aucune supposition sur la structure)
      dynamic nextVal;
      if (rawPagination is Map && rawPagination['next'] != null) {
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
      isUrgent: (data['is_urgent'] ?? false) == true, // bool sûr
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

  /// TLS-safe : on n'utilise que `image_url` ; si absent/invalide → placeholder.
  String _extractImageUrlTLSafe(Map<String, dynamic> data) {
    final raw = (data['image_url'] ?? '').toString().trim();
    if (raw.isEmpty) return _strings.placeholderImageUrl;

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return _strings.placeholderImageUrl;
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
          backgroundColor: Colors.red,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        minPriceController: _minPriceController,
        maxPriceController: _maxPriceController,
        selectedCategory: _selectedCategory,
        categories: _categories,
        ordering: _ordering,
        onApply: () {
          _applyPriceFilter();
          Navigator.pop(context);
        },
        onClear: () {
          _clearFilters();
          Navigator.pop(context);
        },
        onCategoryChanged: (category) {
          setState(() => _selectedCategory = category);
        },
        onOrderingChanged: (ordering) {
          setState(() => _ordering = ordering);
        },
      ),
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
      backgroundColor: _UrgentServicesColors.background,
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFilterFAB(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Services urgents'),
      backgroundColor: _UrgentServicesColors.card,
      elevation: 1,
      actions: [
        if (_hasActiveFilters)
          IconButton(
            icon: const Icon(Icons.filter_alt),
            color: _UrgentServicesColors.accent,
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

  Widget _buildFilterFAB() {
    return FloatingActionButton(
      onPressed: _showFilterDialog,
      backgroundColor: _UrgentServicesColors.accent,
      foregroundColor: Colors.white,
      child: const Icon(Icons.filter_list),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildActiveFiltersChips(),
        Expanded(
          child: RefreshIndicator(
            color: _UrgentServicesColors.accent,
            onRefresh: _onRefresh,
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.all(_dimens.screenPadding),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: _strings.searchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadInitialData();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(_dimens.borderRadius),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: _UrgentServicesColors.searchBackground,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildActiveFiltersChips() {
    if (!_hasActiveFilters) return const SizedBox.shrink();

    final chips = <Widget>[];

    if (_searchController.text.isNotEmpty) {
      chips.add(
        Chip(
          label: Text('Recherche: ${_searchController.text}'),
          onDeleted: () {
            _searchController.clear();
            _loadInitialData();
          },
        ),
      );
    }

    if (_minPrice > 0 || _maxPrice < 100000) {
      chips.add(
        Chip(
          label: Text('Prix: ${_minPrice.toInt()}-${_maxPrice.toInt()} FCFA'),
          onDeleted: () {
            _minPriceController.clear();
            _maxPriceController.clear();
            setState(() {
              _minPrice = 0;
              _maxPrice = 100000;
            });
            _loadInitialData();
          },
        ),
      );
    }

    if (_selectedCategory != null) {
      chips.add(
        Chip(
          label: Text('Catégorie: $_selectedCategory'),
          onDeleted: () {
            setState(() => _selectedCategory = null);
            _loadInitialData();
          },
        ),
      );
    }

    if (_ordering != '-created_at') {
      final orderText = {
            'price': 'Prix croissant',
            '-price': 'Prix décroissant',
            '-rating': 'Meilleures notes',
          }[_ordering] ??
          _ordering;

      chips.add(
        Chip(
          label: Text('Tri: $orderText'),
          onDeleted: () {
            setState(() => _ordering = '-created_at');
            _loadInitialData();
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(children: chips),
    );
  }

  Widget _buildContent() {
    if (_loading && _items.isEmpty) {
      return const LoadingWidget();
    }

    if (_error != null) {
      return CustomErrorWidget(
        error: _error!,
        onRetry: _loadInitialData,
      );
    }

    if (_items.isEmpty) {
      return EmptyStateWidget(
        message: _strings.noServicesFound,
        onRetry: _loadInitialData,
      );
    }

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
      child: ListView.builder(
        padding: EdgeInsets.all(_dimens.screenPadding),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length && _hasMore) {
            return const _LoadingMoreItem();
          }

          final service = _items[index];
          return _UrgentRowCard(
            service: service,
            onTap: () => _onServiceTap(service),
          );
        },
      ),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  const _FilterBottomSheet({
    required this.minPriceController,
    required this.maxPriceController,
    required this.selectedCategory,
    required this.categories,
    required this.ordering,
    required this.onApply,
    required this.onClear,
    required this.onCategoryChanged,
    required this.onOrderingChanged,
  });

  final TextEditingController minPriceController;
  final TextEditingController maxPriceController;
  final String? selectedCategory;
  final List<String> categories;
  final String ordering;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onOrderingChanged;

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Filtres et tri',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onClear,
                  child: const Text('Tout effacer'),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSectionHeader('Trier par'),
                ..._buildOrderingOptions(),
                const SizedBox(height: 20),
                _buildSectionHeader('Catégorie'),
                _buildCategoryDropdown(),
                const SizedBox(height: 20),
                _buildSectionHeader('Prix (FCFA)'),
                _buildPriceFilter(),
                const SizedBox(height: 40),
              ],
            ),
          ),

          // Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: widget.onApply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _UrgentServicesColors.accent,
                    ),
                    child: const Text('Appliquer',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      );

  List<Widget> _buildOrderingOptions() {
    const options = [
      {'value': '-created_at', 'label': 'Plus récents'},
      {'value': 'price', 'label': 'Prix croissant'},
      {'value': '-price', 'label': 'Prix décroissant'},
      {'value': '-rating', 'label': 'Meilleures notes'},
    ];

    return options
        .map((option) => RadioListTile<String>(
              title: Text(option['label']!),
              value: option['value']!,
              groupValue: widget.ordering,
              onChanged: (value) {
                if (value != null) widget.onOrderingChanged(value);
              },
              contentPadding: EdgeInsets.zero,
            ))
        .toList();
  }

  /// IMPORTANT : accepte `null` (toutes catégories)
  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String?>(
      value: widget.selectedCategory,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      ),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Toutes les catégories'),
        ),
        ...widget.categories.map(
          (category) => DropdownMenuItem<String?>(
            value: category,
            child: Text(category),
          ),
        ),
      ],
      onChanged: widget.onCategoryChanged,
    );
  }

  Widget _buildPriceFilter() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: widget.minPriceController,
            decoration: const InputDecoration(
              labelText: 'Min',
              border: OutlineInputBorder(),
              prefixText: '₣ ',
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 12),
        const Text('-'),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: widget.maxPriceController,
            decoration: const InputDecoration(
              labelText: 'Max',
              border: OutlineInputBorder(),
              prefixText: '₣ ',
            ),
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    );
  }
}

class _UrgentRowCard extends StatelessWidget {
  const _UrgentRowCard({
    required this.service,
    required this.onTap,
  });

  final Service service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const dimens = _UrgentServicesDimens();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(dimens.cardRadius),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: _UrgentServicesColors.card,
          borderRadius: BorderRadius.circular(dimens.cardRadius),
          border: Border.all(color: _UrgentServicesColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildImage(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(dimens.contentPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Titre + badge URGENT
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            service.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _UrgentServicesColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (service.isUrgent == true) // garde anti-null
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _UrgentServicesColors.urgentBadge,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'URGENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Catégorie
                    Text(
                      service.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _UrgentServicesColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Prix & note
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    const dimens = _UrgentServicesDimens();
    final imageUrl = service.imageUrl.isNotEmpty
        ? service.imageUrl
        : _UrgentServicesStrings().placeholderImageUrl;

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(dimens.cardRadius),
        bottomLeft: Radius.circular(dimens.cardRadius),
      ),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: 120,
        height: 100,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 120,
          height: 100,
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 120,
          height: 100,
          color: Colors.grey[200],
          child: const Icon(Icons.error_outline, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final priceText = '${(service.price ?? 0).toStringAsFixed(0)} FCFA';
    final double rating = service.rating ?? 0;

    return Row(
      children: [
        Text(
          priceText,
          style: const TextStyle(
            color: _UrgentServicesColors.accent,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        if (rating > 0) ...[
          const Icon(Icons.star, color: Colors.amber, size: 14),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: _UrgentServicesColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
        ],
        const Icon(Icons.chevron_right,
            color: _UrgentServicesColors.textSecondary, size: 16),
      ],
    );
  }
}

class _LoadingMoreItem extends StatelessWidget {
  const _LoadingMoreItem();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

// Design constants
class _UrgentServicesColors {
  const _UrgentServicesColors();

  static const Color background = Color(0xFFF8F9FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E5E5);
  static const Color textPrimary = Color(0xFF1E272E);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color accent = Color(0xFF00B14F);
  static const Color urgentBadge = Color(0xFFFF5252);
  static const Color searchBackground = Color(0xFFF1F2F6);
}

class _UrgentServicesDimens {
  const _UrgentServicesDimens();

  final double screenPadding = 12.0;
  final double contentPadding = 10.0;
  final double cardRadius = 14.0;
  final double borderRadius = 12.0;
}

class _UrgentServicesStrings {
  const _UrgentServicesStrings();

  final String searchHint = 'Rechercher un service urgent…';
  final String noServicesFound = 'Aucun service urgent trouvé';
  final String placeholderImageUrl =
      'https://via.placeholder.com/600x400?text=Service+Urgent';
}
