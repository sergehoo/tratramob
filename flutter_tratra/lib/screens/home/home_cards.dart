// lib/screens/home/home_cards.dart
//
// Cartes de l'accueil : service et artisan proche. Classes publiques conservées
// (mêmes noms, mêmes paramètres requis) ; les ajouts sont tous optionnels et ne portent
// que sur des données réelles de l'API (artisan, note, distance) : rien n'est inventé.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/design/design.dart';

import 'home_models.dart';

/// Image réelle ou, à défaut (URL absente ou illisible), panneau de marque : jamais de
/// photo de remplissage téléchargée.
class HomeImage extends StatelessWidget {
  const HomeImage({super.key, required this.url, this.icon = Icons.handyman_outlined});

  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: TtGradients.wash),
      child: Center(child: Icon(icon, size: 40, color: TtColors.primary.withValues(alpha: 0.45))),
    );
    if (url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: TtMotion.base,
      placeholder: (_, __) => const ColoredBox(color: TtColors.lineSoft),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// Bouton rond posé sur une image (favori, partage) : cible tactile de 44 dp.
class HomeRoundAction extends StatelessWidget {
  const HomeRoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = TtColors.ink,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Material(
          color: TtColors.surface.withValues(alpha: 0.94),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: SizedBox(
              width: TtLayout.touchTarget,
              height: TtLayout.touchTarget,
              child: Icon(icon, size: 20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Voile de lisibilité au bas d'une image.
class _ImageScrim extends StatelessWidget {
  const _ImageScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            TtColors.night.withValues(alpha: 0.05),
            TtColors.night.withValues(alpha: 0.4),
          ],
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.rating});
  final double rating;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: TtColors.surface.withValues(alpha: 0.94), shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 15, color: TtColors.accentDark),
            const SizedBox(width: 3),
            Text(
              rating.toStringAsFixed(1).replaceAll('.', ','),
              style: TratraTheme.style(TtType.caption).copyWith(fontWeight: FontWeight.w700, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtisanLine extends StatelessWidget {
  const _ArtisanLine({required this.artisan});
  final HomeArtisanBrief artisan;

  @override
  Widget build(BuildContext context) {
    final name = artisan.displayName ?? '';
    return Row(
      children: [
        TratraAvatar(name: name, photoUrl: artisan.photoUrl, size: 26, online: artisan.online),
        const SizedBox(width: TtSpace.s2),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (artisan.verified) ...[
          const SizedBox(width: 4),
          const Icon(Icons.verified_rounded, size: 15, color: TtColors.primary, semanticLabel: 'Profil vérifié'),
        ],
        // Badges cumulables Expert / Sûr (compacts : l'icône suffit, le libellé est en infobulle et lu par les lecteurs d'écran).
        for (final code in artisan.badges.where((c) => c == 'EXPERT' || c == 'SUR')) ...[
          const SizedBox(width: 3),
          Tooltip(
            message: trustBadgeInfo[code]!.help,
            child: Icon(trustBadgeInfo[code]!.icon, size: 15, color: code == 'SUR' ? TtColors.night : TtColors.accentDark, semanticLabel: 'Badge ${trustBadgeInfo[code]!.label}'),
          ),
        ],
      ],
    );
  }
}

/// Carte d'un service (liste « Services »).
class ServiceCardPremium extends StatelessWidget {
  const ServiceCardPremium({
    super.key,
    required this.title,
    required this.category,
    required this.imageUrl,
    required this.basePrice,
    required this.discountedPrice,
    required this.rating,
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    required this.onTap,
    required this.onBook,
    this.badgeText,
    this.priceLabel,
    this.artisan,
  });

  final String title;
  final String category;
  final String imageUrl;
  final double basePrice;
  final double discountedPrice;

  /// Note réelle ; `null` (ou ≤ 0) => aucune note affichée.
  final double? rating;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onTap;
  final VoidCallback onBook;
  final String? badgeText;

  /// Libellé de prix fidèle au type de tarif (« Sur devis », « 5 000 FCFA/h »…).
  /// S'il est fourni, il remplace l'affichage `basePrice` / `discountedPrice`.
  final String? priceLabel;

  /// Résumé réel de l'artisan (nom, vérifié, en ligne), si l'API le fournit.
  final HomeArtisanBrief? artisan;

  @override
  Widget build(BuildContext context) {
    final hasDiscount = priceLabel == null && basePrice > 0 && discountedPrice < basePrice;
    final discountPct = hasDiscount ? ((basePrice - discountedPrice) / basePrice * 100).round() : 0;
    final rawRating = rating;
    final r = (rawRating != null && rawRating > 0) ? rawRating : null;
    final mainPrice =
        priceLabel ?? '${homeFormatFcfa(hasDiscount ? discountedPrice : basePrice)} FCFA';
    final a = artisan;

    return SizedBox(
      width: 280,
      child: TratraCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HomeImage(url: imageUrl),
                  const _ImageScrim(),
                  Positioned(
                    left: TtSpace.s3,
                    top: TtSpace.s3,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (badgeText != null)
                          TratraBadge(badgeText!, tone: TratraTone.accent, icon: Icons.bolt_rounded),
                        if (hasDiscount) TratraBadge('−$discountPct %', tone: TratraTone.danger),
                      ],
                    ),
                  ),
                  if (r != null)
                    Positioned(right: TtSpace.s3, top: TtSpace.s3, child: _RatingPill(rating: r)),
                  Positioned(
                    right: TtSpace.s1,
                    bottom: TtSpace.s1,
                    child: Row(
                      children: [
                        HomeRoundAction(
                          icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                          color: isFavorite ? TtColors.danger : TtColors.ink,
                          onTap: onFavorite,
                        ),
                        const SizedBox(width: TtSpace.s1),
                        HomeRoundAction(
                          icon: Icons.ios_share_rounded,
                          tooltip: 'Partager ce service',
                          color: TtColors.primaryDark,
                          onTap: onShare,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category.isNotEmpty) ...[
                      Text(
                        category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.eyebrow, color: TtColors.primaryDark),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TratraTheme.style(TtType.h3).copyWith(fontSize: 16),
                    ),
                    if (a != null && a.hasName) ...[
                      const SizedBox(height: 6),
                      _ArtisanLine(artisan: a),
                    ],
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasDiscount)
                                Text(
                                  '${homeFormatFcfa(basePrice)} FCFA',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TratraTheme.style(TtType.caption, color: TtColors.ash)
                                      .copyWith(decoration: TextDecoration.lineThrough),
                                ),
                              Text(
                                mainPrice,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TratraTheme.style(TtType.h3, color: TtColors.primaryDark)
                                    .copyWith(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: TtSpace.s2),
                        TratraButton(
                          label: 'Réserver',
                          onPressed: onBook,
                        ),
                      ],
                    ),
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

/// Carte d'un service proche de la personne (liste « Pros à proximité »). Le bouton
/// principal ouvre la fiche du service (même action qu'avant).
class ArtisanCardPremium extends StatelessWidget {
  const ArtisanCardPremium({
    super.key,
    required this.title,
    required this.subtitle,
    required this.priceText,
    required this.imageUrl,
    required this.isFavorite,
    required this.onFavorite,
    required this.onShare,
    required this.onPrimary,
    this.badgeText,
    this.primaryLabel = 'Voir',
    this.artisan,
  });

  final String title;
  final String subtitle;
  final String priceText;
  final String imageUrl;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onPrimary;

  /// Étiquette posée sur l'image (ex. « Vérifié » uniquement si l'API le confirme).
  final String? badgeText;

  /// Libellé du bouton principal (il ouvre la fiche du service).
  final String primaryLabel;

  /// Résumé réel de l'artisan (photo, note, distance, commune), si l'API le fournit.
  final HomeArtisanBrief? artisan;

  @override
  Widget build(BuildContext context) {
    final a = artisan;
    final rating = a?.rating;
    final distance = a?.distanceKm;
    final commune = a?.commune;
    final hasMeta = (rating != null) || (distance != null) || (commune != null);

    return SizedBox(
      width: 268,
      child: TratraCard(
        padding: EdgeInsets.zero,
        onTap: onPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 116,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HomeImage(url: imageUrl),
                  const _ImageScrim(),
                  Positioned(
                    left: TtSpace.s3,
                    top: TtSpace.s3,
                    right: TtSpace.s3,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (badgeText != null)
                          TratraBadge(badgeText!, tone: TratraTone.primary, icon: Icons.verified_rounded),
                        if (a != null && a.online) const TratraBadge('En ligne', tone: TratraTone.success, dot: true),
                      ],
                    ),
                  ),
                  Positioned(
                    right: TtSpace.s1,
                    bottom: TtSpace.s1,
                    child: Row(
                      children: [
                        HomeRoundAction(
                          icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                          color: isFavorite ? TtColors.danger : TtColors.ink,
                          onTap: onFavorite,
                        ),
                        const SizedBox(width: TtSpace.s1),
                        HomeRoundAction(
                          icon: Icons.ios_share_rounded,
                          tooltip: 'Partager ce service',
                          color: TtColors.primaryDark,
                          onTap: onShare,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (a != null && a.hasName) ...[
                          TratraAvatar(name: a.displayName!, photoUrl: a.photoUrl, size: 40),
                          const SizedBox(width: TtSpace.s3),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TratraTheme.style(TtType.h3).copyWith(fontSize: 16),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (hasMeta) ...[
                      const SizedBox(height: TtSpace.s2),
                      Row(
                        children: [
                          if (rating != null) ...[
                            const Icon(Icons.star_rounded, size: 16, color: TtColors.accentDark),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1).replaceAll('.', ','),
                              style: TratraTheme.style(TtType.caption, color: TtColors.ink)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: TtSpace.s3),
                          ],
                          if (distance != null) ...[
                            const Icon(Icons.near_me_rounded, size: 14, color: TtColors.ash),
                            const SizedBox(width: 3),
                            Text(
                              homeFormatKm(distance),
                              style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft),
                            ),
                            const SizedBox(width: TtSpace.s3),
                          ],
                          if (commune != null)
                            Flexible(
                              child: Text(
                                commune,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TratraTheme.style(TtType.h3, color: TtColors.primaryDark)
                                .copyWith(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: TtSpace.s2),
                        TratraButton(
                          label: primaryLabel,
                          onPressed: onPrimary,
                        ),
                      ],
                    ),
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
