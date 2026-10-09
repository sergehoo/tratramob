// lib/widgets/error_retry_widget.dart
// Adaptateur : préférer TratraEmptyState / TratraAlert (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Erreur plein écran avec action « Réessayer » (appelle `onRetry`).
class ErrorRetryWidget extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const ErrorRetryWidget({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return TratraEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Une erreur est survenue',
      description: error,
      actions: [
        TratraButton(
          label: 'Réessayer',
          leading: const Icon(Icons.refresh_rounded),
          onPressed: onRetry,
        ),
      ],
    );
  }
}
