// lib/engagements/contract_screen.dart
//
// Fiche d'un contrat d'engagement : résumé (conditions, acceptation sur l'empreinte EXACTE, préavis, reprise, litige),
// rémunération, planning, avenants, évaluations, historique. Les actions proposées viennent du serveur (`actions`).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/contract_extras.dart';
import 'package:flutter_tratra/engagements/contract_form.dart';
import 'package:flutter_tratra/engagements/contract_pay.dart';
import 'package:flutter_tratra/engagements/contract_planning.dart';
import 'package:flutter_tratra/engagements/contract_sealed.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show DashPage;

enum ContractTab { summary, pay, planning, amendments, evaluations, history }

class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key, required this.id, this.tab = ContractTab.summary});
  final int id;
  final ContractTab tab;
  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  Json? _c;
  String? _error;
  bool _loading = true;
  late ContractTab _tab = widget.tab;
  bool _openAmend = false;
  bool _proposing = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _api.getMap('/contracts/${widget.id}/');
      if (!mounted) return;
      setState(() {
        _c = c;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageOf(e, 'Ce contrat ne peut pas être chargé pour le moment.');
        _loading = false;
      });
    }
  }

  Future<void> _propose(Json c) async {
    setState(() => _proposing = true);
    try {
      await _api.post('/contracts/${c.i('id')}/propose/', {'expected_version': c.i('version')});
      _notice = 'Contrat proposé à ${c.m('worker').s('name')}. Vous serez prévenu(e) de sa réponse.';
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e));
    } finally {
      if (mounted) setState(() => _proposing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return DashPage(
        title: 'Contrat',
        body: _loading
            ? const TratraSkeletonList(count: 3)
            : TratraEmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Contrat indisponible',
                description: _error,
                actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: () {
                  setState(() => _loading = true);
                  _load();
                })],
              ),
      );
    }
    final status = c.s('status');
    final started = const {'signed', 'active', 'suspended', 'notice', 'terminated', 'completed'}.contains(status) ||
        (status == 'accepted' && _c?['signature_required'] != true);
    final tabs = <(ContractTab, String)>[
      (ContractTab.summary, 'Résumé'),
      if (started) ...[(ContractTab.pay, 'Rémunération'), (ContractTab.planning, 'Planning'), (ContractTab.amendments, 'Avenants'), (ContractTab.evaluations, 'Évaluations')],
      (ContractTab.history, 'Historique'),
    ];
    final tab = tabs.any((t) => t.$1 == _tab) ? _tab : ContractTab.summary;
    final role = c.s('my_role');
    return DashPage(
      title: c.s('title'),
      body: RefreshIndicator(
        color: TtColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(contractStatusOf(c)),
              Text('${role == 'worker' ? 'Pour' : 'Avec'} ${c.m('counterpart').s('name')} · ${fcfa(c.s('amount'), c.s('currency', 'XOF'))} ${periodFr[c.s('period')] ?? ''}',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            ]),
            if (status == 'draft') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TratraButton(label: 'Modifier', variant: TratraButtonVariant.outline, onPressed: () async {
                  final changed = await goTo<bool>(context, ContractFormScreen(existing: c));
                  if (changed == true) await _load();
                })),
                const SizedBox(width: 10),
                Expanded(child: TratraButton(label: 'Proposer', loading: _proposing, onPressed: _proposing ? null : () => _propose(c))),
              ]),
            ],
            if (_notice != null) ...[const SizedBox(height: 12), TratraAlert(tone: TratraAlertTone.success, message: _notice!, onDismiss: () => setState(() => _notice = null))],
            if (_error != null) ...[const SizedBox(height: 12), TratraAlert(tone: TratraAlertTone.danger, message: _error!, onDismiss: () => setState(() => _error = null))],
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (t, label) in tabs) Padding(padding: const EdgeInsets.only(right: 8), child: TratraChip(label: label, selected: t == tab, onTap: () => setState(() => _tab = t))),
              ]),
            ),
            const SizedBox(height: 16),
            switch (tab) {
              ContractTab.summary => ContractSummary(api: _api, c: c, reload: _load, goTab: (t) => setState(() => _tab = t), openAmend: () => setState(() {
                    _tab = ContractTab.amendments;
                    _openAmend = true;
                  })),
              ContractTab.pay => ContractPay(api: _api, c: c, onChanged: _load),
              ContractTab.planning => ContractPlanning(api: _api, c: c, onChanged: _load),
              ContractTab.amendments => ContractAmendments(api: _api, c: c, onChanged: _load, openNew: _openAmend, onOpened: () => _openAmend = false),
              ContractTab.evaluations => ContractEvaluations(api: _api, c: c),
              ContractTab.history => ContractHistory(api: _api, c: c),
            },
          ],
        ),
      ),
    );
  }
}

// ── Résumé ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class ContractSummary extends StatelessWidget {
  const ContractSummary({super.key, required this.api, required this.c, required this.reload, required this.goTab, required this.openAmend});
  final EngagementsApi api;
  final Json c;
  final Future<void> Function() reload;
  final ValueChanged<ContractTab> goTab;
  final VoidCallback openAmend;

  bool has(String a) => c.strs('actions').contains(a);

  @override
  Widget build(BuildContext context) {
    final status = c.s('status');
    final role = c.s('my_role');
    final iAccepted = c.strs('accepted_by').contains(role);
    final pending = c['pending_amendment'] is Map ? c.m('pending_amendment') : null;
    final suspensions = c.l('suspensions');
    final adminSuspended = suspensions.any((s) => s.s('source') == 'admin' && s.sn('ends_on') == null);
    final renewal = c.b('auto_renew') && c.sn('end_date') != null
        ? 'Automatique (${c.i('renewal_term_months')} mois)${c.sn('non_renewal_at') != null ? ' — refusé' : c.sn('non_renewal_deadline') != null ? ', non-renouvellement possible jusqu’au ${dateFr(c.sn('non_renewal_deadline'))}' : ''}'
        : 'Non';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == 'pending_acceptance' && has('accept')) _AcceptCard(api: api, c: c, onChanged: reload),
        SignContractCard(api: api, c: c, onChanged: reload),
        if (status == 'pending_acceptance' && iAccepted)
          TratraAlert(tone: TratraAlertTone.info, title: 'En attente de l’autre partie', message: '${c.m('counterpart').s('name')} doit relire et accepter ces conditions. Vous serez prévenu(e) dès sa réponse.'),
        if (status == 'draft')
          TratraAlert(tone: TratraAlertTone.brand, title: 'Brouillon', message: 'Ce contrat n’est visible que de vous. « Proposer » l’envoie à ${c.m('worker').s('name')}, qui peut l’accepter, demander une modification ou le refuser.'),
        if (pending != null) ...[const SizedBox(height: 12), AmendmentCard(api: api, a: pending, onChanged: reload)],
        if (status == 'notice') ...[const SizedBox(height: 12), TratraAlert(tone: TratraAlertTone.warning, title: 'Préavis en cours : fin le ${dateFr(c.sn('ends_on'))}', message: c.s('end_reason'))],
        if (adminSuspended) ...[
          const SizedBox(height: 12),
          const TratraAlert(tone: TratraAlertTone.danger, title: 'Contrat suspendu par Tratra', message: 'La plateforme a suspendu ce contrat. Elle seule peut lever la suspension ; vous serez informé(e) de la suite.'),
        ],
        const SizedBox(height: 12),
        TratraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('Conditions', style: TratraTheme.style(TtType.h2))),
                TextButton.icon(onPressed: () => _showDocument(context), icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Document')),
              ]),
              const SizedBox(height: 8),
              Facts([
                ('Donneur d’ordre', '${c.m('principal').s('name')}${c.m('organization').sn('name') != null ? ' (${c.m('organization').s('name')})' : ''}'),
                ('Prestataire', c.m('worker').s('name')),
                ('Nature', relationshipFr[c.s('work_relationship')]),
                ('Type', missionTypeFr[c.s('mission_type')]),
                ('Rémunération', '${fcfa(c.s('amount'), c.s('currency', 'XOF'))} ${periodFr[c.s('period')] ?? ''}'),
                ('Paiement', c.sn('payment_day') == null ? null : 'le ${c.s('payment_day')} qui suit la fin de chaque période'),
                ('Début', dateFr(c.sn('start_date'))),
                ('Fin', c.sn('end_date') == null ? 'Durée indéterminée' : '${dateFr(c.sn('end_date'))} (${durationLabel(c)})'),
                ('Planning', scheduleLabel(c.l('schedule'))),
                ('Préavis', '${c.s('notice_period_days')} jours'),
                ('Lieu', [c.s('location_address'), c.s('location_city')].where((e) => e.isNotEmpty).join(', ')),
                ('Renouvellement', renewal),
                ('Heures supplémentaires', c.sn('overtime_hourly_rate') == null ? 'Non valorisées' : '${fcfa(c.sn('overtime_hourly_rate'))} / h'),
                ('Prorata dernière période', c.s('proration_mode') == 'calendar_days' ? 'Jours calendaires' : 'Aucun'),
                ('Réservations', c.s('bookings_mode') == 'per_occurrence' ? 'Une réservation Tratra par intervention' : 'Aucune'),
                ('Avantages', c.s('benefits').isEmpty ? null : c.s('benefits')),
                ('Référence', c.sn('reference')),
              ]),
              if (c.s('description').isNotEmpty) ...[Text('Missions confiées', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(c.s('description'), style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)), const SizedBox(height: 12)],
              if (c.s('conditions').isNotEmpty) ...[Text('Conditions particulières', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(c.s('conditions'), style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)), const SizedBox(height: 12)],
              if (suspensions.isNotEmpty) ...[
                Text('Suspensions', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                for (final s in suspensions)
                  Text('Du ${dateFr(s.sn('starts_on'))} ${s.sn('ends_on') != null ? 'au ${dateFr(s.sn('ends_on'))}' : '(sans date de fin)'} — ${s.s('source') == 'admin' ? 'décision de Tratra' : 'd’un commun accord'} : ${s.s('reason')}',
                      style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
                child: Text('${c.s('legal_notice')} Les paiements sont déclarés par une partie et ne comptent qu’une fois confirmés par l’autre : Tratra ne verse ni n’encaisse la rémunération.',
                    style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              ),
            ],
          ),
        ),
        ContractArticlesCard(c: c),
        ContractDocumentsCard(api: api, c: c),
        if (const {'accepted', 'signed', 'active', 'suspended', 'notice', 'terminated', 'completed'}.contains(status) && !(status == 'accepted' && c.b('signature_required'))) ...[
          const SizedBox(height: 16),
          TratraCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Actions', style: TratraTheme.style(TtType.h2)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (has('propose_amendment') && pending == null) TratraButton(label: 'Proposer un avenant', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: openAmend),
                if (has('give_notice')) TratraButton(label: 'Donner un préavis', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _notice(context)),
                if (has('declare_non_renewal'))
                  AsyncAction(label: 'Refuser le renouvellement', variant: TratraButtonVariant.outline, confirm: 'Le contrat prendra fin à son terme, le ${dateFr(c.sn('end_date'))}. L’autre partie en est informée.', run: () async {
                    await api.post('/contracts/${c.i('id')}/non-renewal/');
                    await reload();
                  }),
                if (has('resume'))
                  AsyncAction(label: 'Reprendre le contrat', variant: TratraButtonVariant.outline, confirm: 'La suspension convenue prend fin aujourd’hui.', run: () async {
                    await api.post('/contracts/${c.i('id')}/resume/');
                    await reload();
                  }),
                if (has('evaluate')) TratraButton(label: 'Évaluer', size: TratraButtonSize.sm, variant: TratraButtonVariant.soft, onPressed: () => goTab(ContractTab.evaluations)),
                if (has('close'))
                  AsyncAction(label: 'Clôturer le contrat', variant: TratraButtonVariant.outline, confirm: 'L’historique financier est figé. Possible seulement quand plus aucune échéance n’est due.', run: () async {
                    await api.post('/contracts/${c.i('id')}/close/');
                    await reload();
                  }),
                if (has('dispute')) TratraButton(label: 'Signaler un désaccord', size: TratraButtonSize.sm, variant: TratraButtonVariant.ghost, onPressed: () => _dispute(context)),
              ]),
            ]),
          ),
        ],
      ],
    );
  }

  Future<void> _notice(BuildContext context) async {
    final base = randomHex();
    final min = DateTime.now().add(Duration(days: c.i('notice_period_days')));
    final done = await showActionSheet(
      context,
      title: 'Donner un préavis',
      description: 'Le contrat prévoit ${c.s('notice_period_days')} jours de préavis. Il se termine à la date choisie ; les échéances postérieures sont annulées.',
      confirmLabel: 'Donner le préavis',
      danger: true,
      fields: [FieldSpec('last_day', 'Dernier jour du contrat', kind: FieldKind.date, required: true, hint: 'Au plus tôt le ${dateFr(isoDay(min))}.', firstDate: min), const FieldSpec('reason', 'Motif', kind: FieldKind.multiline, required: true)],
      submit: (v) => api.post('/contracts/${c.i('id')}/notice/', {'last_day': v['last_day'], 'reason': v['reason'], 'expected_version': c.i('version')}, intentKey('notice', base, v)),
    );
    if (done) await reload();
  }

  Future<void> _dispute(BuildContext context) async {
    final base = randomHex();
    final done = await showActionSheet(
      context,
      title: 'Signaler un désaccord',
      description: 'Un litige est examiné par l’équipe Tratra, qui peut médier, suspendre ou résilier le contrat. Il ne modifie aucun montant.',
      confirmLabel: 'Ouvrir le litige',
      fields: [
        FieldSpec('kind', 'Nature', kind: FieldKind.select, options: [for (final e in disputeKindFr.entries) (e.key, e.value)], initial: 'conditions'),
        const FieldSpec('reason', 'Décrivez le désaccord', kind: FieldKind.multiline, required: true, hint: 'Faits, dates, ce que vous attendez (10 caractères minimum).', maxLength: 2000),
      ],
      submit: (v) => api.post('/contracts/${c.i('id')}/disputes/', {'kind': v['kind'], 'reason': v['reason']}, intentKey('dispute', base, v)),
    );
    if (done) {
      goTab(ContractTab.history);
      await reload();
    }
  }

  Future<void> _showDocument(BuildContext context) => showTratraSheet<void>(
        context,
        title: 'Document du contrat',
        description: 'Trace des acceptations de chaque version des conditions.',
        child: EngLoader<Json>(
          load: () => api.getMap('/contracts/${c.i('id')}/document/'),
          builder: (ctx, d, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.s('notice'), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            const SizedBox(height: 10),
            Text('Version ${d.s('terms_version')} · empreinte ${d.s('terms_hash')}', style: TratraTheme.style(TtType.bodySm)),
            const SizedBox(height: 10),
            Text('Acceptations', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
            for (final a in d.l('acceptances')) Text('${roleFr[a.s('role')]} — ${a.m('user').s('name')} · version ${a.s('terms_version')} · ${dateTimeFr(a.sn('accepted_at'))}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
          ]),
        ),
      );
}

/// Acceptation liée à l'empreinte EXACTE des conditions affichées : si elles ont changé entre-temps, le serveur refuse.
class _AcceptCard extends StatefulWidget {
  const _AcceptCard({required this.api, required this.c, required this.onChanged});
  final EngagementsApi api;
  final Json c;
  final Future<void> Function() onChanged;
  @override
  State<_AcceptCard> createState() => _AcceptCardState();
}

class _AcceptCardState extends State<_AcceptCard> {
  final _base = randomHex();
  bool _read = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final hash = widget.c.s('terms_hash');
    try {
      await widget.api.post('/contracts/${widget.c.i('id')}/accept/', {'terms_hash': hash}, intentKey('accept', _base, hash));
      await widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e, 'Acceptation impossible. Rien n’a été enregistré.'));
      await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendBack() async {
    final done = await showActionSheet(
      context,
      title: 'Demander une modification',
      description: 'Le contrat repasse en brouillon chez son auteur, avec votre demande.',
      confirmLabel: 'Envoyer la demande',
      fields: const [FieldSpec('note', 'Ce que vous souhaitez changer', kind: FieldKind.multiline, required: true)],
      submit: (v) => widget.api.post('/contracts/${widget.c.i('id')}/send-back/', {'note': v['note']}),
    );
    if (done) await widget.onChanged();
  }

  Future<void> _decline() async {
    final done = await showActionSheet(
      context,
      title: 'Refuser ce contrat ?',
      description: 'Il est annulé ; l’autre partie en est informée.',
      confirmLabel: 'Refuser le contrat',
      danger: true,
      fields: const [FieldSpec('reason', 'Motif', kind: FieldKind.multiline, optional: true)],
      submit: (v) => widget.api.post('/contracts/${widget.c.i('id')}/decline/', {'reason': v['reason']}),
    );
    if (done) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TratraCard(
        variant: TratraCardVariant.accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ce contrat attend votre réponse', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: 6),
          Text('${c.m('counterpart').s('name')} vous propose ces conditions. Relisez-les en entier : votre acceptation porte sur cette version exacte.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _read,
            onChanged: (v) => setState(() => _read = v == true),
            title: Text('J’ai lu les conditions ci-dessous (version ${c.s('terms_version')}, empreinte ${c.s('terms_hash').substring(0, c.s('terms_hash').length < 8 ? c.s('terms_hash').length : 8)}) et j’accepte ce contrat.', style: TratraTheme.style(TtType.bodySm)),
          ),
          if (_error != null) ...[TratraAlert(tone: TratraAlertTone.danger, message: _error!), const SizedBox(height: 10)],
          TratraButton(label: 'Accepter le contrat', block: true, loading: _busy, onPressed: _read && !_busy ? _accept : null),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TratraButton(label: 'Demander une modification', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: _sendBack)),
            const SizedBox(width: 8),
            TratraButton(label: 'Refuser', size: TratraButtonSize.sm, variant: TratraButtonVariant.ghost, onPressed: _decline),
          ]),
        ]),
      ),
    );
  }
}
