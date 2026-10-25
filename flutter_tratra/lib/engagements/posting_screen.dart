// lib/engagements/posting_screen.dart
//
// Un besoin de longue durée : détail, candidatures reçues (présélection, entretien, choix, préparation du contrat) pour son
// auteur ; candidature, entretiens et retrait pour un professionnel vérifié. Les droits viennent du serveur.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/contract_form.dart';
import 'package:flutter_tratra/engagements/contract_screen.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/engagements/posting_form.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show DashPage;

class PostingScreen extends StatefulWidget {
  const PostingScreen({super.key, required this.id});
  final int id;
  @override
  State<PostingScreen> createState() => _PostingScreenState();
}

class _PostingScreenState extends State<PostingScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  Json? _p;
  Json? _mine; // ma candidature (si je ne suis pas l'auteur)
  String? _error;
  bool _loading = true;
  int _apps = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.getMap('/postings/${widget.id}/');
      Json? mine;
      if (!p.b('mine')) {
        final apps = await _api.getList('/applications/mine/?limit=50');
        mine = apps.where((a) => a.i('posting') == widget.id).firstOrNull;
      }
      if (!mounted) return;
      setState(() {
        _p = p;
        _mine = mine;
        _error = null;
        _loading = false;
        _apps++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = messageOf(e, 'Ce besoin ne peut pas être chargé pour le moment.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return DashPage(
        title: 'Besoin',
        body: _loading
            ? const TratraSkeletonList(count: 3)
            : TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Besoin indisponible', description: _error, actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: () {
                setState(() => _loading = true);
                _load();
              })]),
      );
    }
    final mine = p.b('mine');
    final status = p.s('status');
    return DashPage(
      title: p.s('title'),
      body: RefreshIndicator(
        color: TtColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusChip(postingStatus(status)),
              Text('${p.m('category').s('name')} · ${p.s('city')} · ${missionTypeFr[p.s('mission_type')] ?? ''} · ${p['organization'] is Map ? p.m('organization').s('name') : p.m('publisher').s('name')}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            ]),
            if (mine) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (status == 'draft' || status == 'open')
                  TratraButton(label: 'Modifier', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () async {
                    await goTo<void>(context, PostingFormScreen(existing: p));
                    if (mounted) await _load();
                  }),
                if (status == 'draft')
                  AsyncAction(label: 'Publier', run: () async {
                    await _api.post('/postings/${p.i('id')}/publish/');
                    await _load();
                  }),
                if (status == 'open')
                  AsyncAction(label: 'Clore le besoin', variant: TratraButtonVariant.outline, confirm: 'Il n’accepte plus de candidatures. Les candidatures déjà reçues restent consultables.', run: () async {
                    await _api.post('/postings/${p.i('id')}/close/');
                    await _load();
                  }),
              ]),
            ],
            if (p.s('work_relationship') == 'employment' && p.s('legal_notice').isNotEmpty) ...[const SizedBox(height: 12), TratraAlert(tone: TratraAlertTone.warning, title: relationshipFr['employment'], message: p.s('legal_notice'))],
            const SizedBox(height: 12),
            TratraCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Facts([
                  ('Rémunération', '${fcfa(p.sn('amount'), p.s('currency', 'XOF'))} ${periodFr[p.s('period')] ?? ''}'),
                  ('Nature', relationshipFr[p.s('work_relationship')]),
                  ('Début souhaité', p.sn('start_date') == null ? null : dateFr(p.sn('start_date'))),
                  ('Fin souhaitée', p.sn('end_date') != null ? dateFr(p.sn('end_date')) : p.sn('duration_months') != null ? 'Selon la durée envisagée' : 'Durée indéterminée'),
                  ('Planning', scheduleLabel(p.l('schedule'))),
                  ('Heures par semaine', p.sn('hours_per_week') == null ? null : '${num.tryParse(p.s('hours_per_week'))} h'),
                  ('Candidatures jusqu’au', p.sn('application_deadline') == null ? 'Sans date limite' : dateFr(p.sn('application_deadline'))),
                  ('Zone', p.sn('location_note')),
                  ('Durée envisagée', p.sn('duration_months') == null ? null : '${p.s('duration_months')} mois'),
                  ('Avantages', p.sn('benefits') == null || p.s('benefits').isEmpty ? null : p.s('benefits')),
                ]),
                if (p.s('description').isNotEmpty) ...[Text('Mission', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(p.s('description'), style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)), const SizedBox(height: 12)],
                if (p.s('conditions').isNotEmpty) ...[Text('Conditions', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(p.s('conditions'), style: TratraTheme.style(TtType.body, color: TtColors.inkSoft))],
              ]),
            ),
            const SizedBox(height: 16),
            if (mine && p.s('status') == 'open') ...[_InvitePanel(api: _api, postingId: p.i('id')), const SizedBox(height: 16)],
            if (mine) _Applications(api: _api, posting: p, version: _apps, onChanged: _load) else _ApplyBlock(api: _api, posting: p, mine: _mine, onChanged: _load),
          ],
        ),
      ),
    );
  }
}

// ── Côté auteur ─────────────────────────────────────────────────────────────────────────────────────────────────────

const _invitationStatusFr = {'sent': 'Envoyée', 'accepted': 'Candidature reçue', 'declined': 'Déclinée', 'cancelled': 'Retirée'};

/// Inviter un professionnel VÉRIFIÉ à candidater : il reste libre d'accepter (sa candidature est alors envoyée) ou de décliner.
class _InvitePanel extends StatefulWidget {
  const _InvitePanel({required this.api, required this.postingId});
  final EngagementsApi api;
  final int postingId;
  @override
  State<_InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<_InvitePanel> {
  PickedWorker? _worker;
  int _pickerKey = 0;
  int _version = 0;
  String _message = '';
  bool _busy = false;
  String? _error;

  Future<void> _invite() async {
    final w = _worker;
    if (w == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/postings/${widget.postingId}/invitations/', {'invitee': w.id, 'message': _message.trim()});
      if (!mounted) return;
      setState(() {
        _worker = null;
        _message = '';
        _pickerKey++;
        _version++;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitation envoyée à ${w.name}.')));
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e, 'Invitation impossible.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Inviter un professionnel', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: 4),
          Text('Seuls les professionnels vérifiés peuvent être invités. L’invitation leur propose de candidater ; vous choisissez ensuite.',
              style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: 12),
          WorkerPicker(key: ValueKey('invite-picker-$_pickerKey'), api: widget.api, label: 'Professionnel vérifié', onPicked: (w) => setState(() => _worker = w)),
          const SizedBox(height: 10),
          TratraInput(key: ValueKey('invite-message-$_pickerKey'), label: 'Message', optional: true, maxLength: 500, maxLines: 3, minLines: 2, onChanged: (v) => _message = v),
          if (_error != null) ...[const SizedBox(height: 8), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
          const SizedBox(height: 10),
          TratraButton(key: const ValueKey('invite-send'), label: 'Envoyer l’invitation', block: true, loading: _busy, onPressed: _worker == null || _busy ? null : _invite),
          EngLoader<Json>(
            reloadKey: _version,
            load: () => widget.api.getMap('/postings/${widget.postingId}/invitations/'),
            builder: (ctx, data, reload) {
              final rows = data.l('results');
              if (rows.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 12),
                for (final i in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(i.m('invitee').s('name'), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text(_invitationStatusFr[i.s('status')] ?? i.s('status'), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    trailing: i.s('status') == 'sent'
                        ? AsyncAction(label: 'Retirer', variant: TratraButtonVariant.ghost, confirm: 'Le professionnel ne pourra plus répondre à cette invitation.', run: () async {
                            await widget.api.post('/invitations/${i.i('id')}/cancel/');
                            await reload();
                          })
                        : null,
                  ),
              ]);
            },
          ),
        ]),
      );
}

class _Applications extends StatelessWidget {
  const _Applications({required this.api, required this.posting, required this.version, required this.onChanged});
  final EngagementsApi api;
  final Json posting;
  final int version;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Candidatures', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: 4),
          Text('Les candidats sont des professionnels vérifiés. Vous choisissez, puis vous préparez le contrat.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: 12),
          EngLoader<List<Json>>(
            reloadKey: version,
            load: () => api.getList('/postings/${posting.i('id')}/applications/?limit=50'),
            builder: (ctx, rows, _) => rows.isEmpty
                ? TratraEmptyState(compact: true, title: 'Aucune candidature pour le moment', description: posting.s('status') == 'open' ? 'Elles apparaîtront ici dès qu’un professionnel postulera.' : 'Publiez le besoin pour recevoir des candidatures.')
                : Column(children: [for (final a in rows) _ApplicationCard(api: api, a: a, onChanged: onChanged)]),
          ),
        ]),
      );
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.api, required this.a, required this.onChanged});
  final EngagementsApi api;
  final Json a;
  final Future<void> Function() onChanged;

  Future<void> _interview(BuildContext context) async {
    final base = randomHex();
    final done = await showActionSheet(
      context,
      title: 'Entretien avec ${a.m('applicant').s('name')}',
      description: 'Le candidat reçoit la proposition et la confirme ou la refuse.',
      confirmLabel: 'Proposer l’entretien',
      fields: [
        const FieldSpec('scheduled_at', 'Date et heure', kind: FieldKind.datetime, required: true),
        FieldSpec('duration_minutes', 'Durée', kind: FieldKind.select, options: [for (final m in [15, 30, 45, 60, 90]) ('$m', '$m minutes')], initial: '30'),
        FieldSpec('mode', 'Mode', kind: FieldKind.select, options: [for (final e in interviewModeFr.entries) (e.key, e.value)], initial: 'phone'),
        const FieldSpec('place_note', 'Précisions', optional: true, hint: 'Lieu de rendez-vous ou lien d’appel. Évitez les données personnelles sensibles.'),
      ],
      submit: (v) {
        final body = {'scheduled_at': v['scheduled_at'], 'duration_minutes': int.tryParse(v['duration_minutes'] ?? '') ?? 30, 'mode': v['mode'], 'place_note': v['place_note']};
        return api.post('/applications/${a.i('id')}/interviews/', body, intentKey('interview', base, {...body, 'a': a.i('id')}));
      },
    );
    if (done) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final status = a.s('status');
    final open = const {'submitted', 'shortlisted', 'interview'}.contains(status);
    final xp = a.m('experience');
    final evals = xp.m('evaluations');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: TtColors.surface, border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(a.m('applicant').s('name'), style: TratraTheme.style(TtType.h3))),
          StatusChip(applicationStatus(status)),
        ]),
        if (xp.isNotEmpty)
          Text('Expérience vérifiée sur Tratra : ${xp.i('contracts_completed')} contrat(s) terminé(s), ${xp.i('months_total')} mois${evals['average'] != null ? ', note ${evals['average']}/5 (${evals.i('count')})' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (a.s('message').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(a.s('message'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Reçue le ${dateFr(a.sn('created_at'))}${a.sn('proposed_amount') != null ? ' · propose ${fcfa(a.s('proposed_amount'))}' : ''}${a.sn('available_from') != null ? ' · disponible dès le ${dateFr(a.sn('available_from'))}' : ''}',
              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ),
        for (final i in a.l('interviews')) InterviewTile(api: api, i: i, owner: true, onDone: onChanged),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (open) ...[
            if (status == 'submitted') AsyncAction(label: 'Présélectionner', variant: TratraButtonVariant.soft, run: () async {
              await api.post('/applications/${a.i('id')}/decision/', {'decision': 'shortlist'});
              await onChanged();
            }),
            TratraButton(label: 'Proposer un entretien', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _interview(context)),
            AsyncAction(label: 'Retenir', confirm: 'Vous préparerez ensuite le contrat : rien ne vous engage tant que les deux parties ne l’ont pas accepté.', run: () async {
              await api.post('/applications/${a.i('id')}/decision/', {'decision': 'select'});
              await onChanged();
            }),
            AsyncAction(label: 'Refuser', variant: TratraButtonVariant.danger, confirm: 'Le candidat est prévenu. Cette décision est définitive pour cette candidature.', run: () async {
              await api.post('/applications/${a.i('id')}/decision/', {'decision': 'reject'});
              await onChanged();
            }),
          ],
          if (status == 'selected')
            a['contract_id'] != null
                ? TratraButton(label: 'Ouvrir le contrat', size: TratraButtonSize.sm, onPressed: () => goTo<void>(context, ContractScreen(id: a.i('contract_id'))))
                : TratraButton(label: 'Préparer le contrat', size: TratraButtonSize.sm, onPressed: () async {
                    await goTo<void>(context, ContractFormScreen(application: a.i('id'), posting: a.i('posting')));
                    await onChanged();
                  }),
        ]),
      ]),
    );
  }
}

/// Entretien proposé : l'autre partie confirme ou refuse ; l'auteur peut annuler ; le donneur d'ordre marque « effectué ».
class InterviewTile extends StatelessWidget {
  const InterviewTile({super.key, required this.api, required this.i, required this.owner, required this.onDone});
  final EngagementsApi api;
  final Json i;
  final bool owner;
  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final status = i.s('status');
    Future<void> op(String name) async {
      await api.post('/interviews/${i.i('id')}/respond/', {'op': name});
      await onDone();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${dateTimeFr(i.sn('scheduled_at'))} · ${i.s('duration_minutes')} min · ${interviewModeFr[i.s('mode')] ?? i.s('mode')}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
          TratraBadge(switch (status) { 'proposed' => 'Proposé', 'confirmed' => 'Confirmé', 'declined' => 'Refusé', 'cancelled' => 'Annulé', _ => 'Effectué' },
              tone: status == 'confirmed' ? TratraTone.success : (status == 'proposed' ? TratraTone.accent : TratraTone.gray)),
        ]),
        if (i.s('place_note').isNotEmpty) Text(i.s('place_note'), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (status == 'proposed' || status == 'confirmed')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              if (status == 'proposed' && !i.b('proposed_by_me')) ...[
                AsyncAction(label: 'Confirmer', run: () => op('confirm')),
                AsyncAction(label: 'Refuser', variant: TratraButtonVariant.outline, run: () => op('decline')),
              ],
              if (i.b('proposed_by_me') && status == 'proposed') AsyncAction(label: 'Annuler la proposition', variant: TratraButtonVariant.outline, run: () => op('cancel')),
              if (owner && status == 'confirmed') AsyncAction(label: 'Marquer comme effectué', variant: TratraButtonVariant.soft, run: () => op('done')),
            ]),
          ),
      ]),
    );
  }
}

// ── Côté professionnel ──────────────────────────────────────────────────────────────────────────────────────────────

class _ApplyBlock extends StatelessWidget {
  const _ApplyBlock({required this.api, required this.posting, required this.mine, required this.onChanged});
  final EngagementsApi api;
  final Json posting;
  final Json? mine;
  final Future<void> Function() onChanged;

  Future<void> _apply(BuildContext context) async {
    final base = randomHex();
    final done = await showActionSheet(
      context,
      title: 'Postuler',
      description: 'Votre nom public et votre expérience vérifiée sur Tratra sont partagés ; jamais votre téléphone.',
      confirmLabel: 'Envoyer ma candidature',
      fields: [
        const FieldSpec('message', 'Message', kind: FieldKind.multiline, optional: true, maxLength: 2000, hint: 'Expérience utile, disponibilités, questions.'),
        FieldSpec('proposed_amount', 'Votre montant proposé (FCFA)', kind: FieldKind.number, optional: true, hint: 'Offre : ${fcfa(posting.sn('amount'), posting.s('currency', 'XOF'))} ${periodFr[posting.s('period')] ?? ''}'),
        FieldSpec('available_from', 'Disponible à partir du', kind: FieldKind.date, optional: true, firstDate: DateTime.now()),
      ],
      submit: (v) {
        final body = {'message': v['message'], if ((v['proposed_amount'] ?? '').isNotEmpty) 'proposed_amount': v['proposed_amount'], if ((v['available_from'] ?? '').isNotEmpty) 'available_from': v['available_from']};
        return api.post('/postings/${posting.i('id')}/apply/', body, intentKey('apply', base, body));
      },
    );
    if (done) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final m = mine;
    if (m != null) {
      final status = m.s('status');
      return TratraCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('Ma candidature', style: TratraTheme.style(TtType.h2))), StatusChip(applicationStatus(status))]),
          if (m.s('message').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(m.s('message'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
          for (final i in m.l('interviews')) InterviewTile(api: api, i: i, owner: false, onDone: onChanged),
          if (status == 'selected') ...[
            const SizedBox(height: 10),
            TratraAlert(tone: TratraAlertTone.success, message: m['contract_id'] != null ? 'Votre candidature est retenue : le contrat est prêt.' : 'Votre candidature est retenue. Le donneur d’ordre prépare le contrat : vous serez prévenu(e) pour le relire et l’accepter.'),
            if (m['contract_id'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: TratraButton(label: 'Ouvrir le contrat', onPressed: () => goTo<void>(context, ContractScreen(id: m.i('contract_id'))))),
          ],
          if (const {'submitted', 'shortlisted', 'interview'}.contains(status))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AsyncAction(label: 'Retirer ma candidature', variant: TratraButtonVariant.outline, confirm: 'Le donneur d’ordre en est informé.', run: () async {
                await api.post('/applications/${m.i('id')}/withdraw/');
                await onChanged();
              }),
            ),
        ]),
      );
    }
    if (!posting.b('can_apply')) {
      return TratraAlert(
        tone: TratraAlertTone.info,
        title: 'Postuler',
        message: posting.s('status') != 'open' ? 'Ce besoin n’accepte plus de candidatures.' : 'Postuler demande un profil professionnel vérifié par Tratra (dossier KYC approuvé).',
      );
    }
    return TratraButton(label: 'Postuler', block: true, onPressed: () => _apply(context));
  }
}
