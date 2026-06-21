// lib/screens/all_categories_screen.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/category.dart';

class AllCategoriesScreen extends StatefulWidget {
  const AllCategoriesScreen({Key? key}) : super(key: key);

  @override
  State<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends State<AllCategoriesScreen> {
  // UI
  static const _bg = Color(0xFFF8F9FA);
  static const _card = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE5E5E5);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);
  static const _searchBg = Color(0xFFF1F2F6);

  static const _placeholder =
      'https://via.placeholder.com/600x400?text=Category';

  late final BaseApi _api;

  // État chargement / pagination
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Category> _items = [];
  int _currentPage = 1;
  bool _hasMore = true;

  // Recherche & filtres
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _ordering = 'name'; // options: name, -name, -created_at, created_at
  bool _onlyActive = true;

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ============ API ============

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
      final queryParams = <String, String>{
        'page_size': '24',
        'ordering': _ordering,
        'page': reset ? '1' : (_currentPage + 1).toString(),
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        if (_onlyActive) 'is_active': 'true',
      };

      final uri =
          Uri.parse('${_api.baseUrl}${AppConstants.categoriesEndpoint}/')
              .replace(queryParameters: queryParams);

      final r = await _getPublic(uri);
      if (r.statusCode != 200) {
        _api.handleError(r);
        return;
      }

      final decoded = _api.decodeBody(r);
      final results = _api.extractResults(decoded);
      final pagination = _api.extractPagination(decoded);

      final newItems = results
          .map<Category>((e) => Category.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Robustesse pagination (si extractPagination est null ou différent)
      dynamic nextVal;
      if (pagination is Map && pagination['next'] != null) {
        nextVal = pagination['next'];
      } else if (decoded is Map && decoded['next'] != null) {
        nextVal = decoded['next'];
      } else if (decoded is Map &&
          decoded['pagination'] is Map &&
          (decoded['pagination'] as Map)['next'] != null) {
        nextVal = (decoded['pagination'] as Map)['next'];
      }

      if (!mounted) return;
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

  // ============ HELPERS ============

  /// Utilise uniquement l'URL fournie par l'API (Category.imageUrl).
  /// Si vide/invalide → placeholder (évite les erreurs TLS MinIO).
  String _safeImageUrl(String raw) {
    final u = (raw).trim();
    if (u.isEmpty) return _placeholder;
    final parsed = Uri.tryParse(u);
    if (parsed == null ||
        !parsed.hasScheme ||
        !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return _placeholder;
    }
    return u;
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadInitial();
    });
  }

  bool get _hasActiveFilters =>
      _search.text.isNotEmpty || _ordering != 'name' || !_onlyActive;

  void _clearFilters() {
    setState(() {
      _search.clear();
      _ordering = 'name';
      _onlyActive = true;
    });
    _loadInitial();
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryFiltersSheet(
        ordering: _ordering,
        onlyActive: _onlyActive,
        onOrderingChanged: (v) => setState(() => _ordering = v),
        onActiveChanged: (v) => setState(() => _onlyActive = v),
        onApply: () {
          _loadInitial();
          Navigator.pop(context);
        },
        onClear: () {
          _clearFilters();
          Navigator.pop(context);
        },
      ),
    );
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Toutes les catégories'),
        backgroundColor: _card,
        actions: [
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
                DropdownMenuItem(value: 'name', child: Text('Nom A→Z')),
                DropdownMenuItem(value: '-name', child: Text('Nom Z→A')),
                DropdownMenuItem(
                    value: '-created_at', child: Text('Plus récentes')),
                DropdownMenuItem(
                    value: 'created_at', child: Text('Plus anciennes')),
              ],
              onChanged: (v) {
                setState(() => _ordering = v ?? 'name');
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
                hintText: 'Rechercher une catégorie…',
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

          // Chips d’état des filtres
          _buildActiveFiltersChips(),

          // Contenu
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInitial,
              color: _accent,
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

    if (_ordering != 'name') {
      final txt = {
            'name': 'Nom A→Z',
            '-name': 'Nom Z→A',
            '-created_at': 'Plus récentes',
            'created_at': 'Plus anciennes',
          }[_ordering] ??
          _ordering;
      chips.add(Chip(
        label: Text('Tri: $txt'),
        onDeleted: () {
          setState(() => _ordering = 'name');
          _loadInitial();
        },
      ));
    }

    if (!_onlyActive) {
      chips.add(Chip(
        label: const Text('Inclure inactives'),
        onDeleted: () {
          setState(() => _onlyActive = true);
          _loadInitial();
        },
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: chips
            .map((c) =>
                Padding(padding: const EdgeInsets.only(right: 6), child: c))
            .toList(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Erreur : $_error',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('Aucune catégorie')),
          SizedBox(height: 120),
        ],
      );
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
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: .8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  if (i == _items.length && _hasMore) {
                    return Container(
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
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
                  if (i >= _items.length) return null;

                  final c = _items[i];
                  final imageUrl = _safeImageUrl(c.imageUrl);

                  return Container(
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            height: 80,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(height: 80, color: Colors.black12),
                            errorWidget: (_, __, ___) => Container(
                              height: 80,
                              color: Colors.black12,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
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

// ===== Bottom sheet filtres =====

class _CategoryFiltersSheet extends StatefulWidget {
  const _CategoryFiltersSheet({
    required this.ordering,
    required this.onlyActive,
    required this.onOrderingChanged,
    required this.onActiveChanged,
    required this.onApply,
    required this.onClear,
  });

  final String ordering;
  final bool onlyActive;
  final ValueChanged<String> onOrderingChanged;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  State<_CategoryFiltersSheet> createState() => _CategoryFiltersSheetState();
}

class _CategoryFiltersSheetState extends State<_CategoryFiltersSheet> {
  Color? get _accent => null;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
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
                  'Filtres & tri',
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
                _section('Trier par'),
                ..._orderingTiles(),
                const SizedBox(height: 16),
                _section('Statut'),
                SwitchListTile(
                  title: const Text('Afficher uniquement les actives'),
                  value: widget.onlyActive,
                  onChanged: widget.onActiveChanged,
                  contentPadding: EdgeInsets.zero,
                ),
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

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      );

  List<Widget> _orderingTiles() {
    const options = [
      {'value': 'name', 'label': 'Nom A→Z'},
      {'value': '-name', 'label': 'Nom Z→A'},
      {'value': '-created_at', 'label': 'Plus récentes'},
      {'value': 'created_at', 'label': 'Plus anciennes'},
    ];
    return options
        .map(
          (o) => RadioListTile<String>(
            title: Text(o['label']!),
            value: o['value']!,
            groupValue: widget.ordering,
            onChanged: (v) {
              if (v != null) widget.onOrderingChanged(v);
            },
            contentPadding: EdgeInsets.zero,
          ),
        )
        .toList();
  }
}
