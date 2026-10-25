// widgets/artisan_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/artisan.dart';
import 'card_parts.dart';
import 'package:flutter_tratra/statuses/status_presence.dart';

/// Carte d'artisan (photo réelle sinon initiales, disponibilité, nom, métier, note, tarif).
///
/// `onTap` : rend la carte cliquable. `onFavoriteToggle` : affiche le bouton favori.
/// Passer `null` pour l'un ou l'autre retire l'interaction correspondante (jamais de
/// bouton sans action). La carte s'adapte à la hauteur disponible (≈ 200 dp en liste
/// horizontale) ; la zone photo occupe la place restante, ou 100 dp si la hauteur est libre.
class ArtisanCard extends StatelessWidget {
  final Artisan artisan;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onTap;

  const ArtisanCard({
    super.key,
    required this.artisan,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final toggle = onFavoriteToggle;
    final profession = artisan.profession.trim();
    final rating = CardFormat.rating(artisan.rating);
    final rate = CardFormat.fcfa(artisan.hourlyRate);
    final distance = CardFormat.distanceKm(artisan.distance);

    Widget header(bool bounded) {
      final stack = Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(decoration: BoxDecoration(gradient: TtGradients.wash)),
          // Marge haute : l'avatar ne chevauche jamais le badge de disponibilité.
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Center(
              child: StatusAvatar(
                userId: artisan.userId,
                name: artisan.name,
                photoUrl: CardPhoto.isUsable(artisan.imageUrl) ? artisan.imageUrl : null,
                size: 64,
                online: artisan.isAvailable,
              ),
            ),
          ),
          Positioned(
            top: TtSpace.s2,
            left: TtSpace.s2,
            right: TtSpace.s2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TratraBadge(
                artisan.isAvailable ? 'Disponible' : 'Indisponible',
                tone: artisan.isAvailable ? TratraTone.success : TratraTone.gray,
                dot: true,
              ),
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
      return bounded ? Expanded(child: stack) : SizedBox(height: 100, child: stack);
    }

    return SizedBox(
      width: 176,
      child: TratraCard(
        margin: const EdgeInsets.only(right: TtSpace.s4),
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            return Column(
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(bounded),
                Padding(
                  padding: const EdgeInsets.all(TtSpace.s3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              artisan.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TratraTheme.style(TtType.h3).copyWith(fontSize: 14, height: 1.25),
                            ),
                          ),
                          if (artisan.isCertified) ...[
                            const SizedBox(width: TtSpace.s1),
                            const Icon(Icons.verified, size: 14, color: TtColors.primary, semanticLabel: 'Certifié'),
                          ],
                        ],
                      ),
                      if (profession.isNotEmpty)
                        Text(
                          profession,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                        ),
                      const SizedBox(height: TtSpace.s2),
                      if (rating != null)
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: TtColors.accent),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                artisan.reviews > 0 ? '$rating (${artisan.reviews})' : rating,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TratraTheme.style(TtType.caption, color: TtColors.ink)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Pas encore noté',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                        ),
                      if (rate != null || distance != null) ...[
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              if (rate != null)
                                TextSpan(
                                  text: '$rate / h',
                                  style: TratraTheme.style(TtType.caption, color: TtColors.primaryDark)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                              if (rate != null && distance != null) const TextSpan(text: ' · '),
                              if (distance != null) TextSpan(text: distance),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                        ),
                      ],
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
