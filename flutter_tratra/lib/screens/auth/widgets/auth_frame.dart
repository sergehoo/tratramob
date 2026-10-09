// Cadre commun des écrans d'authentification (connexion, inscription), miroir de
// `AuthFrame` côté web : fond canvas avec halos de marque, en-tête de marque,
// sur-titre en pastille, titre Montserrat souligné de jaune, puis formulaire en carte.
// Ce fichier ne porte AUCUNE logique métier : il ne fait que cadrer son contenu.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Message lisible à partir d'une exception (affichage uniquement) : retire le préfixe
/// technique « Exception: » et reformule les coupures réseau.
String authErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('TimeoutException')) {
    return 'Impossible de joindre le service. Vérifiez votre connexion puis réessayez.';
  }
  const prefix = 'Exception: ';
  return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
}

/// Durée d'animation, ramenée à zéro quand l'utilisateur réduit les animations.
Duration authMotion(BuildContext context, Duration duration) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? Duration.zero
        : duration;

/// Cadre d'un écran d'authentification.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.onBack,
  });

  /// Sur-titre en pastille (majuscules).
  final String eyebrow;

  /// Unique titre de l'écran.
  final String title;
  final String subtitle;

  /// Formulaire, rendu dans une carte blanche.
  final Widget child;

  /// Lien secondaire sous la carte (vers l'autre écran d'authentification).
  final Widget? footer;

  /// Si fourni, affiche un bouton « Retour » dans l'en-tête.
  final VoidCallback? onBack;

  static const double _maxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= TtLayout.compactMax
        ? TtLayout.gutterDesktop
        : TtLayout.gutterMobile;

    return Scaffold(
      backgroundColor: TtColors.canvas,
      body: Stack(
        children: [
          const Positioned.fill(child: _BrandHalo()),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding:
                  EdgeInsets.fromLTRB(gutter, TtSpace.s3, gutter, TtSpace.s8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: _Rise(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BrandHeader(onBack: onBack),
                        const SizedBox(height: TtSpace.s8),
                        _Eyebrow(eyebrow),
                        const SizedBox(height: TtSpace.s4),
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: TratraTheme.style(TtType.displayLg),
                          ),
                        ),
                        const SizedBox(height: TtSpace.s3),
                        const _AccentBar(),
                        const SizedBox(height: TtSpace.s3),
                        Text(
                          subtitle,
                          style: TratraTheme.style(TtType.body,
                              color: TtColors.inkSoft),
                        ),
                        const SizedBox(height: TtSpace.s6),
                        TratraCard(child: child),
                        if (footer != null) ...[
                          const SizedBox(height: TtSpace.s5),
                          Center(child: footer),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Message d'erreur / d'avertissement du formulaire : apparaît en douceur, annoncé aux
/// lecteurs d'écran. `message == null` => rien n'est affiché.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.message,
    this.title,
    this.tone = TratraAlertTone.danger,
    this.onDismiss,
  });

  final String? message;
  final String? title;
  final TratraAlertTone tone;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AnimatedSize(
      duration: authMotion(context, TtMotion.base),
      curve: TtMotion.emphasized,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: TtSpace.s4),
              child: TratraAlert(
                tone: tone,
                title: title,
                message: text,
                onDismiss: onDismiss,
              ),
            ),
    );
  }
}

/// En-tête de marque : pastille logo + mot-symbole, bouton « Retour » optionnel.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final wordmark =
        TratraTheme.style(TtType.h2).copyWith(fontWeight: FontWeight.w800);
    return Row(
      children: [
        const Hero(tag: 'app-logo', child: TratraBrandMark(size: 44)),
        const SizedBox(width: TtSpace.s3),
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              style: wordmark,
              children: [
                const TextSpan(text: 'Tra'),
                TextSpan(
                    text: 'tra',
                    style: wordmark.copyWith(color: TtColors.primaryDark)),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (onBack != null)
          TratraButton(
            label: 'Retour',
            variant: TratraButtonVariant.ghost,
            leading: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
      ],
    );
  }
}

/// Sur-titre : pastille verte douce, point jaune, majuscules très espacées.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: TtColors.primarySoft,
              shape: StadiumBorder(
                side:
                    BorderSide(color: TtColors.primary.withValues(alpha: 0.18)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: TtSpace.s3, vertical: TtSpace.s1 + 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                        color: TtColors.accent, shape: BoxShape.circle),
                    child: SizedBox(width: 6, height: 6),
                  ),
                  const SizedBox(width: TtSpace.s2),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TratraTheme.style(TtType.eyebrow,
                          color: TtColors.primaryDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Soulignement jaune de marque sous le titre.
class _AccentBar extends StatelessWidget {
  const _AccentBar();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: TtColors.accent, borderRadius: TtRadius.pillAll),
        child: const SizedBox(width: TtSpace.s10, height: TtSpace.s1),
      ),
    );
  }
}

/// Fond décoratif : deux halos radiaux (vert en haut à gauche, jaune en bas à droite),
/// sans filtre de flou (léger à peindre) et ignorés des lecteurs d'écran.
class _BrandHalo extends StatelessWidget {
  const _BrandHalo();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -140,
              left: -120,
              child: _Blob(color: TtColors.primary, alpha: 0.2, size: 380),
            ),
            Positioned(
              bottom: -130,
              right: -110,
              child: _Blob(color: TtColors.accent, alpha: 0.16, size: 320),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.alpha, required this.size});
  final Color color;
  final double alpha;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ),
      ),
      child: SizedBox(width: size, height: size),
    );
  }
}

/// Apparition discrète (fondu + léger glissement vers le haut), neutralisée quand
/// l'utilisateur réduit les animations.
class _Rise extends StatelessWidget {
  const _Rise({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: TtMotion.slow,
      curve: TtMotion.emphasized,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
            offset: Offset(0, (1 - t) * TtSpace.s4), child: child),
      ),
    );
  }
}
