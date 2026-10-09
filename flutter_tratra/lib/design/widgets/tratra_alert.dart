import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum TratraAlertTone { info, success, warning, danger, brand }

/// Message contextuel (miroir de `Alert` côté web). Annoncé aux lecteurs d'écran
/// (liveRegion) ; `action` est un bouton/lien affiché sous le texte.
class TratraAlert extends StatelessWidget {
  const TratraAlert({
    super.key,
    required this.message,
    this.title,
    this.tone = TratraAlertTone.info,
    this.action,
    this.icon,
    this.onDismiss,
  });

  final String message;
  final String? title;
  final TratraAlertTone tone;
  final Widget? action;
  final IconData? icon;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, accent, defaultIcon) = switch (tone) {
      TratraAlertTone.info => (TtColors.infoSoft, TtColors.info, TtColors.infoInk, TtColors.info, Icons.info_outline),
      TratraAlertTone.success => (
          TtColors.successSoft, TtColors.success, TtColors.successInk, TtColors.success, Icons.check_circle_outline),
      TratraAlertTone.warning => (
          TtColors.warningSoft, TtColors.warning, TtColors.warningInk, TtColors.warning, Icons.warning_amber_rounded),
      TratraAlertTone.danger => (
          TtColors.dangerSoft, TtColors.danger, TtColors.dangerInk, TtColors.danger, Icons.error_outline),
      TratraAlertTone.brand => (
          TtColors.primarySoft, TtColors.primary, TtColors.primaryDark, TtColors.primary, Icons.info_outline),
    };
    final base = TratraTheme.style(TtType.bodySm, color: fg);

    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: TtRadius.panelAll,
          border: Border.all(color: border.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon ?? defaultIcon, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title!, style: base.copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(message, style: base.copyWith(fontSize: 13.5, height: 1.5)),
                    if (action != null) ...[const SizedBox(height: 10), action!],
                  ],
                ),
              ),
              if (onDismiss != null)
                InkResponse(
                  onTap: onDismiss,
                  radius: 20,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 18, color: fg.withValues(alpha: 0.7), semanticLabel: 'Fermer le message'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
