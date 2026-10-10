// lib/engagements/contract_extras.dart
//
// Avenants (proposés, acceptés par l'AUTRE partie, datés, jamais rétroactifs), évaluations (anti-abus : seules les deux
// parties d'un contrat réellement commencé, cadence et délais imposés par le serveur) et historique en ajout seulement.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';

const _changeLabel = {
  'amount': 'Montant', 'end_date': 'Fin', 'notice_period_days': 'Préavis (jours)', 'conditions': 'Conditions', 'payment_day': 'Jour de paiement', 'overtime_hourly_rate': 'Taux heures supplémentaires',
  'schedule': 'Planning', 'description': 'Missions', 'starts_on': 'Début de suspension', 'ends_on': 'Fin de suspension', 'auto_renew': 'Renouvellement automatique',
  'renewal_term_months': 'Durée de renouvellement', 'location_address': 'Adresse', 'location_city': 'Ville', 'proration_mode': 'Prorata', 'hours_per_week': 'Heures par semaine',
};

/// « Montant : 165 000 FCFA · Fin : 4 janvier 2028 ».
String describeChanges(Json a) {
  final changes = a.m('changes');
  final parts = changes.entries.map((e) {
    final label = _changeLabel[e.key] ?? e.key;
    final v = e.value;
    if (e.key == 'amount' || e.key == 'overtime_hourly_rate') return '$label : ${fcfa('$v')}';
    if (e.key == 'schedule') return '$label modifié';
    if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return '$label : ${dateFr(v)}';
    if (v is bool) return '$label : ${v ? 'oui' : 'non'}';
    final t = '$v';
    return '$label : ${t.length > 80 ? t.substring(0, 80) : t}';
  }).toList();
  return parts.isEmpty ? (amendmentKindFr[a.s('kind')] ?? a.s('kind')) : parts.join(' · ');
}

class AmendmentCard extends StatelessWidget {
  const AmendmentCard({super.key, required this.api, required this.a, required this.onChanged});
  final EngagementsApi api;
  final Json a;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => TratraAlert(
        tone: TratraAlertTone.info,
        title: 'Avenant ${a.s('status') == 'accepted' ? 'accepté, en attente de sa date d’effet' : 'à valider'} : ${amendmentKindFr[a.s('kind')] ?? a.s('kind')}',
        message: '${describeChanges(a)} · effet le ${dateFr(a.sn('effective_date'))}\nMotif : ${a.s('reason')}',
        action: (a.b('can_respond') || a.b('can_withdraw'))
            ? Wrap(spacing: 8, runSpacing: 6, children: [
                if (a.b('can_respond')) ...[
                  AsyncAction(label: 'Accepter l’avenant', run: () async {
                    await api.post('/amendments/${a.i('id')}/respond/', {'accept': true});
                    await onChanged();
                  }),
                  AsyncAction(label: 'Refuser', variant: TratraButtonVariant.outline, run: () async {
                    await api.post('/amendments/${a.i('id')}/respond/', {'accept': false});
                    await onChanged();
                  }),
                ],
                if (a.b('can_withdraw'))
                  AsyncAction(label: 'Retirer ma proposition', variant: TratraButtonVariant.outline, run: () async {
                    await api.post('/amendments/${a.i('id')}/withdraw/');
                    await onChanged();
                  }),
              ])
            : null,
      );
}

// ── Avenants ────────────────────────────────────────────────────────────────────────────────────────────────────────

class ContractAmendments extends StatefulWidget {
  const ContractAmendments({super.key, required this.api, required this.c, required this.onChanged, required this.openNew, required this.onOpened});
  final EngagementsApi api;
  final Json c;
  final Future<void> Function() onChanged;
  final bool openNew;
  final VoidCallback onOpened;
  @override
  State<ContractAmendments> createState() => _ContractAmendmentsState();
}

class _ContractAmendmentsState extends State<ContractAmendments> {
  int _version = 0;

  @override
  void initState() {
    super.initState();
    if (widget.openNew) WidgetsBinding.instance.addPostFrameCallback((_) => _propose());
  }

  void _refresh() {
    setState(() => _version++);
    widget.onChanged();
  }

  Future<void> _propose() async {
    widget.onOpened();
    final c = widget.c;
    final kinds = <(String, String)>[
      ('change', amendmentKindFr['change']!),
      ('suspend', amendmentKindFr['suspend']!),
      ('end', amendmentKindFr['end']!),
      if (c.s('status') == 'notice') ('cancel_notice', amendmentKindFr['cancel_notice']!),
      if (c.sn('end_date') != null) ('renewal', amendmentKindFr['renewal']!),
    ];
    final kind = await showTratraSheet<String>(
      context,
      title: 'Proposer un avenant',
      description: '${c.m('counterpart').s('name')} doit l’accepter. Un avenant n’est jamais rétroactif : les périodes déjà commencées ne changent pas, et l’historique garde toutes les versions.',
      child: Column(children: [for (final k in kinds) ListTile(contentPadding: EdgeInsets.zero, title: Text(k.$2), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).pop(k.$1))]),
    );
    if (kind == null || !mounted) return;
    final base = randomHex();
    final today = DateTime.now();
    final other = c.m('counterpart').s('name');
    final id = c.i('id');
    Future<void> send(String kind, Map<String, dynamic> changes, Map<String, String> v) {
      if (kind != 'cancel_notice' && changes.isEmpty) throw const FormError('Renseignez au moins une modification.');
      final body = {'kind': kind, 'changes': changes, 'reason': v['reason'], if ((v['effective_date'] ?? '').isNotEmpty) 'effective_date': v['effective_date'], 'expected_version': c.i('version')};
      return widget.api.post('/contracts/$id/amendments/', body, intentKey('amend', base, body));
    }

    const reason = FieldSpec('reason', 'Motif', kind: FieldKind.multiline, required: true);
    final effective = FieldSpec('effective_date', 'Date d’effet', kind: FieldKind.date, optional: true, hint: 'Par défaut : aujourd’hui, dès acceptation.', firstDate: today);
    late final bool done;
    switch (kind) {
      case 'change':
        done = await showActionSheet(
          context,
          title: 'Modifier les conditions',
          description: 'Renseignez uniquement ce qui change. $other doit accepter.',
          confirmLabel: 'Envoyer l’avenant',
          fields: [
            FieldSpec('amount', 'Montant (actuel : ${fcfa(c.s('amount'), c.s('currency', 'XOF'))})', kind: FieldKind.number, optional: true),
            FieldSpec('notice_period_days', 'Préavis en jours (actuel : ${c.s('notice_period_days')})', kind: FieldKind.number, optional: true),
            const FieldSpec('payment_day', 'Jour de paiement', kind: FieldKind.number, optional: true),
            const FieldSpec('overtime_hourly_rate', 'Taux horaire des heures supplémentaires', kind: FieldKind.number, optional: true),
            if (c.sn('end_date') != null) FieldSpec('end_date', 'Nouvelle date de fin', kind: FieldKind.date, optional: true, firstDate: today),
            const FieldSpec('conditions', 'Conditions particulières (remplacent les actuelles)', kind: FieldKind.multiline, optional: true),
            effective,
            reason,
          ],
          submit: (v) => send('change', {
            if ((v['amount'] ?? '').isNotEmpty) 'amount': v['amount'],
            if ((v['notice_period_days'] ?? '').isNotEmpty) 'notice_period_days': int.tryParse(v['notice_period_days']!) ?? v['notice_period_days'],
            if ((v['payment_day'] ?? '').isNotEmpty) 'payment_day': int.tryParse(v['payment_day']!) ?? v['payment_day'],
            if ((v['overtime_hourly_rate'] ?? '').isNotEmpty) 'overtime_hourly_rate': v['overtime_hourly_rate'],
            if ((v['end_date'] ?? '').isNotEmpty) 'end_date': v['end_date'],
            if ((v['conditions'] ?? '').isNotEmpty) 'conditions': v['conditions'],
          }, v),
        );
      case 'suspend':
        done = await showActionSheet(
          context,
          title: 'Suspendre d’un commun accord',
          description: 'Les échéances et le planning de la période sont suspendus ; le contrat reprend à la date de fin.',
          confirmLabel: 'Envoyer l’avenant',
          fields: [FieldSpec('starts_on', 'Début de la suspension', kind: FieldKind.date, required: true, firstDate: today), FieldSpec('ends_on', 'Fin (vide = jusqu’à reprise)', kind: FieldKind.date, optional: true, firstDate: today), reason],
          submit: (v) => send('suspend', {'starts_on': v['starts_on'], if ((v['ends_on'] ?? '').isNotEmpty) 'ends_on': v['ends_on']}, v),
        );
      case 'end':
        done = await showActionSheet(
          context,
          title: 'Fin d’un commun accord',
          confirmLabel: 'Envoyer l’avenant',
          danger: true,
          fields: [FieldSpec('end_date', 'Date de fin convenue', kind: FieldKind.date, required: true, firstDate: today), effective, reason],
          submit: (v) => send('end', {'end_date': v['end_date']}, v),
        );
      case 'renewal':
        done = await showActionSheet(
          context,
          title: 'Renouveler le contrat',
          confirmLabel: 'Envoyer l’avenant',
          fields: [FieldSpec('end_date', 'Nouvelle date de fin', kind: FieldKind.date, required: true, firstDate: today), effective, reason],
          submit: (v) => send('renewal', {'end_date': v['end_date']}, v),
        );
      default:
        done = await showActionSheet(
          context,
          title: 'Annuler le préavis',
          confirmLabel: 'Envoyer l’avenant',
          fields: const [reason],
          submit: (v) => send('cancel_notice', const {}, v),
        );
    }
    if (done) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final canPropose = c.strs('actions').contains('propose_amendment') && c['pending_amendment'] == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Avenants', style: TratraTheme.style(TtType.h2))),
            if (canPropose) TratraButton(label: 'Proposer', size: TratraButtonSize.sm, onPressed: _propose),
          ]),
          const SizedBox(height: 4),
          Text('Chaque évolution du contrat est proposée, acceptée par l’autre partie et datée.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: 12),
          if (c['pending_amendment'] is Map) ...[AmendmentCard(api: widget.api, a: c.m('pending_amendment'), onChanged: () async => _refresh()), const SizedBox(height: 12)],
          EngLoader<List<Json>>(
            reloadKey: '$_version-${c.i('version')}',
            load: () => widget.api.getList('/contracts/${c.i('id')}/amendments/'),
            builder: (ctx, rows, _) => rows.isEmpty
                ? const TratraEmptyState(compact: true, title: 'Aucun avenant', description: 'Le contrat est encore dans sa version d’origine.')
                : Column(children: [
                    for (final a in rows)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.control)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(amendmentKindFr[a.s('kind')] ?? a.s('kind'), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
                            TratraBadge(_amendStatus(a.s('status')).$1, tone: _amendStatus(a.s('status')).$2),
                          ]),
                          Text(describeChanges(a), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                          Text('Proposé par ${a.b('mine') ? 'vous' : a.m('proposed_by').s('name')} · effet le ${dateFr(a.sn('effective_date'))} · motif : ${a.s('reason')}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    ]);
  }

  static (String, TratraTone) _amendStatus(String s) => switch (s) {
        'proposed' => ('À valider', TratraTone.accent),
        'accepted' => ('Accepté', TratraTone.info),
        'applied' => ('En vigueur', TratraTone.success),
        'rejected' => ('Refusé', TratraTone.danger),
        'withdrawn' => ('Retiré', TratraTone.gray),
        _ => (s, TratraTone.gray),
      };
}

// ── Évaluations ─────────────────────────────────────────────────────────────────────────────────────────────────────

const _criteria = [('quality', 'Qualité du travail'), ('punctuality', 'Ponctualité'), ('communication', 'Communication'), ('respect', 'Respect')];

class ContractEvaluations extends StatefulWidget {
  const ContractEvaluations({super.key, required this.api, required this.c});
  final EngagementsApi api;
  final Json c;
  @override
  State<ContractEvaluations> createState() => _ContractEvaluationsState();
}

class _ContractEvaluationsState extends State<ContractEvaluations> {
  int _version = 0;
  void _refresh() => setState(() => _version++);

  Future<void> _create() async {
    final c = widget.c;
    final ended = const {'terminated', 'completed'}.contains(c.s('status'));
    final base = randomHex();
    final done = await showActionSheet(
      context,
      title: 'Évaluer ${c.m('counterpart').s('name')}',
      description: 'Votre avis est publié sur le profil de la personne évaluée. Il doit refléter votre expérience réelle de ce contrat.',
      confirmLabel: 'Publier mon évaluation',
      fields: [
        FieldSpec('kind', 'Type d’évaluation', kind: FieldKind.select, options: [if (!ended) ('periodic', 'Évaluation périodique (pendant le contrat)'), if (ended) ('final', 'Évaluation finale (après la fin)')], initial: ended ? 'final' : 'periodic'),
        const FieldSpec('rating', 'Note globale', kind: FieldKind.select, options: [('5', '5 / 5 — Excellent'), ('4', '4 / 5 — Très bien'), ('3', '3 / 5 — Correct'), ('2', '2 / 5 — Décevant'), ('1', '1 / 5 — Très insuffisant')], initial: '5'),
        for (final (k, l) in _criteria) FieldSpec('c_$k', l, kind: FieldKind.select, options: const [('', 'Non évalué'), ('5', '5 / 5'), ('4', '4 / 5'), ('3', '3 / 5'), ('2', '2 / 5'), ('1', '1 / 5')]),
        const FieldSpec('comment', 'Commentaire', kind: FieldKind.multiline, optional: true, maxLength: 2000, hint: 'Sans lien, adresse e-mail ni numéro de téléphone.'),
      ],
      submit: (v) {
        final body = {
          'kind': v['kind'],
          'rating': int.tryParse(v['rating'] ?? '') ?? 0,
          'criteria': {for (final (k, _) in _criteria) if ((v['c_$k'] ?? '').isNotEmpty) k: int.parse(v['c_$k']!)},
          'comment': v['comment'],
        };
        return widget.api.post('/contracts/${c.i('id')}/evaluations/', body, intentKey('eval', base, body));
      },
    );
    if (done) _refresh();
  }

  Future<void> _reply(Json e) async {
    final done = await showActionSheet(
      context,
      title: 'Répondre à cette évaluation',
      description: 'Une seule réponse, publique, sans lien ni coordonnées.',
      confirmLabel: 'Publier ma réponse',
      fields: const [FieldSpec('reply', 'Votre réponse', kind: FieldKind.multiline, required: true, maxLength: 1000)],
      submit: (v) => widget.api.post('/evaluations/${e.i('id')}/reply/', {'reply': v['reply']}),
    );
    if (done) _refresh();
  }

  Future<void> _edit(Json e) async {
    final done = await showActionSheet(
      context,
      title: 'Modifier mon évaluation',
      description: 'Possible pendant quelques jours seulement après la publication.',
      confirmLabel: 'Enregistrer',
      fields: [
        FieldSpec('rating', 'Note globale', kind: FieldKind.select, options: const [('5', '5 / 5'), ('4', '4 / 5'), ('3', '3 / 5'), ('2', '2 / 5'), ('1', '1 / 5')], initial: e.s('rating')),
        FieldSpec('comment', 'Commentaire', kind: FieldKind.multiline, optional: true, initial: e.s('comment')),
      ],
      submit: (v) => widget.api.patch('/evaluations/${e.i('id')}/', {'rating': int.tryParse(v['rating'] ?? '') ?? 0, 'comment': v['comment']}),
    );
    if (done) _refresh();
  }

  Future<void> _report(Json e) async {
    final done = await showActionSheet(
      context,
      title: 'Signaler cette évaluation',
      description: 'L’équipe Tratra l’examine ; elle peut la masquer si elle est fausse ou abusive.',
      confirmLabel: 'Signaler',
      danger: true,
      fields: const [FieldSpec('reason', 'Motif', kind: FieldKind.multiline, required: true)],
      submit: (v) => widget.api.post('/evaluations/${e.i('id')}/report/', {'reason': v['reason']}),
    );
    if (done && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signalement transmis à Tratra.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final rules = c.m('rules');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TratraAlert(
        tone: TratraAlertTone.brand,
        title: 'Des évaluations fiables',
        message: 'Seules les deux parties d’un contrat réellement commencé peuvent s’évaluer : une évaluation périodique après ${rules.s('min_days_for_evaluation', '30')} jours puis tous les ${rules.s('evaluation_interval_days', '90')} jours au plus, une évaluation finale dans les 60 jours après la fin.',
      ),
      const SizedBox(height: 14),
      TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Évaluations', style: TratraTheme.style(TtType.h2))),
            if (c.strs('actions').contains('evaluate')) TratraButton(label: 'Évaluer', size: TratraButtonSize.sm, onPressed: _create),
          ]),
          const SizedBox(height: 10),
          EngLoader<List<Json>>(
            reloadKey: _version,
            load: () => widget.api.getList('/contracts/${c.i('id')}/evaluations/'),
            builder: (ctx, rows, _) => rows.isEmpty
                ? const TratraEmptyState(compact: true, title: 'Aucune évaluation pour le moment', description: 'Elles apparaissent ici pour les deux parties.')
                : Column(children: [
                    for (final e in rows)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.control)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Semantics(label: '${e.s('rating')} sur 5', child: Text('★' * e.i('rating') + '☆' * (5 - e.i('rating')), style: const TextStyle(color: TtColors.accentDark, fontSize: 18))),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e.b('mine') ? 'Votre évaluation' : 'De ${e.m('author').s('name')}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
                            TratraBadge(e.s('kind') == 'final' ? 'Finale' : 'Périodique', tone: e.s('kind') == 'final' ? TratraTone.primary : TratraTone.gray),
                          ]),
                          Text('${e.b('mine') ? 'Pour ${e.m('subject').s('name')}' : 'Pour vous'} · ${dateFr(e.sn('created_at'))}${e.b('is_hidden') ? ' · masquée par Tratra' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                          if (e.s('comment').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(e.s('comment'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
                          if (e.s('reply').isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)),
                              child: Text('Réponse de ${e.m('subject').s('name')} : ${e.s('reply')}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                            ),
                          Wrap(spacing: 8, children: [
                            if (e.b('editable')) TextButton(onPressed: () => _edit(e), child: const Text('Modifier')),
                            if (e.b('can_reply')) TextButton(onPressed: () => _reply(e), child: const Text('Répondre')),
                            if (!e.b('mine')) TextButton(onPressed: () => _report(e), child: const Text('Signaler')),
                          ]),
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    ]);
  }
}

// ── Historique et litiges ───────────────────────────────────────────────────────────────────────────────────────────

class ContractHistory extends StatefulWidget {
  const ContractHistory({super.key, required this.api, required this.c});
  final EngagementsApi api;
  final Json c;
  @override
  State<ContractHistory> createState() => _ContractHistoryState();
}

class _ContractHistoryState extends State<ContractHistory> {
  final List<Json> _extra = [];
  int? _more;
  String? _moreError;

  Future<void> _loadMore() async {
    if (_more == null) return;
    try {
      final page = await widget.api.getPage('/contracts/${widget.c.i('id')}/history/?limit=50&offset=$_more');
      if (!mounted) return;
      setState(() {
        _extra.addAll(page.results);
        _more = page.nextOffset;
        _moreError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _moreError = messageOf(e, 'Chargement impossible.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EngLoader<List<Json>>(
        reloadKey: c.i('version'),
        load: () => widget.api.getList('/contracts/${c.i('id')}/disputes/'),
        builder: (ctx, rows, _) => rows.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TratraCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Litiges', style: TratraTheme.style(TtType.h2)),
                    const SizedBox(height: 8),
                    for (final d in rows)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.control)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${disputeKindFr[d.s('kind')] ?? d.s('kind')}${d.b('mine') ? ' · ouvert par vous' : ''}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
                            TratraBadge(switch (d.s('status')) { 'open' => 'Ouvert', 'under_review' => 'En cours d’examen', 'resolved' => 'Résolu', _ => 'Rejeté' },
                                tone: switch (d.s('status')) { 'open' => TratraTone.danger, 'under_review' => TratraTone.warning, 'resolved' => TratraTone.success, _ => TratraTone.gray }),
                          ]),
                          Text(d.s('reason'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                          if (d.s('resolution').isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Décision de Tratra : ${d.s('resolution')}', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft))),
                        ]),
                      ),
                  ]),
                ),
              ),
      ),
      TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Historique', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: 4),
          Text('Chaque étape du contrat, en ajout seulement : rien n’est jamais effacé.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: 12),
          EngLoader<EngPage>(
            reloadKey: c.i('version'),
            load: () async {
              final p = await widget.api.getPage('/contracts/${c.i('id')}/history/?limit=50');
              _extra.clear();
              _more = p.nextOffset;
              return p;
            },
            builder: (ctx, page, _) {
              final events = [...page.results, ..._extra];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (events.isEmpty) const TratraEmptyState(compact: true, title: 'Aucun événement'),
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(margin: const EdgeInsets.only(top: 6, right: 10), width: 8, height: 8, decoration: const BoxDecoration(color: TtColors.primary, shape: BoxShape.circle)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(contractEventFr[e.s('type')] ?? e.s('type').replaceAll('_', ' '), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                          Text('${e['actor'] is Map ? e.m('actor').s('name') : 'Tratra (automatique)'} · ${dateTimeFr(e.sn('at'))}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                        ]),
                      ),
                    ]),
                  ),
                if (_more != null) TratraButton(label: 'Voir les événements plus anciens', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: _loadMore),
                if (_moreError != null) Text(_moreError!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
              ]);
            },
          ),
        ]),
      ),
    ]);
  }
}
