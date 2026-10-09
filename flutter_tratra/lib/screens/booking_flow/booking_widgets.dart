// Briques d'affichage partagées par la réservation, le paiement et le suivi.
// Composées uniquement avec les jetons du Design System : aucune règle métier ici.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Limite la largeur du contenu et le centre (tablettes, grands écrans).
class BookingContentWidth extends StatelessWidget {
  const BookingContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // heightFactor: 1 — sans lui, le conteneur occupe toute la hauteur offerte
    // (cas d'une barre posée en bottomNavigationBar) et écrase le contenu de l'écran.
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: TtLayout.compactMax),
        child: child,
      ),
    );
  }
}

/// Sur-titre en pastille majuscule à fort interlettrage (comme sur la landing).
class BookingEyebrow extends StatelessWidget {
  const BookingEyebrow(this.label, {super.key, this.onNight = false});
  final String label;
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    final fg = onNight ? TtColors.accent : TtColors.primaryDark;
    final bg = onNight ? Colors.white.withValues(alpha: 0.1) : TtColors.primarySoft;
    return DecoratedBox(
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s3, vertical: TtSpace.s1 + 2),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TratraTheme.style(TtType.eyebrow, color: fg),
        ),
      ),
    );
  }
}

/// Apparition douce (fondu + léger glissement), échelonnée par `index`.
/// Neutralisée quand l'utilisateur réduit les animations.
class BookingReveal extends StatefulWidget {
  const BookingReveal({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<BookingReveal> createState() => _BookingRevealState();
}

class _BookingRevealState extends State<BookingReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: TtMotion.slow);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _controller, curve: TtMotion.emphasized);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    final steps = widget.index.clamp(0, 6);
    _timer = Timer(Duration(milliseconds: 60 * steps), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Carte d'étape : pastille numérotée (ou icône) + titre, puis le contenu.
class BookingStepCard extends StatelessWidget {
  const BookingStepCard({
    super.key,
    required this.title,
    required this.child,
    this.step,
    this.icon,
  });

  final String title;
  final Widget child;
  final int? step;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final badge = step != null
        ? DecoratedBox(
            decoration: const BoxDecoration(color: TtColors.primaryDark, shape: BoxShape.circle),
            child: SizedBox(
              width: TtSpace.s8 - TtSpace.s1,
              height: TtSpace.s8 - TtSpace.s1,
              child: Center(
                child: Text('$step', style: TratraTheme.style(TtType.title, color: Colors.white).copyWith(height: 1)),
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: TtRadius.controlAll),
            child: SizedBox(
              width: TtSpace.s8 - TtSpace.s1,
              height: TtSpace.s8 - TtSpace.s1,
              child: Icon(icon ?? Icons.event_note_outlined, size: TtSpace.s5, color: TtColors.primaryDark),
            ),
          );

    return TratraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: badge),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.h3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: TtSpace.s4),
          child,
        ],
      ),
    );
  }
}

/// Ligne « libellé — valeur » d'un récapitulatif.
class BookingInfoRow extends StatelessWidget {
  const BookingInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.strike = false,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;

  /// Ligne de total : valeur en titre de la marque.
  final bool strong;

  /// Valeur barrée (ancien prix).
  final bool strike;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TratraTheme.style(strong ? TtType.title : TtType.bodySm, color: strong ? TtColors.ink : TtColors.ash);
    final valueStyle = strong
        ? TratraTheme.style(TtType.h3, color: valueColor ?? TtColors.primaryDark)
        : TratraTheme.style(TtType.body, color: valueColor ?? TtColors.ink).copyWith(
            fontWeight: FontWeight.w600,
            decoration: strike ? TextDecoration.lineThrough : null,
            decorationColor: TtColors.fog,
          );
    return Semantics(
      container: true,
      label: '$label : $value',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: TtSpace.s5 - 2, color: TtColors.fog),
            ),
            const SizedBox(width: TtSpace.s2),
          ],
          Flexible(flex: 2, child: Text(label, style: labelStyle)),
          const SizedBox(width: TtSpace.s4),
          Flexible(
            flex: 3,
            child: Text(value, textAlign: TextAlign.end, maxLines: 4, overflow: TextOverflow.ellipsis, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

/// Barre d'action basse collante : fond blanc, filet haut, zone sûre.
class BookingStickyBar extends StatelessWidget {
  const BookingStickyBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(top: BorderSide(color: TtColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: BookingContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s3),
            child: child,
          ),
        ),
      ),
    );
  }
}
