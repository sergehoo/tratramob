import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'tratra_badge.dart';

/// Badges Tratra Trust (jamais saisis : attribués par le serveur à partir de données réelles).
/// Mêmes codes et libellés que le web (`frontend/src/lib/trust.ts`) et que l'API (`trust/engine.py`).
class TrustBadgeInfo {
  const TrustBadgeInfo(this.label, this.help, this.tone, this.icon);
  final String label;
  final String help;
  final TratraTone tone;
  final IconData icon;
}

const Map<String, TrustBadgeInfo> trustBadgeInfo = {
  'NOUVEAU': TrustBadgeInfo('Nouveau', 'Profil créé, identité pas encore vérifiée.', TratraTone.gray, Icons.auto_awesome_rounded),
  'VERIFIE': TrustBadgeInfo('Vérifié', 'Pièce d’identité contrôlée par l’équipe Tratra et profil complet.', TratraTone.primary, Icons.verified_rounded),
  'EXPERT': TrustBadgeInfo('Expert', 'Expertise démontrée : justificatifs approuvés et résultats atteints.', TratraTone.accent, Icons.workspace_premium_rounded),
  'SUR': TrustBadgeInfo('Sûr', 'Fiabilité mesurée : ponctualité, absence de litiges et avis des clients.', TratraTone.night, Icons.shield_rounded),
};

/// Ordre d'affichage (cumulables).
const List<String> trustBadgeOrder = ['VERIFIE', 'EXPERT', 'SUR', 'NOUVEAU'];

/// Codes de badges connus, dans l'ordre d'affichage, depuis `[{code, label}, ...]` (ou une liste de codes).
List<String> trustBadgeCodes(dynamic raw) {
  if (raw is! List) return const [];
  final codes = raw.map((e) => e is Map ? '${e['code']}' : '$e').where(trustBadgeInfo.containsKey).toSet();
  return [for (final c in trustBadgeOrder) if (codes.contains(c)) c];
}

/// Un badge Tratra Trust.
class TratraTrustBadge extends StatelessWidget {
  const TratraTrustBadge(this.code, {super.key, this.onNight = false});
  final String code;

  /// Sur fond sombre (carte « night ») : teintes lisibles (le badge Sûr, noir, y serait invisible).
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    final info = trustBadgeInfo[code];
    if (info == null) return const SizedBox.shrink();
    final tone = !onNight
        ? info.tone
        : switch (code) {
            'VERIFIE' => TratraTone.success,
            'SUR' => TratraTone.primary,
            _ => info.tone,
          };
    return Tooltip(message: info.help, child: TratraBadge(info.label, tone: tone, icon: info.icon));
  }
}

/// Badges actuels d'un artisan (rien s'il n'y en a aucun).
class TratraTrustBadges extends StatelessWidget {
  const TratraTrustBadges(this.codes, {super.key, this.spacing = 6, this.onNight = false});
  final List<String> codes;
  final double spacing;
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [for (final c in codes) TratraTrustBadge(c, onNight: onNight)],
    );
  }
}

/// Score de confiance sur 100 — rien tant qu'il n'est pas calculable (jamais de chiffre inventé).
class TratraTrustScorePill extends StatelessWidget {
  const TratraTrustScorePill(this.score, {super.key});
  final int? score;

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const ShapeDecoration(color: TtColors.lineSoft, shape: StadiumBorder()),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.circle, size: 7, color: TtColors.primary),
        const SizedBox(width: 6),
        Text('Confiance $score/100', style: TratraTheme.style(TtType.caption).copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
