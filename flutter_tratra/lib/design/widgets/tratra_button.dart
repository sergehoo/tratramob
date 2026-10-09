import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum TratraButtonVariant { primary, accent, night, soft, outline, ghost, danger }

enum TratraButtonSize { sm, md, lg }

/// Bouton de la marque (miroir de `Button` côté web) : pilule, cible tactile ≥ 44,
/// retour d'appui discret, état de chargement. `onPressed == null` => désactivé.
class TratraButton extends StatefulWidget {
  const TratraButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = TratraButtonVariant.primary,
    this.size = TratraButtonSize.md,
    this.loading = false,
    this.block = false,
    this.leading,
    this.trailing,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final TratraButtonVariant variant;
  final TratraButtonSize size;

  /// Affiche un spinner et neutralise les appuis (action asynchrone en cours).
  final bool loading;

  /// Occupe toute la largeur disponible.
  final bool block;
  final Widget? leading;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  State<TratraButton> createState() => _TratraButtonState();
}

class _TratraButtonState extends State<TratraButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  ({Color bg, Color fg, BorderSide? border, List<BoxShadow> shadow}) get _look {
    switch (widget.variant) {
      case TratraButtonVariant.primary:
        return (bg: TtColors.primaryDark, fg: Colors.white, border: null, shadow: TtShadows.glow);
      case TratraButtonVariant.accent:
        return (bg: TtColors.accent, fg: TtColors.ink, border: null, shadow: TtShadows.glowAccent);
      case TratraButtonVariant.night:
        return (bg: TtColors.night, fg: Colors.white, border: null, shadow: TtShadows.strong);
      case TratraButtonVariant.soft:
        return (bg: TtColors.primarySoft, fg: TtColors.primaryDark, border: null, shadow: const []);
      case TratraButtonVariant.outline:
        return (
          bg: TtColors.surface,
          fg: TtColors.ink,
          border: const BorderSide(color: TtColors.line),
          shadow: const [],
        );
      case TratraButtonVariant.ghost:
        return (bg: Colors.transparent, fg: TtColors.inkSoft, border: null, shadow: const []);
      case TratraButtonVariant.danger:
        return (bg: TtColors.danger, fg: Colors.white, border: null, shadow: TtShadows.hair);
    }
  }

  double get _height => switch (widget.size) {
        TratraButtonSize.sm => 40,
        TratraButtonSize.md => 44,
        TratraButtonSize.lg => 52,
      };

  double get _hPad => switch (widget.size) {
        TratraButtonSize.sm => 16,
        TratraButtonSize.md => 20,
        TratraButtonSize.lg => 24,
      };

  double get _fontSize => switch (widget.size) {
        TratraButtonSize.sm => 13,
        TratraButtonSize.md => 14,
        TratraButtonSize.lg => 15,
      };

  @override
  Widget build(BuildContext context) {
    final look = _look;
    final enabled = _enabled;
    final disableMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final textStyle = TratraTheme.style(TtType.button, color: look.fg).copyWith(fontSize: _fontSize);

    final content = Row(
      mainAxisSize: widget.block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: look.fg),
          )
        else if (widget.leading != null)
          IconTheme.merge(data: IconThemeData(color: look.fg, size: 18), child: widget.leading!),
        if (widget.loading || widget.leading != null) const SizedBox(width: 8),
        Flexible(
          child: Text(widget.label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (!widget.loading && widget.trailing != null) ...[
          const SizedBox(width: 8),
          IconTheme.merge(data: IconThemeData(color: look.fg, size: 18), child: widget.trailing!),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed && enabled && !disableMotion ? 0.98 : 1,
        duration: TtMotion.fast,
        curve: TtMotion.emphasized,
        child: AnimatedOpacity(
          opacity: widget.onPressed == null ? 0.6 : 1,
          duration: TtMotion.fast,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: TtRadius.pillAll,
              boxShadow: enabled && widget.size != TratraButtonSize.sm ? look.shadow : const [],
            ),
            child: Material(
              color: look.bg,
              shape: StadiumBorder(side: look.border ?? BorderSide.none),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                onHighlightChanged: (v) => setState(() => _pressed = v),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: _height, minWidth: _height),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _hPad),
                    // heightFactor: 1 évite que le bouton s'étire sur toute la hauteur dans une barre basse.
                    child: Center(widthFactor: widget.block ? null : 1, heightFactor: 1, child: content),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
