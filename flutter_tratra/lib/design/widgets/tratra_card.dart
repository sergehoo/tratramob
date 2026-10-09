import 'package:flutter/material.dart';

import '../tokens.dart';

enum TratraCardVariant { standard, flat, soft, accent, night }

/// Surface de la marque (miroir de `Card` côté web). `radius` : `TtRadius.card` (24)
/// pour les cartes éditoriales, `TtRadius.panel` (16) pour les lignes denses.
class TratraCard extends StatelessWidget {
  const TratraCard({
    super.key,
    required this.child,
    this.variant = TratraCardVariant.standard,
    this.padding = const EdgeInsets.all(20),
    this.radius = TtRadius.card,
    this.onTap,
    this.margin,
    this.semanticLabel,
  });

  final Widget child;
  final TratraCardVariant variant;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final String? semanticLabel;

  /// Padding compact pour les lignes de liste.
  static const EdgeInsets compact = EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    final (bg, border, shadow) = switch (variant) {
      TratraCardVariant.standard => (TtColors.surface, TtColors.lineSoft, TtShadows.soft),
      TratraCardVariant.flat => (TtColors.surface, TtColors.line, const <BoxShadow>[]),
      TratraCardVariant.soft => (
          TtColors.primarySoft.withValues(alpha: 0.6),
          TtColors.primary.withValues(alpha: 0.1),
          const <BoxShadow>[],
        ),
      TratraCardVariant.accent => (
          TtColors.accentSoft,
          TtColors.accent.withValues(alpha: 0.4),
          const <BoxShadow>[],
        ),
      TratraCardVariant.night => (TtColors.night, Colors.white.withValues(alpha: 0.1), TtShadows.strong),
    };
    final radiusAll = BorderRadius.circular(radius);

    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(onTap: onTap, borderRadius: radiusAll, child: body);
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radiusAll,
        boxShadow: shadow,
      ),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: radiusAll, side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: variant == TratraCardVariant.night
            ? DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: body)
            : body,
      ),
    );

    final wrapped = margin == null ? card : Padding(padding: margin!, child: card);
    if (semanticLabel == null) return wrapped;
    return Semantics(container: true, label: semanticLabel, child: wrapped);
  }
}
