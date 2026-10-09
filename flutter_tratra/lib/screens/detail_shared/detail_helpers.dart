// Aides d'affichage partagées par la fiche service, le profil artisan et la
// messagerie. Affichage uniquement : aucune règle métier, aucun appel réseau.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/service.dart';

/// URL d'image réellement exploitable : http(s) valide et différente du
/// placeholder `via.placeholder.com` (que le modèle injecte quand un service n'a
/// pas de photo). Renvoie `null` quand il n'y a pas de vraie image.
String? realImageUrl(String? raw) {
  final u = (raw ?? '').trim();
  if (u.isEmpty) return null;
  final p = Uri.tryParse(u);
  if (p == null || !p.hasScheme || !(p.isScheme('http') || p.isScheme('https'))) {
    return null;
  }
  if (p.host == 'via.placeholder.com') return null;
  return u;
}

/// Sépare les milliers d'un nombre entier (espace insécable) : `15000` -> `15 000`.
String groupDigits(String digits) => digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );

/// Prix lisible issu de `Service.priceDisplay` (`15000F/h` -> `15 000 FCFA/h`).
/// Toute autre forme (« Sur devis », « Prix non spécifié ») est conservée telle quelle.
String formatServicePrice(Service s) {
  final raw = s.priceDisplay;
  final m = RegExp(r'^(\d+)F(/h)?$').firstMatch(raw);
  if (m == null) return raw.replaceAll('F', 'FCFA');
  return '${groupDigits(m.group(1)!)} FCFA${m.group(2) ?? ''}';
}

/// Message d'erreur présentable : conserve les messages français déjà produits par
/// `BaseApi.handleError`, sinon renvoie [fallback] (jamais de trace technique brute).
String friendlyError(Object e, {String fallback = 'Vérifiez votre connexion puis réessayez.'}) {
  final raw = e.toString();
  const prefix = 'Exception: ';
  if (raw.startsWith(prefix)) {
    final msg = raw.substring(prefix.length).trim();
    if (msg.isNotEmpty && msg.length <= 90) return msg;
  }
  return fallback;
}

/// Image réelle ou, à défaut, panneau de marque (jamais de photo de stock).
class ServiceCover extends StatelessWidget {
  const ServiceCover({super.key, required this.url, this.iconSize = 32, this.dark = false});

  final String? url;
  final double iconSize;

  /// Repli sombre (en-tête immersif) plutôt que lavis vert clair.
  final bool dark;

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(gradient: dark ? TtGradients.night : TtGradients.wash),
        child: Center(
          child: Icon(
            Icons.handyman_outlined,
            size: iconSize,
            color: dark ? TtColors.accent : TtColors.primary.withValues(alpha: 0.7),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return _fallback();
    return CachedNetworkImage(
      imageUrl: u,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: TtMotion.base,
      placeholder: (_, __) => const ColoredBox(color: TtColors.lineSoft),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }
}

/// Note en étoiles accent. À n'afficher que si une note réelle existe (> 0) :
/// ce widget ne fabrique jamais de valeur par défaut.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.reviewCount,
    this.size = 16,
    this.onDark = false,
  });

  final double rating;
  final int? reviewCount;
  final double size;
  final bool onDark;

  Widget _star(double fill, Color empty) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.star_rounded, size: size, color: empty),
          if (fill >= 0.75)
            Icon(Icons.star_rounded, size: size, color: TtColors.accent)
          else if (fill >= 0.25)
            Icon(Icons.star_half_rounded, size: size, color: TtColors.accent),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = rating.clamp(0.0, 5.0).toDouble();
    final count = reviewCount ?? 0;
    final label = value.toStringAsFixed(1).replaceAll('.', ',');
    final empty = onDark ? Colors.white.withValues(alpha: 0.28) : TtColors.line;
    final strong = onDark ? Colors.white : TtColors.ink;
    final soft = onDark ? Colors.white70 : TtColors.ash;

    return Semantics(
      label: 'Note de $label sur 5${count > 0 ? ', $count avis' : ''}',
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (var i = 0; i < 5; i++) _star(value - i, empty)],
            ),
            Text(
              label,
              style: TratraTheme.style(TtType.bodySm, color: strong).copyWith(fontWeight: FontWeight.w700),
            ),
            if (count > 0)
              Text('($count avis)', style: TratraTheme.style(TtType.caption, color: soft)),
          ],
        ),
      ),
    );
  }
}
