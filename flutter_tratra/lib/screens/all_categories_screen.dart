// lib/screens/all_categories_screen.dart
//
// « Tous les métiers » : le catalogue COMPLET, lu depuis le catalogue commun (`GET /handy/catalog/`, même réponse que le site). Un métier actif
// est toujours affiché, avec ou sans offre ; ses prestations sont listées à l'ouverture de la carte.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/browse/browse_parts.dart';
import 'package:flutter_tratra/screens/home/home_icons.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

/// Tris proposés : l'ordre du catalogue (réglé dans l'administration) ou l'ordre alphabétique.
const List<(String, String)> _orderingOptions = [
  ('order', 'Ordre du catalogue'),
  ('name', 'Nom A→Z'),
  ('-name', 'Nom Z→A'),
];

/// Grille des cellules : 3 colonnes sur téléphone, davantage sur grand écran.
const SliverGridDelegateWithMaxCrossAxisExtent _tileGrid =
    SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 150,
  mainAxisSpacing: TtSpace.s3,
  crossAxisSpacing: TtSpace.s3,
  childAspectRatio: .8,
);

/// Texte sans accents ni casse : « Élagage » se trouve en tapant « elag ».
String _plain(String text) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer.toString();
}

class AllCategoriesScreen extends StatefulWidget {
  const AllCategoriesScreen({super.key});

  @override
  State<AllCategoriesScreen> createState() => _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends State<AllCategoriesScreen> {
  late final BaseApi _api;

  // État chargement
  bool _loading = true;
  String? _error;
  Catalog? _catalog;

  // Recherche & tri (côté application : le catalogue est léger et complet)
  final TextEditingController _search = TextEditingController();
  String _ordering = 'order';

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    final repo = CatalogRepository.shared(_api);
    _catalog = repo.cached; // affichage immédiat si le catalogue est déjà connu
    _loading = _catalog == null;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ============ DONNÉES ============

  Future<void> _load({bool force = false}) async {
    try {
      final catalog = await CatalogRepository.shared(_api).load(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load(force: true);

  /// Métiers visibles : recherche (métier, prestations, description) puis tri.
  List<Category> get _items {
    final catalog = _catalog;
    if (catalog == null) return const [];
    final q = _plain(_search.text.trim());
    var trades = catalog.trades;
    if (q.isNotEmpty) {
      trades = [
        for (final t in trades)
          if (_plain(t.name).contains(q) ||
              _plain(t.description ?? '').contains(q) ||
              catalog.prestationsOf(t.id).any((p) => _plain(p.name).contains(q)))
            t,
      ];
    }
    int byName(Category a, Category b) => _plain(a.name).compareTo(_plain(b.name));
    final sorted = [...trades];
    if (_ordering == 'name') sorted.sort(byName);
    if (_ordering == '-name') sorted.sort((a, b) => byName(b, a));
    return sorted;
  }

  // ============ ACTIONS ============

  bool get _hasActiveFilters => _search.text.isNotEmpty || _ordering != 'order';

  void _clearFilters() => setState(() {
        _search.clear();
        _ordering = 'order';
      });

  void _setOrdering(String value) {
    if (_ordering == value) return;
    setState(() => _ordering = value);
  }

  void _showFilterDialog() {
    showTratraSheet<void>(
      context,
      title: 'Tri',
      child: _CategoryFiltersForm(
        ordering: _ordering,
        onApply: (ordering) => setState(() => _ordering = ordering),
        onClear: _clearFilters,
      ),
    );
  }

  /// Ouvre un métier : ses prestations (avec leurs offres) et l'accès aux offres.
  void _openTrade(Category trade) {
    final catalog = _catalog;
    if (catalog == null) return;
    final prestations = catalog.prestationsOf(trade.id);
    showTratraSheet<void>(
      context,
      title: trade.name,
      description: _offersLabel(trade.offersTotal),
      child: Builder(
        builder: (sheetContext) {
          void browse(String name) {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AllServicesScreen(initialCategory: name)));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((trade.description ?? '').trim().isNotEmpty) ...[
                Text(trade.description!.trim(), style: TratraTheme.style(TtType.body, color: TtColors.ash)),
                const SizedBox(height: TtSpace.s3),
              ],
              if (prestations.isEmpty)
                Text('Aucune prestation détaillée pour ce métier.', style: TratraTheme.style(TtType.body, color: TtColors.ash))
              else
                for (final p in prestations) ...[
                  TratraCard(
                    variant: TratraCardVariant.flat,
                    radius: TtRadius.panel,
                    padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4, vertical: TtSpace.s3),
                    semanticLabel: '${p.name}, ${_offersLabel(p.offersTotal)}',
                    onTap: () => browse(p.name),
                    child: Row(
                      children: [
                        homeCategoryIcon(p, color: TtColors.primaryDark, size: 18),
                        const SizedBox(width: TtSpace.s3),
                        Expanded(child: Text(p.name, style: TratraTheme.style(TtType.title).copyWith(fontSize: 14))),
                        Text(_offersLabel(p.offersTotal), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                      ],
                    ),
                  ),
                  const SizedBox(height: TtSpace.s2),
                ],
              const SizedBox(height: TtSpace.s3),
              TratraButton(
                label: 'Voir les offres de ${trade.name}',
                block: true,
                trailing: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => browse(trade.name),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(
        title: 'Tous les métiers',
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
              onRefresh: _refresh,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s2),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _search,
              builder: (_, value, __) => TratraInput(
                controller: _search,
                hint: 'Rechercher un métier ou une prestation…',
                leadingIcon: Icons.search_rounded,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                suffix: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer la recherche',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          _buildSortRow(),
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
              label: 'Tri',
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
    if (_search.text.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
        children: [
          Center(
            child: _RemovableChip(
              label: 'Recherche : ${_search.text}',
              onRemove: () => setState(_search.clear),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final items = _items;
    if (_loading && _catalog == null) {
      return const _CategoriesSkeleton();
    }

    if (_error != null && _catalog == null) {
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
              onPressed: _refresh,
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      final filtered = _hasActiveFilters;
      return BrowseCenteredScroll(
        key: const ValueKey('categories-empty'),
        child: TratraEmptyState(
          icon: Icons.category_outlined,
          title: filtered ? 'Aucun métier' : 'Le catalogue des métiers arrive',
          description: filtered
              ? 'Aucun métier ni aucune prestation ne correspond à votre recherche.'
              : 'Les métiers s’afficheront ici dès leur ouverture sur la plateforme.',
          actions: [
            if (filtered)
              TratraButton(
                label: 'Réinitialiser',
                variant: TratraButtonVariant.soft,
                onPressed: _clearFilters,
              )
            else
              TratraButton(
                label: 'Actualiser',
                variant: TratraButtonVariant.outline,
                leading: const Icon(Icons.refresh_rounded),
                onPressed: _refresh,
              ),
          ],
        ),
      );
    }

    return BrowseFadeIn(
      key: const ValueKey('categories-grid'),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s2),
            sliver: SliverGrid(
              gridDelegate: _tileGrid,
              delegate: SliverChildBuilderDelegate(
                (context, i) => _CategoryTile(
                  category: items[i],
                  prestations: _catalog!.prestationsOf(items[i].id),
                  onTap: () => _openTrade(items[i]),
                ),
                childCount: items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: TtSpace.s6 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

/// « 12 offres », « 1 offre » ou « Aucune offre » (un métier sans offre reste affiché).
String _offersLabel(int? count) {
  if (count == null) return '';
  if (count <= 0) return 'Aucune offre';
  return count == 1 ? '1 offre' : '$count offres';
}

// ===== Cellule métier =====

/// Carte d'un métier : icône du catalogue, nom, nombre d'offres publiées ; un appui ouvre ses prestations.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.prestations, required this.onTap});
  final Category category;
  final List<Category> prestations;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = category;
    final subtitle = prestations.isEmpty ? _offersLabel(c.offersTotal) : '${prestations.length} prestation${prestations.length > 1 ? 's' : ''}';
    return TratraCard(
      variant: TratraCardVariant.flat,
      padding: const EdgeInsets.all(TtSpace.s2),
      radius: TtRadius.panel,
      semanticLabel: '${c.name}, $subtitle, ${_offersLabel(c.offersTotal)}',
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: TtRadius.panelAll),
            child: Center(child: homeCategoryIcon(c, color: TtColors.primaryDark)),
          ),
          const SizedBox(height: TtSpace.s2),
          Text(
            c.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
            style: TratraTheme.style(TtType.h3).copyWith(fontSize: 13, height: 1.25),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.1),
            style: TratraTheme.style(TtType.caption, color: TtColors.ash),
          ),
        ],
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
      label: 'Chargement des métiers',
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

class _CategoryFiltersForm extends StatelessWidget {
  const _CategoryFiltersForm({required this.ordering, required this.onApply, required this.onClear});

  final String ordering;
  final void Function(String ordering) onApply;
  final VoidCallback onClear;

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
                selected: ordering == option.$1,
                onTap: () {
                  onApply(option.$1);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        const SizedBox(height: TtSpace.s4),
        Center(
          child: TratraButton(
            label: 'Tout effacer',
            variant: TratraButtonVariant.ghost,
            size: TratraButtonSize.sm,
            onPressed: () {
              onClear();
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }
}
