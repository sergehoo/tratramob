// widgets/promotion_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Bandeau d'offre. Tout le contenu est fourni par l'appelant (offre réelle issue de
/// l'API) : sans `title` ni `message`, rien n'est affiché, et le bouton n'apparaît que si
/// `actionLabel` ET `onAction` (destination réelle) sont fournis.
class PromotionBanner extends StatelessWidget {
  const PromotionBanner({
    super.key,
    this.eyebrow,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.local_offer_outlined,
  });

  /// Sur-titre en pastille (ex. nom de l'opération), optionnel.
  final String? eyebrow;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_has(title) && !_has(message)) return const SizedBox.shrink();

    final disableMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final showAction = _has(actionLabel) && onAction != null;

    final banner = TratraCard(
      variant: TratraCardVariant.night,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -28,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TtColors.accent.withValues(alpha: 0.1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(TtSpace.s5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_has(eyebrow)) ...[
                        DecoratedBox(
                          decoration: ShapeDecoration(
                            color: TtColors.accent.withValues(alpha: 0.16),
                            shape: const StadiumBorder(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Text(
                              eyebrow!.toUpperCase(),
                              style: TratraTheme.style(TtType.eyebrow, color: TtColors.accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: TtSpace.s3),
                      ],
                      if (_has(title))
                        Semantics(
                          header: true,
                          child: Text(
                            title!,
                            style: TratraTheme.style(TtType.h3, color: Colors.white),
                          ),
                        ),
                      if (_has(title) && _has(message)) const SizedBox(height: TtSpace.s2),
                      if (_has(message))
                        Text(
                          message!,
                          style: TratraTheme.style(TtType.bodySm, color: Colors.white70).copyWith(fontSize: 14),
                        ),
                      if (showAction) ...[
                        const SizedBox(height: TtSpace.s4),
                        TratraButton(
                          label: actionLabel!,
                          variant: TratraButtonVariant.accent,
                          size: TratraButtonSize.sm,
                          trailing: const Icon(Icons.arrow_forward_rounded),
                          onPressed: onAction,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: TtSpace.s4),
                ExcludeSemantics(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: TtColors.accent,
                      borderRadius: TtRadius.panelAll,
                    ),
                    child: Icon(icon, color: TtColors.ink, size: 28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: disableMotion ? Duration.zero : TtMotion.slow,
      curve: TtMotion.emphasized,
      child: banner,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
      ),
    );
  }
}
