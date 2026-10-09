// lib/widgets/empty_state_widget.dart
// Adaptateur : préférer TratraEmptyState (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// État vide générique. `onRetry` (si fourni) ajoute un bouton d'action réel,
/// libellé `retryText` (« Réessayer » par défaut), icône `actionIcon`.
class EmptyStateWidget extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onRetry;
  final String? retryText;

  /// Icône du bouton d'action (rafraîchir par défaut).
  final IconData? actionIcon;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.subtitle,
    this.icon,
    this.onRetry,
    this.retryText,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TratraEmptyState(
      icon: icon ?? Icons.search_off_rounded,
      title: message,
      description: subtitle,
      actions: [
        if (onRetry != null)
          TratraButton(
            label: retryText ?? 'Réessayer',
            leading: Icon(actionIcon ?? Icons.refresh_rounded),
            onPressed: onRetry,
          ),
      ],
    );
  }
}

/// Aucun service à afficher ; `onExplore` (si fourni) mène vers la découverte des catégories.
class EmptyServicesWidget extends StatelessWidget {
  final VoidCallback? onExplore;
  final String? message;

  const EmptyServicesWidget({
    super.key,
    this.onExplore,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateWidget(
      icon: Icons.handyman_outlined,
      message: message ?? 'Aucun service trouvé',
      subtitle:
          'Essayez de modifier vos critères de recherche ou explorez nos catégories',
      onRetry: onExplore,
      retryText: 'Explorer les catégories',
      actionIcon: Icons.explore_outlined,
    );
  }
}
