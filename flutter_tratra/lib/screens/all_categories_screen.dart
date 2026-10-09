// lib/screens/all_categories_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/screens/browse/browse_parts.dart';

/// Valeurs `ordering` acceptées par l'API et leur libellé.
const List<(String, String)> _orderingOptions = [
  ('name', 'Nom A→Z'),
  ('-name', 'Nom Z→A'),
  ('-created_at', 'Plus récentes'),
  ('created_at', 'Plus anciennes'),
];

/// Grille des cellules : 3 colonnes sur téléphone, davantage sur grand écran.
const SliverGridDelegateWithMaxCrossAxisExtent _tileGrid =
    SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 150,
  mainAxisSpacing: TtSpace.s3,
  crossAxisSpacing: TtSpace.s3,
  childAspectRatio: .8,
);

class AllCategoriesScreen extends StatefulWidget {
  const AllCategoriesScreen({super.key});

  @override
  State<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends State<AllCategoriesScreen> {
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
      }

      final decoded = _api.decodeBody(r);
      final results = _api.extractResults(decoded);
      final pagination = _api.extractPagination(decoded);

      final newItems = results
          .map<Category>((e) => Category.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Robustesse pagination (si extractPagination est null ou différent)
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

  // ============ ACTIONS ============

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

  void _setOrdering(String value) {
    if (_ordering == value) return;
    setState(() => _ordering = value);
    _loadInitial();
  }

  void _showFilterDialog() {
    showTratraSheet<void>(
      context,
      title: 'Filtres & tri',
      child: _CategoryFiltersForm(
        ordering: _ordering,
        onlyActive: _onlyActive,
        onApply: (ordering, onlyActive) {
          setState(() {
            _ordering = ordering;
            _onlyActive = onlyActive;
          });
          _loadInitial();
        },
        onClear: _clearFilters,
      ),
    );
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(
        title: 'Toutes les catégories',
        actions: [
          if (_hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              color: TtColors.primaryDark,
              tooltip: 'Supprimer les filtres',
              onPressed: _clearFilters,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInitial,
              color: TtColors.primaryDark,
              backgroundColor: TtColors.surface,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(bottom: BorderSide(color: TtColors.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barre de recherche (debounce)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s2),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _search,
              builder: (_, value, __) => TratraInput(
                controller: _search,
                hint: 'Rechercher une catégorie…',
                leadingIcon: Icons.search_rounded,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                suffix: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _search.clear();
                          _loadInitial();
                        },
                      ),
              ),
            ),
          ),

          // Filtres + tri
          _buildSortRow(),

          // Filtres actifs (recherche, inactives)
          _buildActiveFilters(),

          const SizedBox(height: TtSpace.s2),
        ],
      ),
    );
  }

  Widget _buildSortRow() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
        children: [
          Center(
            child: TratraButton(
              label: 'Filtres',
              variant: TratraButtonVariant.soft,
              size: TratraButtonSize.sm,
              leading: const Icon(Icons.tune_rounded),
              onPressed: _showFilterDialog,
            ),
          ),
          const SizedBox(width: TtSpace.s3),
          const Center(
            child: SizedBox(
              height: 20,
              child: VerticalDivider(width: 1, color: TtColors.line),
            ),
          ),
          for (final option in _orderingOptions) ...[
            const SizedBox(width: TtSpace.s2),
            Center(
              child: TratraChip(
                label: option.$2,
                selected: _ordering == option.$1,
                onTap: () => _setOrdering(option.$1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    final chips = <Widget>[
      if (_search.text.isNotEmpty)
        _RemovableChip(
          label: 'Recherche : ${_search.text}',
          onRemove: () {
            _search.clear();
            _loadInitial();
          },
        ),
      if (!_onlyActive)
        _RemovableChip(
          label: 'Inclure inactives',
          onRemove: () {
            setState(() => _onlyActive = true);
            _loadInitial();
          },
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: TtSpace.s2),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _items.isEmpty) {
      return const _CategoriesSkeleton();
    }

    if (_error != null) {
      return BrowseCenteredScroll(
        key: const ValueKey('categories-error'),
        child: TratraEmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Chargement impossible',
          description: browseErrorMessage(_error),
          actions: [
            TratraButton(
              label: 'Réessayer',
              leading: const Icon(Icons.refresh_rounded),
              onPressed: _loadInitial,
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      final filtered = _hasActiveFilters;
      return BrowseCenteredScroll(
        key: const ValueKey('categories-empty'),
        child: TratraEmptyState(
          icon: Icons.category_outlined,
          title: 'Aucune catégorie',
          description: filtered
              ? 'Aucune catégorie ne correspond à votre recherche ou à vos filtres.'
              : 'Aucune catégorie n’est disponible pour le moment.',
          actions: [
            if (filtered)
              TratraButton(
                label: 'Réinitialiser les filtres',
                variant: TratraButtonVariant.soft,
                onPressed: _clearFilters,
              )
            else
              TratraButton(
                label: 'Actualiser',
                variant: TratraButtonVariant.outline,
                leading: const Icon(Icons.refresh_rounded),
                onPressed: _loadInitial,
              ),
          ],
        ),
      );
    }

    return BrowseFadeIn(
      key: const ValueKey('categories-grid'),
      child: NotificationListener<ScrollNotification>(
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
              padding: const EdgeInsets.fromLTRB(
                  TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s2),
              sliver: SliverGrid(
                gridDelegate: _tileGrid,
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i == _items.length && _hasMore) {
                      return const TratraShimmer(child: _CategoryTileSkeleton());
                    }
                    if (i >= _items.length) return null;
                    return _CategoryTile(category: _items[i]);
                  },
                  childCount: _items.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: TtSpace.s3),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: TtSpace.s6 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Cellule catégorie =====

/// Cellule d'information : l'application n'expose pas de destination filtrée par
/// catégorie, la cellule n'est donc pas cliquable (pas de faux affordance).
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final c = category;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: c.isActive ? c.name : '${c.name}, inactive',
      child: TratraCard(
        variant: TratraCardVariant.flat,
        padding: EdgeInsets.zero,
        radius: TtRadius.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BrowseImage(
                    url: c.imageUrl,
                    fallbackIcon: Icons.handyman_outlined,
                  ),
                  if (!c.isActive)
                    const Positioned(
                      top: TtSpace.s2,
                      left: TtSpace.s2,
                      child: TratraBadge('Inactive', tone: TratraTone.gray),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: TtSpace.s2),
                  child: Text(
                    c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    textScaler:
                        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
                    style: TratraTheme.style(TtType.h3)
                        .copyWith(fontSize: 13, height: 1.25),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Squelettes =====

class _CategoryTileSkeleton extends StatelessWidget {
  const _CategoryTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TtColors.surface,
        borderRadius: TtRadius.panelAll,
        border: Border.all(color: TtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(TtRadius.panel - 1),
              ),
              child: ColoredBox(color: TtColors.line.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(
            height: 52,
            child: Center(child: TratraSkeletonBox(width: 64, height: 12)),
          ),
        ],
      ),
    );
  }
}

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement des catégories',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(TtSpace.s4),
            gridDelegate: _tileGrid,
            itemCount: 12,
            itemBuilder: (_, __) => const _CategoryTileSkeleton(),
          ),
        ),
      ),
    );
  }
}

// ===== Puce de filtre actif (supprimable) =====

/// Puce de filtre actif : un appui retire le filtre. Composée localement car
/// `TratraChip` n'a pas de variante « supprimable ».
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Semantics(
        button: true,
        label: 'Retirer le filtre : $label',
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: TtColors.primarySoft,
            shape: StadiumBorder(
              side: BorderSide(color: TtColors.primary.withValues(alpha: 0.5)),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRemove,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: TtLayout.touchTarget - 4),
                child: Padding(
                  padding: const EdgeInsets.only(left: TtSpace.s3, right: TtSpace.s2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.bodySm,
                                  color: TtColors.primaryDark)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: TtSpace.s2),
                      const Icon(Icons.close_rounded,
                          size: 16, color: TtColors.primaryDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Feuille de filtres =====

/// Contenu de la feuille « Filtres & tri ». Le brouillon est local : rien n'est
/// appliqué tant que l'utilisateur n'appuie pas sur « Appliquer ».
class _CategoryFiltersForm extends StatefulWidget {
  const _CategoryFiltersForm({
    required this.ordering,
    required this.onlyActive,
    required this.onApply,
    required this.onClear,
  });

  final String ordering;
  final bool onlyActive;
  final void Function(String ordering, bool onlyActive) onApply;
  final VoidCallback onClear;

  @override
  State<_CategoryFiltersForm> createState() => _CategoryFiltersFormState();
}

class _CategoryFiltersFormState extends State<_CategoryFiltersForm> {
  late String _ordering = widget.ordering;
  late bool _onlyActive = widget.onlyActive;

  @override
  Widget build(BuildContext context) {
    final eyebrow = TratraTheme.style(TtType.eyebrow, color: TtColors.ash);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TRIER PAR', style: eyebrow),
        const SizedBox(height: TtSpace.s3),
        Wrap(
          spacing: TtSpace.s2,
          runSpacing: TtSpace.s2,
          children: [
            for (final option in _orderingOptions)
              TratraChip(
                label: option.$2,
                selected: _ordering == option.$1,
                onTap: () => setState(() => _ordering = option.$1),
              ),
          ],
        ),
        const SizedBox(height: TtSpace.s6),
        Text('STATUT', style: eyebrow),
        const SizedBox(height: TtSpace.s2),
        TratraCard(
          variant: TratraCardVariant.flat,
          radius: TtRadius.panel,
          padding: const EdgeInsets.symmetric(
              horizontal: TtSpace.s4, vertical: TtSpace.s1),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Afficher uniquement les actives',
              style: TratraTheme.style(TtType.body),
            ),
            value: _onlyActive,
            onChanged: (v) => setState(() => _onlyActive = v),
          ),
        ),
        const SizedBox(height: TtSpace.s6),
        Row(
          children: [
            Expanded(
              child: TratraButton(
                label: 'Annuler',
                variant: TratraButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: TratraButton(
                label: 'Appliquer',
                onPressed: () {
                  widget.onApply(_ordering, _onlyActive);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: TtSpace.s2),
        Center(
          child: TratraButton(
            label: 'Tout effacer',
            variant: TratraButtonVariant.ghost,
            size: TratraButtonSize.sm,
            onPressed: () {
              widget.onClear();
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }
}
