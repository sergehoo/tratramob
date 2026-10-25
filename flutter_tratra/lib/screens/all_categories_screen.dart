// lib/screens/all_categories_screen.dart
//
// « Tous les métiers » : le catalogue COMPLET, lu depuis le catalogue commun (`GET /handy/catalog/`, même réponse que le site), rangé par
// FAMILLES (navigation compacte, « Autres métiers » en dernier). Un métier actif est toujours affiché, avec ou sans offre ; ses prestations
// sont listées à l'ouverture de la carte. La recherche couvre noms, prestations et synonymes (« clim », « frigo »).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/flash/flash_hybrid.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/browse/browse_parts.dart';
import 'package:flutter_tratra/screens/home/home_icons.dart';
import 'package:flutter_tratra/screens/panne_screen.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

/// Filtre « Autres métiers » : métiers rangés dans aucune famille.
const String _otherFamily = '_autres';

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

  /// Famille choisie (identifiant), `_otherFamily` pour « Autres métiers », null = toutes.
  String? _familyId;

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

  List<Category> _familyTrades(Catalog catalog) {
    final id = _familyId;
    if (id == null) return catalog.trades;
    if (id == _otherFamily) return catalog.tradesWithoutFamily;
    for (final f in catalog.families) {
      if (f.id == id) return catalog.tradesOf(f);
    }
    return catalog.trades;
  }

  /// Métiers visibles : famille, recherche (métier, prestations, description, synonymes) puis tri.
  List<Category> get _items {
    final catalog = _catalog;
    if (catalog == null) return const [];
    final q = _plain(_search.text.trim());
    var trades = _familyTrades(catalog);
    bool matches(Category c) => _plain(c.name).contains(q) || c.keywords.any((k) => _plain(k).contains(q));
    if (q.isNotEmpty) {
      trades = [
        for (final t in trades)
          if (matches(t) || _plain(t.description ?? '').contains(q) || catalog.prestationsOf(t.id).any(matches)) t,
      ];
    }
    int byName(Category a, Category b) => _plain(a.name).compareTo(_plain(b.name));
    final sorted = [...trades];
    if (_ordering == 'name') sorted.sort(byName);
    if (_ordering == '-name') sorted.sort((a, b) => byName(b, a));
    return sorted;
  }

  // ============ ACTIONS ============

  bool get _hasActiveFilters => _search.text.isNotEmpty || _ordering != 'order' || _familyId != null;

  void _clearFilters() => setState(() {
        _search.clear();
        _ordering = 'order';
        _familyId = null;
      });

  /// Sections par famille : seulement pour le catalogue complet, sans recherche ni tri alphabétique.
  bool get _grouped => _familyId == null && _search.text.trim().isEmpty && _ordering == 'order' && (_catalog?.families.isNotEmpty ?? false);

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

  void _openPanne() {
    final q = _search.text.trim();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PanneScreen(initialText: q.isEmpty ? null : q)));
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

          // Hybrid Matching : après le métier ou la prestation, « Trouvez-moi un professionnel » ou « Choisir mon professionnel ».
          void choose(Category category) {
            showTratraSheet<void>(
              context,
              title: category.name,
              child: Builder(
                builder: (choiceContext) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ModeChoiceButtons(category: category, onBeforeOpen: () {
                    Navigator.of(choiceContext).pop();
                    Navigator.of(sheetContext).pop();
                  }),
                  const SizedBox(height: TtSpace.s2),
                  TextButton(onPressed: () {
                    Navigator.of(choiceContext).pop();
                    browse(category.name);
                  }, child: const Text('Voir les offres publiées')),
                ]),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((trade.description ?? '').trim().isNotEmpty) ...[
                Text(trade.description!.trim(), style: TratraTheme.style(TtType.body, color: TtColors.ash)),
                const SizedBox(height: TtSpace.s3),
              ],
              ModeChoiceButtons(category: trade, onBeforeOpen: () => Navigator.of(sheetContext).pop()),
              const SizedBox(height: TtSpace.s4),
              if (prestations.isEmpty)
                Text('Aucune prestation détaillée pour ce métier.', style: TratraTheme.style(TtType.body, color: TtColors.ash))
              else
                for (final p in prestations) ...[
                  TratraCard(
                    variant: TratraCardVariant.flat,
                    radius: TtRadius.panel,
                    padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4, vertical: TtSpace.s3),
                    semanticLabel: '${p.name}, ${_offersLabel(p.offersTotal)}',
                    onTap: () => choose(p),
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
          _buildFamilyRow(),
          _buildSortRow(),
          _buildActiveFilters(),
          const SizedBox(height: TtSpace.s2),
        ],
      ),
    );
  }

  /// Familles de métiers (navigation compacte) : « Toutes », chaque famille, « Autres métiers ».
  Widget _buildFamilyRow() {
    final catalog = _catalog;
    if (catalog == null || catalog.families.isEmpty) return const SizedBox.shrink();
    final options = <(String?, String, String?)>[
      (null, 'Toutes', null),
      for (final f in catalog.families) (f.id, f.name, f.iconKey),
      if (catalog.tradesWithoutFamily.isNotEmpty) (_otherFamily, 'Autres métiers', null),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        key: const ValueKey('family-row'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
        children: [
          for (final (id, label, _) in options) ...[
            Center(
              child: TratraChip(
                key: ValueKey('family-${id ?? 'all'}'),
                label: label,
                selected: _familyId == id,
                onTap: () => setState(() => _familyId = id),
              ),
            ),
            const SizedBox(width: TtSpace.s2),
          ],
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

    final catalog = _catalog!;
    final groups = <(String, List<Category>)>[
      if (_grouped) ...[
        for (final f in catalog.families) (f.name, catalog.tradesOf(f)),
        if (catalog.tradesWithoutFamily.isNotEmpty) ('Autres métiers', catalog.tradesWithoutFamily),
      ] else
        ('', items),
    ];
    return BrowseFadeIn(
      key: const ValueKey('categories-grid'),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, 0),
            sliver: SliverToBoxAdapter(child: _PanneBanner(onTap: () => _openPanne())),
          ),
          for (final (title, trades) in groups) ...[
            if (title.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s5, TtSpace.s4, 0),
                sliver: SliverToBoxAdapter(
                  child: Semantics(header: true, child: Text(title, style: TratraTheme.style(TtType.h2))),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s2),
              sliver: SliverGrid(
                gridDelegate: _tileGrid,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _CategoryTile(
                    category: trades[i],
                    prestations: catalog.prestationsOf(trades[i].id),
                    onTap: () => _openTrade(trades[i]),
                  ),
                  childCount: trades.length,
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: TtSpace.s6 + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}

/// Taille du nom d'une tuile : 13 par défaut, réduite (jusqu'à 10) pour que le mot le plus long tienne sur une ligne — jamais
/// « Cybersécurit / é » coupé en plein mot.
double fittedNameSize(String name, double maxWidth, TextScaler scaler, {double base = 13, double min = 10}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return base;
  var widest = 0.0;
  for (final word in name.split(RegExp(r'\s+'))) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: TratraTheme.style(TtType.h3).copyWith(fontSize: base)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
  }
  if (widest <= maxWidth) return base;
  return (base * maxWidth / widest).clamp(min, base);
}

/// « 12 offres », « 1 offre » ou « Aucune offre » (un métier sans offre reste affiché).
String _offersLabel(int? count) {
  if (count == null) return '';
  if (count <= 0) return 'Aucune offre';
  return count == 1 ? '1 offre' : '$count offres';
}

// ===== « J'ai une panne » =====

/// Accès à « J'ai une panne » : décrire le problème plutôt que chercher le métier.
class _PanneBanner extends StatelessWidget {
  const _PanneBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TratraCard(
        key: const ValueKey('panne-banner'),
        variant: TratraCardVariant.accent,
        padding: TratraCard.compact,
        onTap: onTap,
        semanticLabel: 'J’ai une panne : décrire mon problème',
        child: Row(children: [
          const Icon(Icons.build_circle_outlined, color: TtColors.primaryDark, size: 32),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('J’ai une panne', style: TratraTheme.style(TtType.title)),
              Text('Décrivez le problème : Tratra trouve le métier et les artisans.', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ]),
      );
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
          LayoutBuilder(
            builder: (context, box) {
              final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);
              final style = TratraTheme.style(TtType.h3).copyWith(fontSize: fittedNameSize(c.name, box.maxWidth, scaler), height: 1.25);
              return Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, textScaler: scaler, style: style);
            },
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
