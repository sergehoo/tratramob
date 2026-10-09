import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'tratra_button.dart';

/// Feuille basse de la marque (équivalent mobile de `Modal`) : poignée, titre,
/// description, contenu défilant, marge clavier.
Future<T?> showTratraSheet<T>(
  BuildContext context, {
  required String title,
  String? description,
  required Widget child,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TratraTheme.style(TtType.h2)),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(description, style: TratraTheme.style(TtType.body, color: TtColors.ash).copyWith(fontSize: 14)),
            ],
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    ),
  );
}

/// Confirmation d'une action (éventuellement destructive). Renvoie `true` si confirmée.
Future<bool> showTratraConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirmer',
  String cancelLabel = 'Annuler',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TratraTheme.style(TtType.h2)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message, style: TratraTheme.style(TtType.body, color: TtColors.inkSoft).copyWith(fontSize: 14)),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TratraButton(
                    label: cancelLabel,
                    variant: TratraButtonVariant.outline,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TratraButton(
                    label: confirmLabel,
                    variant: danger ? TratraButtonVariant.danger : TratraButtonVariant.primary,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
