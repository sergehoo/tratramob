// lib/engagements/contract_pay.dart
//
// Rémunération d'un contrat : échéances générées automatiquement, ajustements acceptés par la contrepartie, paiements
// DÉCLARÉS par une partie puis CONFIRMÉS par l'autre (jamais par son auteur). Tratra ne verse ni n'encaisse rien et ne
// calcule aucun élément légal.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';

class ContractPay extends StatefulWidget {
  const ContractPay({super.key, required this.api, required this.c, required this.onChanged});
  final EngagementsApi api;
  final Json c;
  final Future<void> Function() onChanged;
  @override
  State<ContractPay> createState() => _ContractPayState();
}

class _ContractPayState extends State<ContractPay> {
  int _version = 0;

  void _refresh() {
    setState(() => _version++);
    widget.onChanged();
  }

  Future<void> _open(Json i) async {
    await showTratraSheet<void>(
      context,
      title: 'Échéance ${i.s('number')} · ${dateShortFr(i.sn('period_start'))} → ${dateShortFr(i.sn('period_end'))}',
      child: InstallmentDetail(api: widget.api, c: widget.c, id: i.i('id'), onChanged: _refresh),
    );
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TratraAlert(
            tone: TratraAlertTone.brand,
            title: 'Comment fonctionne la rémunération',
            message: 'Les échéances sont générées automatiquement. Tratra ne verse ni n’encaisse rien : un paiement est déclaré par une partie puis confirmé par l’autre. Aucun montant légal (cotisations, impôts) n’est calculé.',
          ),
          const SizedBox(height: 14),
          EngLoader<List<Json>>(
            reloadKey: _version,
            load: () => widget.api.getList('/contracts/${widget.c.i('id')}/installments/'),
            builder: (ctx, rows, _) => rows.isEmpty
                ? const TratraEmptyState(compact: true, icon: Icons.payments_outlined, title: 'Aucune échéance pour le moment', description: 'Les échéances sont créées à l’acceptation du contrat, période après période.')
                : Column(children: [
                    for (final i in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TratraCard(
                          padding: TratraCard.compact,
                          onTap: () => _open(i),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Échéance ${i.s('number')} · ${dateShortFr(i.sn('period_start'))} → ${dateShortFr(i.sn('period_end'))}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('À régler le ${dateFr(i.sn('due_date'))}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                              ]),
                            ),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(i.b('computed') ? fcfa(i.s('total'), i.s('currency', 'XOF')) : '—', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              StatusChip(installmentStatus(i.s('status'))),
                              if ((num.tryParse(i.s('declared')) ?? 0) > 0) const Padding(padding: EdgeInsets.only(top: 4), child: TratraBadge('À confirmer', tone: TratraTone.accent)),
                            ]),
                          ]),
                        ),
                      ),
                  ]),
          ),
        ],
      );
}

/// Détail d'une échéance : montants, paiements (confirmer / contester), ajustements, actions.
class InstallmentDetail extends StatefulWidget {
  const InstallmentDetail({super.key, required this.api, required this.c, required this.id, required this.onChanged});
  final EngagementsApi api;
  final Json c;
  final int id;
  final VoidCallback onChanged;
  @override
  State<InstallmentDetail> createState() => _InstallmentDetailState();
}

class _InstallmentDetailState extends State<InstallmentDetail> {
  int _version = 0;

  void _refresh() {
    setState(() => _version++);
    widget.onChanged();
  }

  Future<void> _declare(Json i) async {
    final base = randomHex();
    String? file;
    final today = DateTime.now();
    final remaining = num.tryParse(i.s('remaining_to_declare')) ?? 0;
    final advance = i['advance_remaining'] == null ? null : num.tryParse(i.s('advance_remaining'));
    final limit = advance == null ? remaining : (remaining < advance ? remaining : advance);
    final other = widget.c.s('my_role') == 'principal' ? widget.c.m('worker').s('name') : widget.c.m('principal').s('name');
    final done = await showActionSheet(
      context,
      title: 'Déclarer un paiement',
      description: 'Il ne comptera qu’une fois confirmé par $other — Tratra n’encaisse ni ne verse rien : déclarez uniquement un paiement réellement effectué.',
      confirmLabel: 'Déclarer le paiement',
      header: AttachPicker(onPicked: (p) => file = p),
      fields: [
        FieldSpec('amount', 'Montant (FCFA)', kind: FieldKind.number, required: true, initial: limit > 0 ? '${limit.round()}' : '',
            hint: advance != null ? 'Période en cours : avance limitée à ${fcfa(advance)} (règle de la catégorie). Solde de l’échéance : ${fcfa(remaining)}.' : 'Solde restant à déclarer : ${fcfa(remaining)}.'),
        FieldSpec('method', 'Moyen de paiement', kind: FieldKind.select, options: [for (final e in paymentMethodFr.entries) (e.key, e.value)], initial: 'mobile_money'),
        FieldSpec('paid_on', 'Date du paiement', kind: FieldKind.date, required: true, initial: isoDay(today), lastDate: today),
        const FieldSpec('reference', 'Référence', optional: true, hint: 'Numéro de transaction, de virement ou de reçu.', maxLength: 100),
      ],
      submit: (v) => widget.api.postForm('/installments/${i.i('id')}/payments/', {'amount': v['amount'] ?? '', 'method': v['method'] ?? '', 'paid_on': v['paid_on'] ?? '', 'reference': v['reference'] ?? ''},
          filePath: file, idempotencyKey: intentKey('pay', base, {...v, 'f': file})),
    );
    if (done) _refresh();
  }

  Future<void> _adjust(Json i) async {
    final base = randomHex();
    String? file;
    final done = await showActionSheet(
      context,
      title: 'Proposer un ajustement',
      description: 'Prime, frais, retenue ou correction : il ne compte qu’une fois accepté par l’autre partie.',
      confirmLabel: 'Proposer',
      header: AttachPicker(onPicked: (p) => file = p),
      fields: [
        FieldSpec('kind', 'Nature', kind: FieldKind.select, options: [for (final e in lineKindFr.entries) if (e.key != 'overtime') (e.key, e.value)], initial: 'bonus'),
        const FieldSpec('amount', 'Montant (FCFA)', kind: FieldKind.number, required: true, hint: 'Une retenue est saisie en positif : elle est déduite.'),
        const FieldSpec('description', 'Description', required: true, maxLength: 300),
      ],
      submit: (v) => widget.api.postForm('/installments/${i.i('id')}/lines/', {'kind': v['kind'] ?? '', 'amount': v['amount'] ?? '', 'description': v['description'] ?? ''}, filePath: file, idempotencyKey: intentKey('line', base, {...v, 'f': file})),
    );
    if (done) _refresh();
  }

  Future<void> _contest(Json p) async {
    final done = await showActionSheet(
      context,
      title: 'Contester ce paiement',
      description: 'Expliquez pourquoi il est inexact : l’autre partie en est informée. Un désaccord persistant peut être signalé à Tratra.',
      confirmLabel: 'Contester',
      danger: true,
      fields: const [FieldSpec('reason', 'Motif', kind: FieldKind.multiline, required: true)],
      submit: (v) => widget.api.post('/payments/${p.i('id')}/respond/', {'confirm': false, 'reason': v['reason']}),
    );
    if (done) _refresh();
  }

  Future<void> _waive(Json i) async {
    final done = await showActionSheet(
      context,
      title: 'Abandonner le solde ?',
      description: 'Vous renoncez au solde de ${fcfa(i.s('balance'))}. C’est définitif et seul le prestataire peut le décider.',
      confirmLabel: 'Abandonner le solde',
      danger: true,
      fields: const [FieldSpec('reason', 'Motif', kind: FieldKind.multiline, required: true)],
      submit: (v) => widget.api.post('/installments/${i.i('id')}/waive/', {'reason': v['reason']}),
    );
    if (done) _refresh();
  }

  @override
  Widget build(BuildContext context) => EngLoader<Json>(
        reloadKey: _version,
        load: () => widget.api.getMap('/installments/${widget.id}/'),
        builder: (ctx, i, _) {
          final computed = i.b('computed');
          final open = !const {'waived', 'cancelled', 'paid'}.contains(i.s('status'));
          final remaining = num.tryParse(i.s('remaining_to_declare')) ?? 0;
          final payments = i.l('payments'), lines = i.l('lines');
          final cur = i.s('currency', 'XOF');
          Widget kpi(String label, String value) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label.toUpperCase(), style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w700, fontSize: 10)),
                    const SizedBox(height: 2),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
                  ]),
                ),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [kpi('Dû', computed ? fcfa(i.s('total'), cur) : '—'), kpi('Confirmé', fcfa(i.s('confirmed'), cur)), kpi('Solde', computed ? fcfa(i.s('balance'), cur) : '—')]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Échéance le ${dateFr(i.sn('due_date'))}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              StatusChip(installmentStatus(i.s('status'))),
            ]),
            if ((num.tryParse(i.s('declared')) ?? 0) > 0) Text('${fcfa(i.s('declared'), cur)} déclaré(s), en attente de confirmation', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            if (!computed) ...[const SizedBox(height: 10), TratraAlert(tone: TratraAlertTone.info, message: 'Rémunération ${widget.c.s('period') == 'hourly' ? 'à l’heure' : 'à l’intervention'} : le montant est calculé à la fin de la période à partir des présences confirmées par le donneur d’ordre.')],
            if ((num.tryParse(i.s('platform_fee')) ?? 0) > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Commission Tratra : ${fcfa(i.s('platform_fee'), cur)}, à la charge du ${i.s('platform_fee_payer') == 'worker' ? 'prestataire' : 'donneur d’ordre'} — distincte de la rémunération.', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
            const SizedBox(height: 14),
            Text('Paiements', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (payments.isEmpty) Text('Aucun paiement déclaré.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            for (final p in payments) _PaymentTile(api: widget.api, c: widget.c, p: p, onDone: _refresh, onContest: () => _contest(p)),
            const SizedBox(height: 10),
            Text('Ajustements', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (lines.isEmpty) Text('Aucun ajustement (prime, frais, retenue, heures supplémentaires).', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            for (final l in lines) _LineTile(api: widget.api, l: l, onDone: _refresh),
            if (open) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (computed && remaining > 0) TratraButton(label: 'Déclarer un paiement', size: TratraButtonSize.sm, leading: const Icon(Icons.payments_outlined, size: 18), onPressed: () => _declare(i)),
                TratraButton(label: 'Proposer un ajustement', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _adjust(i)),
                if (i.b('can_waive')) TratraButton(label: 'Abandonner le solde', size: TratraButtonSize.sm, variant: TratraButtonVariant.ghost, onPressed: () => _waive(i)),
              ]),
            ],
          ]);
        },
      );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.api, required this.c, required this.p, required this.onDone, required this.onContest});
  final EngagementsApi api;
  final Json c;
  final Json p;
  final VoidCallback onDone;
  final VoidCallback onContest;

  @override
  Widget build(BuildContext context) {
    final status = p.s('status');
    final tone = status == 'confirmed' ? TratraTone.success : (status == 'declared' ? TratraTone.accent : TratraTone.danger);
    final label = status == 'confirmed' ? 'Confirmé' : (status == 'declared' ? 'À confirmer' : 'Contesté');
    final who = p.b('mine') ? 'vous' : (p.s('declared_by_role') == 'principal' ? c.m('principal').s('name') : c.m('worker').s('name'));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${fcfa(p.s('amount'), c.s('currency', 'XOF'))} · ${paymentMethodFr[p.s('method')] ?? p.s('method')}${p.b('is_advance') ? ' · avance' : ''}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
          TratraBadge(label, tone: tone),
        ]),
        const SizedBox(height: 2),
        Text('Déclaré par $who · versé le ${dateFr(p.sn('paid_on'))}${p.s('reference').isNotEmpty ? ' · réf. ${p.s('reference')}' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (status == 'confirmed' && p['trust'] is Map && p.m('trust').s('note').isNotEmpty) Text(p.m('trust').s('note'), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (status == 'rejected' && p.s('rejection_reason').isNotEmpty) Text('Motif de contestation : ${p.s('rejection_reason')}', style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
        if (p['evidence'] is Map) EvidenceLink(api: api, evidence: p.m('evidence')),
        if (status == 'declared' && p.b('mine')) Text('En attente de confirmation de l’autre partie : un paiement ne se confirme jamais soi-même.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (p.b('can_respond'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              AsyncAction(label: 'Je confirme avoir ${c.s('my_role') == 'worker' ? 'reçu' : 'payé'} ce montant', run: () async {
                await api.post('/payments/${p.i('id')}/respond/', {'confirm': true});
                onDone();
              }),
              TratraButton(label: 'Contester', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: onContest),
            ]),
          ),
      ]),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.api, required this.l, required this.onDone});
  final EngagementsApi api;
  final Json l;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final status = l.s('status');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${lineKindFr[l.s('kind')] ?? l.s('kind')} · ${fcfa(l.s('amount'))}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
          TratraBadge(status == 'accepted' ? 'Accepté' : (status == 'proposed' ? 'À valider' : 'Refusé'), tone: status == 'accepted' ? TratraTone.success : (status == 'proposed' ? TratraTone.accent : TratraTone.gray)),
        ]),
        const SizedBox(height: 2),
        Text(l.s('description'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        if (l['evidence'] is Map) EvidenceLink(api: api, evidence: l.m('evidence')),
        if (l.b('can_respond'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              AsyncAction(label: 'Accepter', run: () async {
                await api.post('/lines/${l.i('id')}/respond/', {'accept': true});
                onDone();
              }),
              AsyncAction(label: 'Refuser', variant: TratraButtonVariant.outline, run: () async {
                await api.post('/lines/${l.i('id')}/respond/', {'accept': false});
                onDone();
              }),
            ]),
          ),
      ]),
    );
  }
}
