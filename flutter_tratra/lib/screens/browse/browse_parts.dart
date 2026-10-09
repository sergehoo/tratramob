// Briques partagées par les écrans « Toutes les catégories », « Artisans à proximité »
// et « Recherche ». Composées localement avec les jetons du Design System : aucune
// valeur de marque en dur, aucune donnée fictive.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';

/// Renvoie l'URL d'image à afficher, ou `null` si l'API n'en fournit pas d'exploitable
/// (vide, relative, schéma non http/https). Les anciens substituts `via.placeholder.com`
/// ne sont jamais affichés : on montre le repli de marque à la place.
String? browseImageUrl(String? raw) {
  final u = (raw ?? '').trim();
  if (u.isEmpty) return null;
  final parsed = Uri.tryParse(u);
  if (parsed == null ||
      !parsed.hasScheme ||
      !(parsed.isScheme('http') || parsed.isScheme('https'))) {
    return null;
  }
  if (parsed.host == 'via.placeholder.com') return null;
  return u;
}

/// Message d'erreur lisible : retire le préfixe technique « Exception: » et ramène
/// les erreurs réseau à une phrase claire. Le détail serveur (code, message) est conservé.
String browseErrorMessage(Object? error) {
  var message = '${error ?? ''}'.trim();
  if (message.startsWith('Exception:')) {
    message = message.substring('Exception:'.length).trim();
  }
  const networkMarkers = [
    'SocketException',
    'ClientException',
    'TimeoutException',
    'Failed host lookup',
    'Connection refused',
    'Connection closed',
  ];
  if (networkMarkers.any(message.contains)) {
    return 'Connexion impossible. Vérifiez votre réseau puis réessayez.';
  }
  if (message.isEmpty) return 'Une erreur inattendue est survenue. Réessayez dans un instant.';
  return message.length > 180 ? '${message.substring(0, 177)}…' : message;
}

/// Image réelle (CachedNetworkImage) ou repli de marque (dégradé doux + pictogramme)
/// quand l'API n'en fournit pas ou que le chargement échoue. Décorative : le texte
/// voisin porte le sens.
class BrowseImage extends StatelessWidget {
  const BrowseImage({
    super.key,
    required this.url,
    required this.fallbackIcon,
    this.width,
    this.height,
  });

  final String? url;
  final IconData fallbackIcon;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final valid = browseImageUrl(url);
    final fallback = _BrowseImageFallback(icon: fallbackIcon);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: valid == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: valid,
                fit: BoxFit.cover,
                fadeInDuration: reduceMotion ? Duration.zero : TtMotion.base,
                fadeOutDuration: reduceMotion ? Duration.zero : TtMotion.fast,
                placeholder: (_, __) => const ColoredBox(color: TtColors.lineSoft),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class _BrowseImageFallback extends StatelessWidget {
  const _BrowseImageFallback({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: TtGradients.wash),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          final size = side.isFinite ? (side * 0.36).clamp(20.0, 36.0).toDouble() : 28.0;
          return Center(child: Icon(icon, size: size, color: TtColors.primary));
        },
      ),
    );
  }
}

/// Centre un contenu (état vide / erreur) tout en le gardant « tirable » pour le
/// `RefreshIndicator` parent.
class BrowseCenteredScroll extends StatelessWidget {
  const BrowseCenteredScroll({super.key, required this.child});
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

/// Apparition en fondu discrète (TtMotion.slow), neutralisée si l'utilisateur réduit
/// les animations. À utiliser avec une `key` propre à chaque état pour ne rejouer
/// l'animation qu'au changement d'état (pas à la pagination).
class BrowseFadeIn extends StatelessWidget {
  const BrowseFadeIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: TtMotion.slow,
      curve: TtMotion.emphasized,
      child: child,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
    );
  }
}
