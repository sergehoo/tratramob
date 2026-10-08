// lib/screens/all_services_screen.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';

class AllServicesScreen extends StatefulWidget {
  const AllServicesScreen({super.key});

  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  // Couleurs/constantes visuelles locales
  static const _bg = Color(0xFFF8F9FA);
  static const _card = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE5E5E5);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);
  static const _searchBg = Color(0xFFF1F2F6);

  static const _placeholder =
      'https://via.placeholder.com/600x400?text=Service';

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
        return;
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

  /// Utilise seulement `image_url`. Si vide/invalide → placeholder.
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
          backgroundColor: Colors.red,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Tous les services'),
        backgroundColor: _card,
        actions: [
          // bouton clear si filtres actifs
          if (_hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt),
              color: _accent,
              tooltip: 'Supprimer les filtres',
              onPressed: _clearFilters,
            ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _ordering,
              items: const [
                DropdownMenuItem(
                    value: '-created_at', child: Text('Plus récents')),
                DropdownMenuItem(value: 'price', child: Text('Prix ↑')),
                DropdownMenuItem(value: '-price', child: Text('Prix ↓')),
                DropdownMenuItem(
                    value: '-rating', child: Text('Meilleures notes')),
              ],
              onChanged: (v) {
                setState(() => _ordering = v ?? '-created_at');
                _loadInitial();
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showFilterDialog,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        child: const Icon(Icons.filter_list),
      ),
      body: Column(
        children: [
          // Barre de recherche (debounce)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher un service…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _loadInitial();
                        },
                      )
                    : null,
                filled: true,
                fillColor: _searchBg,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),

          // Chips de filtres actifs
          _buildActiveFiltersChips(),

          // Contenu
          Expanded(
            child: RefreshIndicator(
              color: _accent,
              onRefresh: _loadInitial,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersChips() {
    if (!_hasActiveFilters) return const SizedBox.shrink();

    final chips = <Widget>[];

    if (_search.text.isNotEmpty) {
      chips.add(Chip(
        label: Text('Recherche: ${_search.text}'),
        onDeleted: () {
          _search.clear();
          _loadInitial();
        },
      ));
    }

    if (_minPrice > 0 || _maxPrice < 100000) {
      chips.add(Chip(
        label: Text('Prix: ${_minPrice.toInt()}-${_maxPrice.toInt()} FCFA'),
        onDeleted: () {
          _minPriceController.clear();
          _maxPriceController.clear();
          setState(() {
            _minPrice = 0;
            _maxPrice = 100000;
          });
          _loadInitial();
        },
      ));
    }

    if (_selectedCategory != null) {
      chips.add(Chip(
        label: Text('Catégorie: $_selectedCategory'),
        onDeleted: () {
          setState(() => _selectedCategory = null);
          _loadInitial();
        },
      ));
    }

    if (_ordering != '-created_at') {
      final txt = {
            'price': 'Prix croissant',
            '-price': 'Prix décroissant',
            '-rating': 'Meilleures notes',
          }[_ordering] ??
          _ordering;
      chips.add(Chip(
        label: Text('Tri: $txt'),
        onDeleted: () {
          setState(() => _ordering = '-created_at');
          _loadInitial();
        },
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
          children: chips
              .map((c) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: c,
                  ))
              .toList()),
    );
  }

  Widget _buildContent() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Erreur : $_error',
              style: const TextStyle(color: Colors.red)),
        )
      ]);
    }

    if (_items.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(child: Text('Aucun service')),
        SizedBox(height: 120),
      ]);
    }

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
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: .78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _items.length && _hasMore) {
                    // Carte "loading plus"
                    return Container(
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                      ),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    );
                  }
                  if (index >= _items.length) return null;
                  final s = _items[index];
                  return _ServiceGridCard(
                    title: s.title,
                    category: s.categoryName,
                    priceText: '${(s.price ?? 0).toStringAsFixed(0)} FCFA',
                    imageUrl: s.imageUrl.isNotEmpty ? s.imageUrl : _placeholder,
                    onTap: () => Navigator.pushNamed(
                      context,
                      RouteNames.serviceDetail,
                      arguments: ServiceDetailArgs(s),
                    ),
                  );
                },
                childCount: _items.length + (_hasMore ? 1 : 0),
              ),
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServiceGridCard extends StatelessWidget {
  const _ServiceGridCard({
    required this.title,
    required this.category,
    required this.priceText,
    required this.imageUrl,
    required this.onTap,
  });

  final String title;
  final String category;
  final String priceText;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const card = Color(0xFFFFFFFF);
    const border = Color(0xFFE5E5E5);
    const textPrimary = Color(0xFF1E272E);
    const textSecondary = Color(0xFF636E72);
    const accent = Color(0xFF00B14F);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(height: 120, color: Colors.black12),
                errorWidget: (_, __, ___) => Container(
                  height: 120,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.grey),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: textPrimary, fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Text(priceText,
                      style: const TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: textSecondary),
                ],
              ),
            ),
          ],
        ),
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
  Color? get _accent => null;

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
                      backgroundColor: _accent,
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

  /// IMPORTANT : accepte `null` (toutes les catégories)
  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: widget.selectedCategory,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
