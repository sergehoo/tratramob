// lib/widgets/animated_button.dart
// Adaptateur : préférer TratraButton (lib/design) pour tout nouveau code.
//
// AnimatedButton reçoit un `child` Widget arbitraire (texte stylé, spinner…) alors que
// TratraButton n'accepte qu'un libellé : il ne peut donc pas lui déléguer sans changer
// l'API. Il reprend donc le rendu de TratraButton (pilule, halo de marque, appui à 0,98,
// cible >= 48) à partir des mêmes jetons, en gardant son contrat : appel asynchrone
// protégé contre le double appui, chargement interne, `enabled`, couleur de fond optionnelle.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/design/design.dart';

class AnimatedButton extends StatefulWidget {
  final FutureOr<void> Function() onPressed;
  final Widget child;
  final bool isLoading;
  final bool enabled;

  /// Couleur de fond. Par défaut : vert de marque foncé (texte blanc, contraste AA).
  /// Le texte/icône s'adapte automatiquement (blanc sur fond sombre, encre sur fond clair).
  final Color? backgroundColor;

  /// Marges internes. Par défaut : celles du Design System (24 horizontal, 12 vertical).
  final EdgeInsetsGeometry? padding;

  /// Rayon des coins. Par défaut (null) : pilule, comme TratraButton.
  final double? radius;

  /// Conservé pour compatibilité d'API : l'ombre vient des jetons du DS (TtShadows).
  final double elevation;
  final String? semanticsLabel;

  /// Retour haptique léger à l'appui.
  final bool hapticFeedback;

  const AnimatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.enabled = true,
    this.backgroundColor,
    this.padding,
    this.radius,
    this.elevation = 0,
    this.semanticsLabel,
    this.hapticFeedback = false,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> {
  bool _internalLoading = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _effectiveLoading => widget.isLoading || _internalLoading;
  bool get _interactive => widget.enabled && !_effectiveLoading;

  Future<void> _handlePress() async {
    if (!_interactive) return;
    setState(() => _internalLoading = true);
    try {
      if (widget.hapticFeedback) {
        unawaited(HapticFeedback.selectionClick());
      }
      final result = widget.onPressed();
      if (result is Future) await result;
    } finally {
      if (mounted) setState(() => _internalLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = _interactive;
    final bg = widget.backgroundColor ?? TtColors.primaryDark;
    final onDark = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark;
    final fg = onDark ? Colors.white : TtColors.ink;
    final disableMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final customRadius = widget.radius;
    final borderRadius = customRadius == null ? TtRadius.pillAll : BorderRadius.circular(customRadius);
    final focusSide = _focused
        ? BorderSide(color: onDark ? TtColors.accent : TtColors.ink, width: 2)
        : BorderSide.none;
    final ShapeBorder shape = customRadius == null
        ? StadiumBorder(side: focusSide)
        : RoundedRectangleBorder(borderRadius: borderRadius, side: focusSide);
    final shadow = !interactive
        ? const <BoxShadow>[]
        : (widget.backgroundColor == null ? TtShadows.glow : TtShadows.soft);
    final padding = widget.padding ?? const EdgeInsets.symmetric(horizontal: TtSpace.s6, vertical: TtSpace.s3);

    final content = _effectiveLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : IconTheme.merge(
            data: IconThemeData(color: fg, size: 18),
            child: DefaultTextStyle.merge(
              style: TratraTheme.style(TtType.button, color: fg),
              textAlign: TextAlign.center,
              child: widget.child,
            ),
          );

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      enabled: widget.enabled,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _handlePress();
            return null;
          }),
        },
        child: IgnorePointer(
          ignoring: !interactive,
          child: AnimatedScale(
            scale: _pressed && interactive && !disableMotion ? 0.98 : 1,
            duration: TtMotion.fast,
            curve: TtMotion.emphasized,
            child: AnimatedOpacity(
              opacity: widget.enabled ? 1 : 0.6,
              duration: TtMotion.fast,
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow),
                child: Material(
                  color: bg,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _handlePress,
                    canRequestFocus: false,
                    onHighlightChanged: (down) => setState(() => _pressed = down),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: TtLayout.controlHeight),
                      child: Padding(
                        padding: padding,
                        child: Center(child: content),
                      ),
                    ),
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
