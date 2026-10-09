// lib/widgets/error_widget.dart
// Adaptateur : préférer TratraEmptyState / TratraAlert (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Erreur plein écran. `onRetry` (si fourni) ajoute le bouton d'action, libellé `retryText`
/// (« Réessayer » par défaut).
class CustomErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final String? retryText;

  const CustomErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.retryText,
  });

  @override
  Widget build(BuildContext context) {
    return TratraEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Oups !',
      description: error,
      actions: [
        if (onRetry != null)
          TratraButton(
            label: retryText ?? 'Réessayer',
            leading: const Icon(Icons.refresh_rounded),
            onPressed: onRetry,
          ),
      ],
    );
  }
}
