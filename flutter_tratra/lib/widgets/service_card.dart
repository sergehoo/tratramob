// widgets/service_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import '../models/service.dart';
import 'card_parts.dart';

/// Carte de service (photo, badges promo/urgent, titre, catégorie, note, prix).
///
/// `onTap` : rend la carte cliquable. `onFavoriteToggle` : affiche le bouton favori.
/// Passer `null` pour l'un ou l'autre retire l'interaction correspondante (jamais de
/// bouton sans action). La carte s'adapte à la hauteur disponible : la photo occupe la
/// place restante (prévoir environ 150 dp de hauteur au minimum), ou 120 dp si la
/// hauteur est libre.
class ServiceCard extends StatelessWidget {
  final Service service;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onTap;

  const ServiceCard({
    super.key,
    required this.service,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = service.hasDiscount;
    final discountPercent = hasDiscount
        ? (((service.price ?? 0) - (service.discountedPrice ?? 0)) /
                (service.price ?? 1) *
                100)
            .round()
        : 0;
    final categoryName = service.categoryName.trim();
    final rating = CardFormat.rating(service.rating);
    final reviewCount = service.reviewCount ?? 0;
    final toggle = onFavoriteToggle;

    // Prix : réel ou « Sur devis » (jamais « null »).
    final unit = service.isHourly ? ' / h' : '';
    final currentPrice = CardFormat.fcfa(hasDiscount ? service.discountedPrice : service.price);
    final priceText = (service.isQuoteBased || currentPrice == null) ? 'Sur devis' : '$currentPrice$unit';
    final oldPrice = hasDiscount ? CardFormat.fcfa(service.price) : null;

    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: TtGradients.wash),
      child: Center(
        child: Icon(Icons.handyman_outlined, size: 40, color: TtColors.primary.withValues(alpha: 0.7)),
      ),
    );

    Widget photo(bool bounded) {
      final stack = Stack(
        fit: StackFit.expand,
        children: [
          CardPhoto(url: service.imageUrl, fallback: fallback),
          Positioned(
            top: TtSpace.s2,
            left: TtSpace.s2,
            right: TtSpace.s2,
            child: Wrap(
              spacing: TtSpace.s1,
              runSpacing: TtSpace.s1,
              children: [
                if (hasDiscount && discountPercent > 0)
                  TratraBadge('-$discountPercent%', tone: TratraTone.accent, icon: Icons.local_offer_outlined),
                if (service.isUrgent)
                  const TratraBadge('Urgent', tone: TratraTone.danger, icon: Icons.bolt_rounded),
              ],
            ),
          ),
          if (toggle != null)
            Positioned(
              bottom: TtSpace.s1,
              right: TtSpace.s1,
              child: FavoriteToggleButton(isFavorite: isFavorite, onPressed: toggle),
            ),
        ],
      );
      return bounded ? Expanded(child: stack) : SizedBox(height: 120, child: stack);
    }

    return SizedBox(
      width: 196,
      child: TratraCard(
        margin: const EdgeInsets.all(TtSpace.s2),
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            return Column(
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                photo(bounded),
                Padding(
                  padding: const EdgeInsets.all(TtSpace.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        service.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.h3).copyWith(fontSize: 14, height: 1.25),
                      ),
                      if (categoryName.isNotEmpty || rating != null) ...[
                        const SizedBox(height: TtSpace.s1),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                categoryName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                              ),
                            ),
                            if (rating != null) ...[
                              const SizedBox(width: TtSpace.s2),
                              const Icon(Icons.star_rounded, size: 14, color: TtColors.accent),
                              const SizedBox(width: 2),
                              Text(
                                reviewCount > 0 ? '$rating ($reviewCount)' : rating,
                                style: TratraTheme.style(TtType.caption, color: TtColors.ink)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: TtSpace.s2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (oldPrice != null) ...[
                              Text(
                                oldPrice,
                                style: TratraTheme.style(TtType.caption, color: TtColors.ash)
                                    .copyWith(decoration: TextDecoration.lineThrough),
                              ),
                              const SizedBox(width: TtSpace.s1),
                            ],
                            Text(
                              priceText,
                              style: TratraTheme.style(TtType.title, color: TtColors.primaryDark)
                                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
