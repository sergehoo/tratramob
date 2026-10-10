// lib/screens/trust/verify_result.dart
//
// Résultat d'une vérification Tratra ID : décision lisible d'un coup d'œil, puis identité vérifiée.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/trust/identity_api.dart';

class VerifyResultView extends StatelessWidget {
  const VerifyResultView({super.key, required this.outcome});
  final IdentityOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (outcome.tone) {
      'ok' => (TtColors.successSoft, TtColors.success, Icons.verified_rounded),
      'danger' => (TtColors.dangerSoft, TtColors.danger, Icons.gpp_bad_rounded),
      _ => (TtColors.warningSoft, TtColors.warning, Icons.error_outline_rounded),
    };
    final holder = outcome.holder;
    final trades = ((holder?['trades'] as List?) ?? const []).map((e) => '$e').toList();
    final kycDate = DateTime.tryParse('${holder?['kyc_verified_on'] ?? ''}')?.toLocal();
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(TtSpace.s4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(TtRadius.panel), border: Border.all(color: fg.withValues(alpha: 0.3))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: fg, size: 28),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(outcome.title, style: TratraTheme.style(TtType.h3)),
                  const SizedBox(height: 4),
                  Text(outcome.message, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                ]),
              ),
            ]),
          ),
        ),
        if (holder != null) ...[
          const SizedBox(height: TtSpace.s4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TratraAvatar(name: '${holder['display_name']}', photoUrl: holder['photo'] as String?, size: 64),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${holder['display_name']}', style: TratraTheme.style(TtType.h3)),
                if (trades.isNotEmpty) Text(trades.join(', '), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                if ('${holder['commune'] ?? ''}'.isNotEmpty) Text('${holder['commune']}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                const SizedBox(height: 6),
                TratraTrustBadges(trustBadgeCodes(holder['badges'])),
              ]),
            ),
          ]),
        ],
        if (outcome.tratraId != null) ...[
          const SizedBox(height: TtSpace.s3),
          Text(
            'Tratra ID : ${outcome.tratraId}${kycDate == null ? '' : ' · identité vérifiée le ${kycDate.day.toString().padLeft(2, '0')}/${kycDate.month.toString().padLeft(2, '0')}/${kycDate.year}'}',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash),
          ),
        ],
        if (outcome.extra != null) ...[
          const SizedBox(height: 4),
          Text(outcome.extra!, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        ],
      ]),
    );
  }
}
