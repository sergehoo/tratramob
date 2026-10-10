// lib/screens/trust/trust_widgets.dart
//
// Briques partagées du passeport professionnel Tratra Trust (public) et de « Ma réputation » (artisan).
// Présentation uniquement : toutes les valeurs viennent de l'API (/handymen/{id}/trust/, /me/trust/).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';

String _s(dynamic v) => '${v ?? ''}';

List<Map<String, dynamic>> maps(dynamic v) =>
    ((v as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

/// 0.923 → « 92 % » ; null → « — ».
String fmtPercent(dynamic ratio) => ratio is num ? '${(ratio * 100).round()} %' : '—';

/// Minutes → « < 1 min », « 12 min », « 1 h 05 » ; null → « — ».
String fmtMinutes(dynamic minutes) {
  if (minutes is! num) return '—';
  if (minutes < 1) return '< 1 min';
  if (minutes < 60) return '${minutes.round()} min';
  final h = minutes ~/ 60;
  final m = (minutes % 60).round();
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String fmtDate(dynamic iso) {
  final d = DateTime.tryParse(_s(iso))?.toLocal();
  if (d == null) return '';
  const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String fmtDecimal(dynamic v) => _s(v).replaceAll('.', ',');

const _sourceLabels = {'vérifié': 'Vérifié par Tratra', 'plateforme': 'Mesuré sur Tratra', 'déclaré': 'Déclaré par l’artisan'};

/// Provenance d'une information : vérifiée par Tratra, mesurée sur la plateforme ou simplement déclarée.
class SourceTag extends StatelessWidget {
  const SourceTag(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final tone = switch (source) {
      'vérifié' => TratraTone.primary,
      'plateforme' => TratraTone.info,
      _ => TratraTone.gray,
    };
    final icon = switch (source) {
      'vérifié' => Icons.verified_rounded,
      'plateforme' => Icons.show_chart_rounded,
      _ => Icons.person_outline_rounded,
    };
    return TratraBadge(_sourceLabels[source] ?? source, tone: tone, icon: icon);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final int value;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = TtColors.lineSoft;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = TtColors.primary;
    canvas.drawCircle(c, r, base);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * value / 100, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// Anneau du score : valeur réelle uniquement.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.value, this.size = 112});
  final int value;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Score de confiance $value sur 100',
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(value),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$value', style: TratraTheme.style(TtType.h1)),
                Text('sur 100', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              ]),
            ),
          ),
        ),
      );
}

/// Explication du score : chaque composante, son poids réel et sa provenance. Aucune donnée manquante n'est comptée comme un zéro.
class ScoreBreakdownCard extends StatelessWidget {
  const ScoreBreakdownCard({super.key, required this.score});
  final Map<String, dynamic> score;

  @override
  Widget build(BuildContext context) {
    final value = score['value'];
    final comps = maps(score['components']);
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Score de confiance', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: 2),
        Text('Calculé par Tratra à partir de données réelles — jamais saisi, jamais acheté.',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s4),
        if (value is num)
          Row(children: [
            ScoreRing(value: value.round()),
            const SizedBox(width: TtSpace.s4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Fiabilité de la mesure : ${_s(score['confidence'])}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                const SizedBox(height: 4),
                Text(_s(score['note']), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              ]),
            ),
          ])
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(TtSpace.s3),
            decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
            child: Text(
              _s(score['reason']).isEmpty ? 'Le score sera publié dès que l’activité mesurée sera suffisante.' : _s(score['reason']),
              style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
            ),
          ),
        const SizedBox(height: TtSpace.s4),
        for (final c in comps) ...[
          Row(children: [
            Expanded(child: Text(_s(c['label']), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600))),
            SourceTag(_s(c['source'])),
          ]),
          const SizedBox(height: 6),
          if (c['available'] == true) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(TtRadius.pill),
              child: LinearProgressIndicator(
                value: ((c['ratio'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: TtColors.lineSoft,
                color: TtColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
                c['points'] is num ? '${_s(c['detail'])} · ${fmtDecimal(c['points'])} / ${fmtDecimal(c['max_points'])} pts' : _s(c['detail']),
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ] else
            Text('${_s(c['detail']).isEmpty ? 'Pas encore mesurable.' : _s(c['detail'])} — non comptée, sans pénalité.',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          const SizedBox(height: TtSpace.s3),
        ],
      ]),
    );
  }
}

/// Historique des badges : attribution et retrait automatiques, conservés (motif visible pour le propriétaire).
class BadgeHistoryCard extends StatelessWidget {
  const BadgeHistoryCard({super.key, required this.history});
  final List<Map<String, dynamic>> history;

  @override
  Widget build(BuildContext context) => TratraCard(
        padding: TratraCard.compact,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Historique des badges', style: TratraTheme.style(TtType.h3)),
          const SizedBox(height: 2),
          Text('Chaque badge est attribué et retiré automatiquement ; l’historique est conservé.',
              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          const SizedBox(height: TtSpace.s3),
          if (history.isEmpty)
            Text('Aucun badge attribué pour le moment.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
          else
            for (final h in history) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 8, color: h['ended_at'] == null ? TtColors.primary : TtColors.fog),
                ),
                const SizedBox(width: TtSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${trustBadgeInfo[_s(h['code'])]?.label ?? _s(h['label'])} · ${h['ended_at'] == null ? 'actif' : 'retiré'}',
                        style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      'depuis le ${fmtDate(h['started_at'])}${h['ended_at'] != null ? ' · jusqu’au ${fmtDate(h['ended_at'])}' : ''}',
                      style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                    ),
                    if (_s(h['ended_at'] == null ? h['start_reason'] : h['end_reason']).isNotEmpty)
                      Text(_s(h['ended_at'] == null ? h['start_reason'] : h['end_reason']),
                          style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
                  ]),
                ),
              ]),
              const SizedBox(height: TtSpace.s3),
            ],
        ]),
      );
}

/// Chiffre clé (missions, satisfaction, ponctualité, réactivité) avec sa provenance.
class FactTile extends StatelessWidget {
  const FactTile({super.key, required this.icon, required this.label, required this.value, required this.hint, required this.source});
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final String source;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(TtSpace.s3),
        decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.panel)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: TtColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text(value, style: TratraTheme.style(TtType.h2)),
          Text(hint, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          const SizedBox(height: 6),
          SourceTag(source),
        ]),
      );
}
