// Libellés français + ton visuel des statuts métier (miroir de frontend/src/lib/status.ts).
// Affichage uniquement : aucune règle métier ici.
import 'package:flutter/material.dart';

import 'widgets/tratra_badge.dart';

class TratraStatusView {
  const TratraStatusView(this.label, this.tone, {this.pulse = false});
  final String label;
  final TratraTone tone;
  final bool pulse;
}

abstract final class TratraStatus {
  static const booking = <String, TratraStatusView>{
    'pending': TratraStatusView('En attente', TratraTone.accent),
    'confirmed': TratraStatusView('Confirmée', TratraTone.primary),
    'in_progress': TratraStatusView('En cours', TratraTone.night, pulse: true),
    'completed': TratraStatusView('Terminée', TratraTone.success),
    'cancelled': TratraStatusView('Annulée', TratraTone.gray),
  };

  static const document = <String, TratraStatusView>{
    'pending': TratraStatusView('En vérification', TratraTone.accent),
    'approved': TratraStatusView('Validé', TratraTone.success),
    'rejected': TratraStatusView('Refusé', TratraTone.danger),
  };

  static const dispute = <String, TratraStatusView>{
    'open': TratraStatusView('Ouvert', TratraTone.danger),
    'under_review': TratraStatusView('En cours d’examen', TratraTone.warning),
    'resolved': TratraStatusView('Résolu', TratraTone.success),
    'rejected': TratraStatusView('Rejeté', TratraTone.gray),
  };

  /// Statut inconnu : valeur brute en gris plutôt que de la cacher.
  static TratraStatusView of(Map<String, TratraStatusView> kind, String? status) =>
      kind[status ?? ''] ?? TratraStatusView((status == null || status.isEmpty) ? '—' : status, TratraTone.gray);
}

/// Badge de statut prêt à l'emploi : `TratraStatusBadge(TratraStatus.booking, b.status)`.
class TratraStatusBadge extends StatelessWidget {
  const TratraStatusBadge(this.kind, this.status, {super.key});
  final Map<String, TratraStatusView> kind;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final v = TratraStatus.of(kind, status);
    return TratraBadge(v.label, tone: v.tone, dot: true, pulse: v.pulse);
  }
}
