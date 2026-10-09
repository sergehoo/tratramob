// lib/widgets/card_parts.dart
// Briques partagées par les cartes historiques (ServiceCard, ArtisanCard) :
// formats d'affichage (FCFA, note, distance), photo réelle avec repli de marque
// et bouton favori. Affichage uniquement : aucune règle métier ici.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Formats d'affichage alignés sur le web (frontend/src/lib/format.ts).
abstract final class CardFormat {
  /// 12500 -> « 12 500 FCFA » (espaces insécables). Valeur absente ou <= 0 -> null.
  static String? fcfa(num? value) {
    if (value == null || value.isNaN || value.isInfinite || value <= 0) return null;
    final digits = value.round().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
      out.write(digits[i]);
    }
    return '$out FCFA';
  }

  /// Note sur 5 avec une décimale et virgule française (« 4,5 »), ou null si aucune note réelle.
  static String? rating(double? value) {
    if (value == null || value.isNaN || value <= 0) return null;
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Distance en kilomètres (« 2,3 km »), ou null si inconnue (<= 0).
  static String? distanceKm(double? km) {
    if (km == null || km.isNaN || km <= 0) return null;
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }
}

/// Photo réelle d'une carte. Sans URL exploitable (vide, non http(s), image de
/// substitution « via.placeholder.com » fabriquée par le modèle) ou si le
/// chargement échoue, affiche `fallback` : jamais de photo de stock.
class CardPhoto extends StatelessWidget {
  const CardPhoto({super.key, required this.url, required this.fallback});

  final String? url;
  final Widget fallback;

  static bool isUsable(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return false;
    return uri.host != 'via.placeholder.com';
  }

  @override
  Widget build(BuildContext context) {
    if (!isUsable(url)) return fallback;
    return ExcludeSemantics(
      child: CachedNetworkImage(
        imageUrl: url!.trim(),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        fadeInDuration: TtMotion.base,
        placeholder: (_, __) => const ColoredBox(color: TtColors.lineSoft),
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

/// Bouton coeur posé sur une photo : cible tactile >= 44, libellé accessible.
/// Rendu uniquement quand l'écran fournit une action réelle.
class FavoriteToggleButton extends StatelessWidget {
  const FavoriteToggleButton({super.key, required this.isFavorite, required this.onPressed});

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IconButton(
      tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: TtColors.surface.withValues(alpha: 0.92),
        fixedSize: const Size.square(TtLayout.touchTarget),
        minimumSize: const Size.square(TtLayout.touchTarget),
      ),
      icon: AnimatedSwitcher(
        duration: disableMotion ? Duration.zero : TtMotion.fast,
        switchInCurve: TtMotion.emphasized,
        child: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey<bool>(isFavorite),
          size: 20,
          color: isFavorite ? TtColors.danger : TtColors.ink,
        ),
      ),
    );
  }
}
