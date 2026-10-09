// lib/screens/service_list/service_list_kit.dart
//
// Briques d'interface partagées par « Tous les services » et « Services urgents ».
// Présentation uniquement : aucun appel réseau, aucune règle métier. Les écrans gardent
// leur chargement, leurs filtres, leur tri, leur pagination et leur navigation.
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/service.dart';

// ---------------------------------------------------------------------------
// Utilitaires d'affichage
// ---------------------------------------------------------------------------

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Largeur maximale du contenu en liste (tablettes / grands écrans).
const double kServiceListMaxWidth = 720;

/// Marge latérale d'une liste centrée à [kServiceListMaxWidth] sur grand écran.
double serviceListGutter(double width) =>
    math.max(TtSpace.s4, (width - kServiceListMaxWidth) / 2);

/// 15000 -> « 15 000 » (espace insécable), sans dépendance de localisation.
String formatFcfaAmount(num value) {
  final raw = value.toStringAsFixed(0);
  final negative = raw.startsWith('-');
  final digits = negative ? raw.substring(1) : raw;
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  return negative ? '-$grouped' : grouped;
}

/// Prix tel que renvoyé par l'API : jamais un « 0 FCFA » inventé quand le prix est absent.
String serviceListPriceText(Service s) {
  if (s.isQuoteBased) return 'Sur devis';
  final price = s.price ?? 0;
  if (price <= 0) return 'Prix non précisé';
  final text = '${formatFcfaAmount(price)} FCFA';
  return s.isHourly ? '$text/h' : text;
}

String _ratingText(double rating) =>
    rating.toStringAsFixed(1).replaceAll('.', ',');

String _semanticLabel(Service s, String price) {
  final category = s.categoryName.trim();
  final rating = s.rating ?? 0;
  return [
    s.title,
    if (category.isNotEmpty) category,
    price,
    if (s.isUrgent) 'Urgent',
    if (rating > 0) 'Note ${_ratingText(rating)}',
  ].join(', ');
}

// ---------------------------------------------------------------------------
// Tri
// ---------------------------------------------------------------------------

class ServiceOrdering {
  const ServiceOrdering(this.value, this.label);
  final String value;
  final String label;
}

/// Valeurs de tri acceptées par l'API (inchangées) et leur libellé.
const List<ServiceOrdering> kServiceOrderings = [
  ServiceOrdering('-created_at', 'Plus récents'),
  ServiceOrdering('price', 'Prix croissant'),
  ServiceOrdering('-price', 'Prix décroissant'),
  ServiceOrdering('-rating', 'Meilleures notes'),
];

/// Libellé d'un tri (valeur brute si inconnue, plutôt que de la cacher).
String serviceOrderingLabel(String value) {
  for (final o in kServiceOrderings) {
    if (o.value == value) return o.label;
  }
  return value;
}

/// Menu de tri rapide de la barre d'application.
class ServiceSortMenuButton extends StatelessWidget {
  const ServiceSortMenuButton({
    super.key,
    required this.ordering,
    required this.onSelected,
  });

  final String ordering;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Trier les services',
      icon: const Icon(Icons.sort_rounded),
      initialValue: ordering,
      onSelected: onSelected,
      color: TtColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: TtColors.ink.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: TtRadius.panelAll,
        side: const BorderSide(color: TtColors.lineSoft),
      ),
      itemBuilder: (context) => [
        for (final o in kServiceOrderings)
          PopupMenuItem<String>(
            value: o.value,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.label,
                    style: TratraTheme.style(
                      TtType.body,
                      color: o.value == ordering
                          ? TtColors.primaryDark
                          : TtColors.ink,
                    ).copyWith(
                      fontWeight: o.value == ordering
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (o.value == ordering)
                  const Icon(Icons.check_rounded,
                      size: 20, color: TtColors.primaryDark),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// En-tête : recherche + bouton filtres + filtres actifs
// ---------------------------------------------------------------------------

class ServiceActiveFilter {
  const ServiceActiveFilter(this.label, this.onRemove);
  final String label;
  final VoidCallback onRemove;
}

class ServiceListHeader extends StatelessWidget {
  const ServiceListHeader({
    super.key,
    required this.controller,
    required this.searchHint,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onOpenFilters,
    required this.activeFilterCount,
    required this.activeFilters,
  });

  final TextEditingController controller;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final VoidCallback onOpenFilters;

  /// Nombre de réglages de la feuille « Filtres et tri » actuellement actifs.
  final int activeFilterCount;
  final List<ServiceActiveFilter> activeFilters;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(bottom: BorderSide(color: TtColors.lineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s3),
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => TratraInput(
                      controller: controller,
                      hint: searchHint,
                      leadingIcon: Icons.search_rounded,
                      textInputAction: TextInputAction.search,
                      onChanged: onSearchChanged,
                      suffix: value.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer la recherche',
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: onSearchClear,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: TtSpace.s3),
                _FilterButton(count: activeFilterCount, onTap: onOpenFilters),
              ],
            ),
          ),
          AnimatedSize(
            duration: _reduceMotion(context) ? Duration.zero : TtMotion.base,
            curve: TtMotion.emphasized,
            alignment: Alignment.topCenter,
            child: activeFilters.isEmpty
                ? const SizedBox(width: double.infinity)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                        TtSpace.s4, 0, TtSpace.s4, TtSpace.s2),
                    child: Row(
                      children: [
                        for (final f in activeFilters)
                          Padding(
                            padding: const EdgeInsets.only(right: TtSpace.s2),
                            child: _FilterPill(filter: f),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final label = active
        ? 'Filtres et tri, $count actif${count > 1 ? 's' : ''}'
        : 'Filtres et tri';

    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Filtres et tri',
        child: SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: active ? TtColors.primaryDark : TtColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: TtRadius.controlAll,
                    side: BorderSide(
                        color: active ? TtColors.primaryDark : TtColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: Center(
                      child: Icon(
                        Icons.tune_rounded,
                        size: 22,
                        color: active ? Colors.white : TtColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              if (active)
                Positioned(
                  top: -6,
                  right: -6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TtColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: TtColors.surface, width: 2),
                    ),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Center(
                        child: Text(
                          '$count',
                          style: TratraTheme.style(TtType.caption,
                                  color: TtColors.ink)
                              .copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtre actif retirable d'un appui (composé localement : le DS n'a pas de puce supprimable).
class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.filter});

  final ServiceActiveFilter filter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Retirer le filtre : ${filter.label}',
      onTap: filter.onRemove,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: filter.onRemove,
        child: ConstrainedBox(
          // Zone d'appui de 44 dp ; la pastille visible reste plus fine.
          constraints: const BoxConstraints(minHeight: TtLayout.touchTarget),
          child: Center(
            child: Material(
              color: TtColors.primarySoft,
              shape: StadiumBorder(
                side:
                    BorderSide(color: TtColors.primary.withValues(alpha: 0.35)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: filter.onRemove,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(TtSpace.s3, 7, TtSpace.s2, 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          filter.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.bodySm,
                                  color: TtColors.primaryDark)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: TtSpace.s1),
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

// ---------------------------------------------------------------------------
// Feuille « Filtres et tri »
// ---------------------------------------------------------------------------

/// Ouvre la feuille de filtres. Les choix de tri et de catégorie sont un brouillon local :
/// ils ne sont transmis à l'écran qu'avec « Appliquer » (`onApply`), qui applique alors
/// le prix et recharge. « Tout effacer » appelle `onClear`. Les deux referment la feuille.
Future<void> showServiceFilterSheet(
  BuildContext context, {
  required TextEditingController minPriceController,
  required TextEditingController maxPriceController,
  required String? selectedCategory,
  required List<String> categories,
  required String ordering,
  required void Function(String? category, String ordering) onApply,
  required VoidCallback onClear,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ServiceFilterSheet(
      minPriceController: minPriceController,
      maxPriceController: maxPriceController,
      selectedCategory: selectedCategory,
      categories: categories,
      ordering: ordering,
      onApply: onApply,
      onClear: onClear,
    ),
  );
}

class _ServiceFilterSheet extends StatefulWidget {
  const _ServiceFilterSheet({
    required this.minPriceController,
    required this.maxPriceController,
    required this.selectedCategory,
    required this.categories,
    required this.ordering,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController minPriceController;
  final TextEditingController maxPriceController;
  final String? selectedCategory;
  final List<String> categories;
  final String ordering;
  final void Function(String? category, String ordering) onApply;
  final VoidCallback onClear;

  @override
  State<_ServiceFilterSheet> createState() => _ServiceFilterSheetState();
}

class _ServiceFilterSheetState extends State<_ServiceFilterSheet> {
  late String? _category = widget.selectedCategory;
  late String _ordering = widget.ordering;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                TtSpace.s5, 0, TtSpace.s3, TtSpace.s1),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Filtres et tri',
                        style: TratraTheme.style(TtType.h2)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.onClear();
                    Navigator.pop(context);
                  },
                  child: const Text('Tout effacer'),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                  TtSpace.s5, TtSpace.s2, TtSpace.s5, TtSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Trier par'),
                  Wrap(
                    spacing: TtSpace.s2,
                    runSpacing: TtSpace.s2,
                    children: [
                      for (final o in kServiceOrderings)
                        TratraChip(
                          label: o.label,
                          selected: _ordering == o.value,
                          onTap: () => setState(() => _ordering = o.value),
                        ),
                    ],
                  ),
                  const SizedBox(height: TtSpace.s6),
                  const _SectionLabel('Catégorie'),
                  Wrap(
                    spacing: TtSpace.s2,
                    runSpacing: TtSpace.s2,
                    children: [
                      TratraChip(
                        label: 'Toutes',
                        selected: _category == null,
                        onTap: () => setState(() => _category = null),
                      ),
                      for (final c in widget.categories)
                        TratraChip(
                          label: c,
                          selected: _category == c,
                          onTap: () => setState(() => _category = c),
                        ),
                    ],
                  ),
                  if (widget.categories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: TtSpace.s2),
                      child: Text(
                        'Aucune catégorie à proposer pour le moment.',
                        style: TratraTheme.style(TtType.caption,
                            color: TtColors.ash),
                      ),
                    ),
                  const SizedBox(height: TtSpace.s6),
                  const _SectionLabel('Prix (FCFA)'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TratraInput(
                          label: 'Minimum',
                          hint: '0',
                          controller: widget.minPriceController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: TtSpace.s3),
                      Expanded(
                        child: TratraInput(
                          label: 'Maximum',
                          hint: 'Sans limite',
                          controller: widget.maxPriceController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: TtColors.surface,
              border: Border(top: BorderSide(color: TtColors.lineSoft)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(TtSpace.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: TratraButton(
                        label: 'Annuler',
                        variant: TratraButtonVariant.outline,
                        block: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: TtSpace.s3),
                    Expanded(
                      child: TratraButton(
                        label: 'Appliquer',
                        block: true,
                        onPressed: () {
                          widget.onApply(_category, _ordering);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TtSpace.s3),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            const DecoratedBox(
              decoration:
                  BoxDecoration(color: TtColors.accent, shape: BoxShape.circle),
              child: SizedBox(width: 6, height: 6),
            ),
            const SizedBox(width: TtSpace.s2),
            Text(
              text.toUpperCase(),
              style: TratraTheme.style(TtType.eyebrow, color: TtColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// États : vide / erreur (défilables pour que le geste « tirer pour actualiser » reste actif)
// ---------------------------------------------------------------------------

class ServiceListCenteredScroll extends StatelessWidget {
  const ServiceListCenteredScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class ServiceListErrorState extends StatelessWidget {
  const ServiceListErrorState(
      {super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TratraEmptyState(
          icon: Icons.sync_problem_rounded,
          title: 'Impossible de charger les services',
          description: 'Le chargement a échoué. Réessayez dans un instant.',
          actions: [
            TratraButton(
              label: 'Réessayer',
              leading: const Icon(Icons.refresh_rounded),
              onPressed: onRetry,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Image de couverture + pastilles
// ---------------------------------------------------------------------------

/// Remplit l'espace que lui donne son parent. Sans image (ou image illisible), vignette
/// de repli aux couleurs de la marque : jamais d'image factice.
class ServiceCoverImage extends StatelessWidget {
  const ServiceCoverImage(
      {super.key, required this.imageUrl, this.memCacheWidth = 480});

  final String imageUrl;
  final int memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    if (url.isEmpty) return const _CoverFallback();
    final reduce = _reduceMotion(context);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      fadeInDuration: reduce ? Duration.zero : TtMotion.base,
      fadeOutDuration: reduce ? Duration.zero : TtMotion.fast,
      fadeInCurve: TtMotion.emphasized,
      placeholder: (_, __) => const ColoredBox(color: TtColors.lineSoft),
      errorWidget: (_, __, ___) => const _CoverFallback(),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: ColoredBox(
        color: TtColors.primarySoft,
        child: Center(
          child:
              Icon(Icons.handyman_outlined, size: 32, color: TtColors.primary),
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating, this.reviewCount});

  final double rating;
  final int? reviewCount;

  @override
  Widget build(BuildContext context) {
    final count = reviewCount ?? 0;
    final style = TratraTheme.style(TtType.caption, color: TtColors.ink)
        .copyWith(fontWeight: FontWeight.w700, height: 1.1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TtColors.surface,
        borderRadius: TtRadius.pillAll,
        boxShadow: TtShadows.hair,
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: TtSpace.s2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded,
                size: 14, color: TtColors.accentDark),
            const SizedBox(width: 3),
            Text(_ratingText(rating), style: style),
            if (count > 0)
              Text(
                ' ($count)',
                style: style.copyWith(
                    color: TtColors.ash, fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ),
    );
  }
}

/// Couverture + pastille « Urgent » (haut) + note (bas) : uniquement des données réelles.
class _CoverWithBadges extends StatelessWidget {
  const _CoverWithBadges({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context) {
    final rating = service.rating ?? 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        ServiceCoverImage(imageUrl: service.imageUrl),
        if (service.isUrgent)
          const Positioned(
            top: TtSpace.s2,
            left: TtSpace.s2,
            child: TratraBadge('Urgent',
                tone: TratraTone.accent, icon: Icons.bolt_rounded),
          ),
        if (rating > 0)
          Positioned(
            left: TtSpace.s2,
            bottom: TtSpace.s2,
            child:
                _RatingPill(rating: rating, reviewCount: service.reviewCount),
          ),
      ],
    );
  }
}

class _ArrowDot extends StatelessWidget {
  const _ArrowDot();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration:
          BoxDecoration(color: TtColors.primarySoft, shape: BoxShape.circle),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(Icons.arrow_forward_rounded,
            size: 16, color: TtColors.primaryDark),
      ),
    );
  }
}

/// Ondulation posée AU-DESSUS du contenu (sinon l'image la masque).
class _TapOverlay extends StatelessWidget {
  const _TapOverlay({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap),
    );
  }
}

TextStyle _categoryStyle() =>
    TratraTheme.style(TtType.eyebrow, color: TtColors.primaryDark);

TextStyle _titleStyle() => TratraTheme.style(TtType.title)
    .copyWith(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3);

/// Prix sur une ligne : il se réduit légèrement plutôt que d'être tronqué (« 15 000 FC… »).
class _PriceText extends StatelessWidget {
  const _PriceText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, style: _priceStyle()),
    );
  }
}

TextStyle _priceStyle() =>
    TratraTheme.style(TtType.h3, color: TtColors.primaryDark)
        .copyWith(fontSize: 15);

// ---------------------------------------------------------------------------
// Grille (« Tous les services »)
// ---------------------------------------------------------------------------

/// Mesures de la grille : nombre de colonnes selon la largeur, image proportionnelle,
/// hauteur de carte tenant compte de la taille de texte du système (pas de débordement).
class ServiceGridLayout {
  ServiceGridLayout._(this.columns, this.imageHeight, this.delegate);

  final int columns;
  final double imageHeight;
  final SliverGridDelegate delegate;

  static ServiceGridLayout of(BuildContext context, double crossAxisExtent) {
    const spacing = TtSpace.s3;
    final columns = math.max(2,
        math.min(4, ((crossAxisExtent + spacing) / (180 + spacing)).floor()));
    final width = (crossAxisExtent - spacing * (columns - 1)) / columns;
    final imageHeight = (width * 0.72).roundToDouble();
    final scale = math.min(
        2.0, math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14));
    // Bloc texte : marges (22) + prix, fixes (≈ 30) + catégorie et titre sur 2 lignes (≈ 54 × échelle).
    final textBlock = 52 + 54 * scale;
    return ServiceGridLayout._(
      columns,
      imageHeight,
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        mainAxisExtent: imageHeight + textBlock,
      ),
    );
  }
}

class ServiceGridCard extends StatelessWidget {
  const ServiceGridCard({
    super.key,
    required this.service,
    required this.imageHeight,
    required this.onTap,
  });

  final Service service;
  final double imageHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = serviceListPriceText(service);
    final category = service.categoryName.trim();

    return Semantics(
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      label: _semanticLabel(service, price),
      child: TratraCard(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: _CoverWithBadges(service: service),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        TtSpace.s3, 10, TtSpace.s3, TtSpace.s3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (category.isNotEmpty) ...[
                          Text(
                            category.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _categoryStyle(),
                          ),
                          const SizedBox(height: TtSpace.s1),
                        ],
                        // Le titre occupe l'espace restant (haut) ; le prix reste en pied de carte.
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              service.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _titleStyle(),
                            ),
                          ),
                        ),
                        _PriceText(price),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned.fill(child: _TapOverlay(onTap: onTap)),
          ],
        ),
      ),
    );
  }
}

class ServiceGridSkeletonCard extends StatelessWidget {
  const ServiceGridSkeletonCard({super.key, required this.imageHeight});

  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TratraSkeletonBox(
              width: double.infinity, height: imageHeight, radius: 0),
          const Padding(
            padding: EdgeInsets.fromLTRB(
                TtSpace.s3, TtSpace.s3, TtSpace.s3, TtSpace.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TratraSkeletonBox(width: 64, height: 10),
                SizedBox(height: 10),
                TratraSkeletonBox(width: double.infinity, height: 13),
                SizedBox(height: 6),
                TratraSkeletonBox(width: 90, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cellule de fin de grille tant qu'il reste des pages à charger.
class ServiceGridLoadingCell extends StatelessWidget {
  const ServiceGridLoadingCell({super.key, required this.imageHeight});

  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement de services supplémentaires',
      child: ExcludeSemantics(
        child: TratraShimmer(
            child: ServiceGridSkeletonCard(imageHeight: imageHeight)),
      ),
    );
  }
}

/// Squelette de la grille pendant le premier chargement (une seule animation partagée).
class ServiceGridSkeleton extends StatelessWidget {
  const ServiceGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Semantics(
      label: 'Chargement des services',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: CustomScrollView(
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s6 + bottom),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final grid = ServiceGridLayout.of(
                        context, constraints.crossAxisExtent);
                    return SliverGrid(
                      gridDelegate: grid.delegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => ServiceGridSkeletonCard(
                            imageHeight: grid.imageHeight),
                        childCount: count,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liste (« Services urgents »)
// ---------------------------------------------------------------------------

class ServiceRowCard extends StatelessWidget {
  const ServiceRowCard({super.key, required this.service, required this.onTap});

  static const double _imageWidth = 112;

  final Service service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = serviceListPriceText(service);
    final category = service.categoryName.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: TtSpace.s3),
      child: Semantics(
        button: true,
        onTap: onTap,
        excludeSemantics: true,
        label: _semanticLabel(service, price),
        child: TratraCard(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _imageWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _imageWidth + TtSpace.s3,
                    TtSpace.s3,
                    TtSpace.s3,
                    TtSpace.s3,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category.isNotEmpty) ...[
                        Text(
                          category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _categoryStyle(),
                        ),
                        const SizedBox(height: TtSpace.s1),
                      ],
                      Text(
                        service.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _titleStyle().copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: TtSpace.s2),
                      Row(
                        children: [
                          Expanded(child: _PriceText(price)),
                          const SizedBox(width: TtSpace.s2),
                          const _ArrowDot(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _imageWidth,
                child: _CoverWithBadges(service: service),
              ),
              Positioned.fill(child: _TapOverlay(onTap: onTap)),
            ],
          ),
        ),
      ),
    );
  }
}

class ServiceRowSkeletonCard extends StatelessWidget {
  const ServiceRowSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: TtSpace.s3),
      child: TratraCard(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            TratraSkeletonBox(width: 112, height: 112, radius: 0),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(TtSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TratraSkeletonBox(width: 70, height: 10),
                    SizedBox(height: 10),
                    TratraSkeletonBox(width: double.infinity, height: 13),
                    SizedBox(height: 6),
                    TratraSkeletonBox(width: 110, height: 13),
                    SizedBox(height: 12),
                    TratraSkeletonBox(width: 80, height: 14),
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

/// Ligne de fin de liste tant qu'il reste des pages à charger.
class ServiceRowLoadingCell extends StatelessWidget {
  const ServiceRowLoadingCell({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement de services supplémentaires',
      child: const ExcludeSemantics(
          child: TratraShimmer(child: ServiceRowSkeletonCard())),
    );
  }
}

/// Squelette de la liste pendant le premier chargement.
class ServiceRowSkeleton extends StatelessWidget {
  const ServiceRowSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = serviceListGutter(constraints.maxWidth);
        return Semantics(
          label: 'Chargement des services',
          liveRegion: true,
          child: ExcludeSemantics(
            child: TratraShimmer(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    gutter, TtSpace.s4, gutter, TtSpace.s6 + bottom),
                itemCount: count,
                itemBuilder: (context, index) => const ServiceRowSkeletonCard(),
              ),
            ),
          ),
        );
      },
    );
  }
}
