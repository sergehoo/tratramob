// lib/screens/home/home_sections.dart
//
// Briques de sections de l'accueil : rangées horizontales, squelettes, états vides,
// bandeau d'urgence et cartes de catégories.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';

import 'home_cards.dart';
import 'home_icons.dart';
import 'home_models.dart';
import 'home_motion.dart';

/// Rangée horizontale à hauteur fixe (agrandie avec la taille de texte du système).
class HomeHorizontalList extends StatelessWidget {
  const HomeHorizontalList({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: homeRowHeight(context, height),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(width: TtSpace.s3),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Squelette d'une rangée de cartes (un seul balayage partagé, annoncé une fois).
class HomeSkeletonRow extends StatelessWidget {
  const HomeSkeletonRow({super.key, required this.height, required this.itemWidth, this.count = 3});

  final double height;
  final double itemWidth;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement en cours',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: SizedBox(
            height: homeRowHeight(context, height),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(width: TtSpace.s3),
              itemBuilder: (_, __) => TratraSkeletonBox(
                width: itemWidth,
                height: homeRowHeight(context, height),
                radius: TtRadius.card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Squelette du carrousel « À la une ».
class HomeSlidesSkeleton extends StatelessWidget {
  const HomeSlidesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement en cours',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
        child: TratraSkeleton(height: homeRowHeight(context, 196), radius: TtRadius.card),
      ),
    );
  }
}

/// État vide d'une section : explique la situation réelle et propose une action existante.
class HomeSectionEmpty extends StatelessWidget {
  const HomeSectionEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
      child: TratraCard(
        variant: TratraCardVariant.flat,
        padding: EdgeInsets.zero,
        child: TratraEmptyState(
          compact: true,
          icon: icon,
          title: title,
          description: description,
          actions: [
            TratraButton(
              label: actionLabel,
              variant: TratraButtonVariant.soft,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau « night » vers l'écran des services d'urgence (destination existante) : aucune
/// disponibilité ni délai d'intervention n'est promis ici.
class HomeUrgentBanner extends StatelessWidget {
  const HomeUrgentBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s6, TtSpace.s4, 0),
      child: TratraCard(
        variant: TratraCardVariant.night,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(1, -1),
                      radius: 1.1,
                      colors: [TtColors.accent.withValues(alpha: 0.22), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(TtSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: TtColors.accent, borderRadius: TtRadius.panelAll),
                        child: const Icon(Icons.bolt_rounded, color: TtColors.ink),
                      ),
                      const SizedBox(width: TtSpace.s3),
                      Expanded(
                        child: Text(
                          'Un dépannage urgent ?',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.h3, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TtSpace.s3),
                  Text(
                    'Accédez à la liste des services d’urgence et choisissez un artisan.',
                    style: TratraTheme.style(TtType.bodySm, color: Colors.white.withValues(alpha: 0.78)),
                  ),
                  const SizedBox(height: TtSpace.s4),
                  TratraButton(
                    label: 'Voir les urgences',
                    variant: TratraButtonVariant.accent,
                    trailing: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onTap();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'une catégorie : photo réelle si l'API en fournit une, sinon panneau de marque.
class HomeCategoryCard extends StatelessWidget {
  const HomeCategoryCard({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = homeFixMediaUrl(category.imageUrl);
    return SizedBox(
      width: 148,
      child: TratraCard(
        variant: selected ? TratraCardVariant.soft : TratraCardVariant.standard,
        padding: EdgeInsets.zero,
        semanticLabel: selected ? '${category.name}, sélectionnée' : category.name,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image.isEmpty
                      ? const DecoratedBox(decoration: BoxDecoration(gradient: TtGradients.brand))
                      : HomeImage(url: image),
                  if (image.isNotEmpty)
                    DecoratedBox(decoration: BoxDecoration(color: TtColors.night.withValues(alpha: 0.28))),
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: TtColors.surface, borderRadius: TtRadius.panelAll),
                      child: Center(child: homeCategoryIcon(category, color: TtColors.primaryDark)),
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      top: TtSpace.s2,
                      right: TtSpace.s2,
                      child: Icon(Icons.check_circle_rounded, size: 22, color: TtColors.accent),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.title, color: selected ? TtColors.primaryDark : TtColors.ink)
                        .copyWith(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25),
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
