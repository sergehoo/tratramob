// lib/screens/business/business_screens.dart
//
// Tratra Business (mobile) : organisation, indicateurs, demandes d'intervention, validation, affectation, sites et
// équipements, signalement par QR. Mêmes endpoints et mêmes règles que le web : rôle, capacités et périmètre sont décidés
// par le serveur ; l'interface ne fait que présenter ce qu'il autorise.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/trust/scan_screen.dart';

String _s(dynamic v) => '${v ?? ''}';
List<Map<String, dynamic>> _l(dynamic v) => ((v as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
Map<String, dynamic> _m(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};

const priorityLabels = {'low': 'Basse', 'normal': 'Normale', 'high': 'Haute', 'urgent': 'Urgente'};
const requestStatus = <String, (String, TratraTone)>{
  'pending_approval': ('À valider', TratraTone.warning),
  'approved': ('Validée', TratraTone.info),
  'dispatched': ('Artisan sollicité', TratraTone.info),
  'scheduled': ('Planifiée', TratraTone.primary),
  'in_progress': ('En cours', TratraTone.primary),
  'completed': ('Terminée', TratraTone.success),
  'rejected': ('Refusée', TratraTone.danger),
  'cancelled': ('Annulée', TratraTone.gray),
};

String money(dynamic v, [String currency = 'XOF']) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null) return '—';
  final digits = n.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}$buf ${currency == 'XOF' ? 'FCFA' : currency}';
}

String shortDate(dynamic iso) {
  final d = DateTime.tryParse(_s(iso))?.toLocal();
  return d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class OrgCtx {
  const OrgCtx(this.data);
  final Map<String, dynamic> data;
  int get id => (data['id'] as num).toInt();
  String get name => _s(data['name']);
  String get currency => _s(data['currency']).isEmpty ? 'XOF' : _s(data['currency']);
  String get roleLabel => _s(data['role_label']);
  bool can(String cap) => ((data['capabilities'] as List?) ?? const []).contains(cap);
  String path(String sub) => '/business/orgs/$id/$sub';
}

// ============================================================================ accueil

class BusinessHomeScreen extends StatefulWidget {
  const BusinessHomeScreen({super.key});
  @override
  State<BusinessHomeScreen> createState() => _BusinessHomeScreenState();
}

class _BusinessHomeScreenState extends State<BusinessHomeScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;
  int? _orgId;
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.post('/business/orgs/', {'name': _name.text.trim()});
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'L’organisation n’a pas pu être créée.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.post('/business/join/', {'code': _code.text.trim()});
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'Code invalide ou expiré.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DashPage(
        title: 'Tratra Business',
        body: ApiView<List<Map<String, dynamic>>>(
          key: ValueKey('orgs-$_version'),
          errorTitle: 'Organisations indisponibles',
          load: () => _api.getList('/business/orgs/'),
          builder: (context, orgs, reload) {
            if (orgs.isEmpty) return _onboarding();
            final org = OrgCtx(orgs.firstWhere((o) => o['id'] == _orgId, orElse: () => orgs.first));
            return _Overview(api: _api, org: org, orgs: orgs, onSwitch: (id) => setState(() => _orgId = id));
          },
        ),
      );

  Widget _onboarding() => ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
        Text('Gérez la maintenance de vos sites', style: TratraTheme.style(TtType.h2)),
        const SizedBox(height: 4),
        Text('Sites, équipements, demandes validées, contrats, budgets et facturation — avec des artisans vérifiés.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        const SizedBox(height: TtSpace.s4),
        TratraCard(
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Créer mon organisation', style: TratraTheme.style(TtType.h3)),
            const SizedBox(height: TtSpace.s3),
            TratraInput(controller: _name, label: 'Nom de l’organisation', maxLength: 150),
            const SizedBox(height: TtSpace.s3),
            TratraButton(label: 'Créer l’organisation', block: true, loading: _busy, onPressed: () => _name.text.trim().isEmpty ? null : _create()),
          ]),
        ),
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Rejoindre avec un code', style: TratraTheme.style(TtType.h3)),
            Text('Votre administrateur vous a remis un code d’invitation à usage unique.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            const SizedBox(height: TtSpace.s3),
            TratraInput(controller: _code, label: 'Code d’invitation', hint: 'ABCD-EFGH-JKMN'),
            const SizedBox(height: TtSpace.s3),
            TratraButton(label: 'Rejoindre', variant: TratraButtonVariant.outline, block: true, loading: _busy, onPressed: () => _code.text.trim().isEmpty ? null : _join()),
          ]),
        ),
        if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
      ]);
}

class _Overview extends StatelessWidget {
  const _Overview({required this.api, required this.org, required this.orgs, required this.onSwitch});
  final DashboardApi api;
  final OrgCtx org;
  final List<Map<String, dynamic>> orgs;
  final ValueChanged<int> onSwitch;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final from = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final to = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return ListView(padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8), children: [
      if (orgs.length > 1)
        Wrap(spacing: TtSpace.s2, children: [for (final o in orgs) TratraChip(label: _s(o['name']), selected: o['id'] == org.id, onTap: () => onSwitch((o['id'] as num).toInt()))]),
      Text(org.name, style: TratraTheme.style(TtType.h2)),
      Padding(padding: const EdgeInsets.only(top: 4, bottom: TtSpace.s3), child: TratraBadge(org.roleLabel, tone: TratraTone.primary)),
      if (org.can('reports.view'))
        FutureBuilder<Map<String, dynamic>>(
          future: api.getMap('${org.path('dashboard/')}?from=$from&to=$to'),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(TtSpace.s6), child: Center(child: CircularProgressIndicator()));
            if (snap.hasError) return TratraAlert(tone: TratraAlertTone.danger, message: friendlyError(snap.error!, 'Indicateurs indisponibles.'));
            final d = snap.data!;
            final rq = _m(d['requests']);
            final sla = _m(_m(d['sla'])['resolution']);
            final spend = _m(d['spend']);
            String pct(dynamic r) => r is num ? '${(r * 100).round()} %' : '—';
            return Column(children: [
              Row(children: [
                Expanded(child: DashKpi(icon: Icons.pending_actions_rounded, label: 'Ouvertes', value: '${rq['open'] ?? 0}', hint: '${rq['created'] ?? 0} créées ce mois-ci')),
                const SizedBox(width: TtSpace.s2),
                Expanded(child: DashKpi(icon: Icons.alarm_rounded, label: 'En retard (SLA)', value: '${rq['overdue'] ?? 0}', tone: (rq['overdue'] ?? 0) > 0 ? TratraTone.accent : TratraTone.primary)),
              ]),
              const SizedBox(height: TtSpace.s2),
              Row(children: [
                Expanded(child: DashKpi(icon: Icons.verified_outlined, label: 'SLA résolution', value: pct(sla['rate']), hint: (sla['measured'] ?? 0) > 0 ? '${sla['met']} / ${sla['measured']} mesurées' : 'Pas encore mesuré')),
                const SizedBox(width: TtSpace.s2),
                Expanded(child: DashKpi(icon: Icons.payments_outlined, label: 'Dépenses', value: money(spend['total'], org.currency), hint: (spend['unpriced_interventions'] ?? 0) > 0 ? '${spend['unpriced_interventions']} sans montant' : null)),
              ]),
              if ((d['pending_my_approval'] ?? 0) > 0) ...[
                const SizedBox(height: TtSpace.s3),
                TratraAlert(tone: TratraAlertTone.warning, title: '${d['pending_my_approval']} demande(s) à valider', message: 'Ouvrez les demandes pour les valider ou les refuser.'),
              ],
              const SizedBox(height: TtSpace.s4),
            ]);
          },
        ),
      for (final a in [
        (Icons.assignment_outlined, 'Demandes d’intervention', 'Suivre, valider et affecter', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizRequestsScreen(org: org)))),
        if (org.can('requests.create')) (Icons.add_circle_outline_rounded, 'Nouvelle demande', 'Signaler un problème', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizNewRequestScreen(org: org)))),
        (Icons.qr_code_scanner_rounded, 'Scanner un équipement', 'Signaler un problème en deux touches', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen()))),
        (Icons.apartment_rounded, 'Sites et équipements', 'Structure de votre organisation', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizSitesScreen(org: org)))),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: TtSpace.s2),
          child: TratraCard(
            padding: TratraCard.compact,
            onTap: a.$4,
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)), child: Icon(a.$1, color: TtColors.primary)),
              const SizedBox(width: TtSpace.s3),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.$2, style: TratraTheme.style(TtType.title)), Text(a.$3, style: TratraTheme.style(TtType.caption, color: TtColors.ash))])),
              const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
            ]),
          ),
        ),
      const SizedBox(height: TtSpace.s3),
      Text('Budgets, facturation consolidée, contrats, membres et règles de validation se gèrent depuis le site web.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
    ]);
  }
}

// ============================================================================ demandes

class BizRequestsScreen extends StatefulWidget {
  const BizRequestsScreen({super.key, required this.org});
  final OrgCtx org;
  @override
  State<BizRequestsScreen> createState() => _BizRequestsScreenState();
}

class _BizRequestsScreenState extends State<BizRequestsScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  late String _scope = widget.org.can('requests.view_all') ? 'all' : 'mine';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final org = widget.org;
    final tabs = <(String, String)>[
      if (org.can('requests.view_all')) ('all', 'Toutes'),
      ('mine', 'Mes demandes'),
      if (org.can('requests.approve')) ('to_approve', 'À valider'),
    ];
    final qs = switch (_scope) { 'mine' => '&mine=1', 'to_approve' => '&to_approve=1', _ => '' };
    return DashPage(
      title: 'Demandes d’intervention',
      actions: [
        if (org.can('requests.create'))
          IconButton(
            tooltip: 'Nouvelle demande',
            icon: const Icon(Icons.add_rounded),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BizNewRequestScreen(org: org)));
              if (created == true && mounted) setState(() => _version++);
            },
          ),
      ],
      body: ApiView<List<Map<String, dynamic>>>(
        key: ValueKey('requests-$_scope-$_version'),
        errorTitle: 'Demandes indisponibles',
        load: () => _api.getList('${org.path('requests/')}?page_size=50$qs'),
        builder: (context, rows, reload) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            Wrap(spacing: TtSpace.s2, children: [for (final t in tabs) TratraChip(label: t.$2, selected: _scope == t.$1, onTap: () => setState(() => _scope = t.$1))]),
            const SizedBox(height: TtSpace.s3),
            if (rows.isEmpty)
              const SizedBox(height: 280, child: TratraEmptyState(icon: Icons.assignment_outlined, title: 'Aucune demande', description: 'Rien à afficher pour ce filtre.'))
            else
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: TtSpace.s2),
                  child: TratraCard(
                    padding: TratraCard.compact,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizRequestScreen(org: org, id: (r['id'] as num).toInt())));
                      if (mounted) setState(() => _version++);
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(_s(r['number']), style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
                        TratraBadge(requestStatus[r['status']]?.$1 ?? _s(r['status']), tone: requestStatus[r['status']]?.$2 ?? TratraTone.gray),
                      ]),
                      const SizedBox(height: 2),
                      Text(_s(r['title']), style: TratraTheme.style(TtType.title)),
                      Text('${_s(r['site_name'])}${r['equipment_name'] != null ? ' · ${r['equipment_name']}' : ''} · ${priorityLabels[r['priority']] ?? ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                      if (r['can_decide'] == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text('À valider par vous', style: TratraTheme.style(TtType.caption, color: TtColors.warningInk).copyWith(fontWeight: FontWeight.w700))),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class BizRequestScreen extends StatefulWidget {
  const BizRequestScreen({super.key, required this.org, required this.id});
  final OrgCtx org;
  final int id;
  @override
  State<BizRequestScreen> createState() => _BizRequestScreenState();
}

class _BizRequestScreenState extends State<BizRequestScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _comment = TextEditingController();
  int _version = 0;
  String? _busy;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _act(String key, String sub, [Map<String, dynamic>? body]) async {
    setState(() {
      _busy = key;
      _error = null;
    });
    try {
      await _api.post('${widget.org.path('requests/${widget.id}/')}$sub', body ?? const {});
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'L’action a échoué.'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.org;
    return DashPage(
      title: 'Demande',
      body: ApiView<Map<String, dynamic>>(
        key: ValueKey('request-$_version'),
        errorTitle: 'Demande indisponible',
        load: () => _api.getMap(org.path('requests/${widget.id}/')),
        builder: (context, r, reload) {
          final steps = _l(r['steps']);
          final status = requestStatus[r['status']];
          final cancellable = const {'pending_approval', 'approved', 'dispatched', 'scheduled'}.contains(r['status']);
          final sla = _m(r['sla']);
          return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8), children: [
            Row(children: [
              Expanded(child: Text(_s(r['number']), style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
              TratraBadge(status?.$1 ?? _s(r['status']), tone: status?.$2 ?? TratraTone.gray),
            ]),
            Text(_s(r['title']), style: TratraTheme.style(TtType.h2)),
            const SizedBox(height: TtSpace.s3),
            TratraCard(
              padding: TratraCard.compact,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Row('Site', _s(r['site_name'])),
                _Row('Équipement', _s(r['equipment_name']).isEmpty ? '—' : _s(r['equipment_name'])),
                _Row('Priorité', priorityLabels[r['priority']] ?? '—'),
                _Row('Demandeur', _s(r['requested_by_name'])),
                _Row('Coût estimé', money(r['estimated_cost'], org.currency)),
                _Row('Coût réel', money(r['cost'], org.currency)),
                _Row('Échéance de prise en charge', '${shortDate(sla['due_response_at'])}${sla['response_met'] == false ? ' · dépassée' : sla['response_met'] == true ? ' · tenue' : ''}'),
                _Row('Échéance de résolution', '${shortDate(sla['due_resolution_at'])}${sla['resolution_met'] == false ? ' · dépassée' : sla['resolution_met'] == true ? ' · tenue' : ''}'),
                if (_s(r['description']).isNotEmpty) ...[const SizedBox(height: 8), Text(_s(r['description']), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))],
              ]),
            ),
            if (_s(r['rejection_reason']).isNotEmpty) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, title: 'Motif du refus', message: _s(r['rejection_reason']))],
            for (final w in _l(r['budget_warnings'])) ...[
              const SizedBox(height: TtSpace.s3),
              TratraAlert(tone: TratraAlertTone.warning, title: 'Budget dépassé si réalisée', message: '${_s(w['name'])} : ${money(w['projected'], org.currency)} prévus pour ${money(w['amount'], org.currency)}.'),
            ],
            const SizedBox(height: TtSpace.s3),
            TratraCard(
              padding: TratraCard.compact,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Validation', style: TratraTheme.style(TtType.h3)),
                Text(steps.isEmpty ? 'Aucune validation requise : validée d’office.' : 'Chaque étape se valide dans l’ordre.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                const SizedBox(height: TtSpace.s3),
                for (final s in steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TtSpace.s2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(s['status'] == 'approved' ? Icons.check_circle_rounded : s['status'] == 'rejected' ? Icons.cancel_rounded : Icons.schedule_rounded, size: 20, color: s['status'] == 'approved' ? TtColors.success : s['status'] == 'rejected' ? TtColors.danger : TtColors.fog),
                      const SizedBox(width: TtSpace.s2),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_s(s['role_label']), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                        Text(s['status'] == 'pending' ? 'En attente' : '${s['status'] == 'approved' ? 'Validé' : 'Refusé'} par ${_s(s['decided_by_name'])} le ${shortDate(s['decided_at'])}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                        if (_s(s['comment']).isNotEmpty) Text(_s(s['comment']), style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
                      ])),
                    ]),
                  ),
                if (r['can_decide'] == true) ...[
                  const Divider(),
                  TratraInput(controller: _comment, label: 'Commentaire', optional: true, maxLines: 2, minLines: 2),
                  const SizedBox(height: TtSpace.s3),
                  Row(children: [
                    Expanded(child: TratraButton(label: 'Valider', loading: _busy == 'approve', onPressed: () => _act('approve', 'decide/', {'approve': true, 'comment': _comment.text.trim()}))),
                    const SizedBox(width: TtSpace.s2),
                    Expanded(child: TratraButton(label: 'Refuser', variant: TratraButtonVariant.outline, loading: _busy == 'reject', onPressed: () => _act('reject', 'decide/', {'approve': false, 'comment': _comment.text.trim()}))),
                  ]),
                ],
              ]),
            ),
            if (org.can('requests.dispatch') && r['status'] == 'approved') ...[const SizedBox(height: TtSpace.s3), _Dispatch(api: _api, org: org, id: widget.id, busy: _busy, onAct: _act)],
            if (r['booking_id'] != null) Padding(padding: const EdgeInsets.only(top: TtSpace.s3), child: Text('Mission confiée à un artisan (réservation n° ${r['booking_id']}) : son avancement met à jour cette demande.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
            if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
            if (cancellable) ...[
              const SizedBox(height: TtSpace.s4),
              TratraButton(
                label: 'Annuler la demande',
                variant: TratraButtonVariant.outline,
                block: true,
                loading: _busy == 'cancel',
                onPressed: () async {
                  final ok = await showTratraConfirm(context, title: 'Annuler cette demande ?', message: 'Si un artisan a déjà été sollicité, sa réservation sera annulée.', confirmLabel: 'Oui, annuler', danger: true);
                  if (ok) await _act('cancel', 'cancel/');
                },
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Text(label, style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
          Expanded(flex: 5, child: Text(value, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600))),
        ]),
      );
}

/// Affectation : artisans vérifiés classés (contrat, proximité, confiance, note, disponibilité) avec leurs raisons.
class _Dispatch extends StatelessWidget {
  const _Dispatch({required this.api, required this.org, required this.id, required this.busy, required this.onAct});
  final DashboardApi api;
  final OrgCtx org;
  final int id;
  final String? busy;
  final Future<void> Function(String key, String sub, [Map<String, dynamic>? body]) onAct;

  @override
  Widget build(BuildContext context) => TratraCard(
        padding: TratraCard.compact,
        child: FutureBuilder<Map<String, dynamic>>(
          future: api.getMap(org.path('requests/$id/suggestions/')),
          builder: (context, snap) {
            final list = _l(snap.data?['results']);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Choisir l’artisan', style: TratraTheme.style(TtType.h3)),
              Text('Artisans vérifiés uniquement, classés selon le contrat, la proximité, la confiance et la disponibilité.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              const SizedBox(height: TtSpace.s3),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (snap.hasError)
                TratraAlert(tone: TratraAlertTone.danger, message: friendlyError(snap.error!, 'Suggestions indisponibles.'))
              else if (list.isEmpty)
                const TratraAlert(tone: TratraAlertTone.info, message: 'Aucun artisan éligible n’est disponible pour cette demande pour le moment.')
              else ...[
                TratraButton(label: 'Affectation automatique', variant: TratraButtonVariant.soft, block: true, loading: busy == 'auto', onPressed: () => onAct('auto', 'dispatch/', {'auto': true})),
                const SizedBox(height: TtSpace.s2),
                for (var i = 0; i < list.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: TtSpace.s2),
                    padding: const EdgeInsets.all(TtSpace.s3),
                    decoration: BoxDecoration(border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.panel)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(_s(list[i]['display_name']), style: TratraTheme.style(TtType.title))),
                        if (i == 0) const TratraBadge('Recommandé', tone: TratraTone.accent),
                      ]),
                      const SizedBox(height: 4),
                      TratraTrustBadges(trustBadgeCodes(list[i]['badges'])),
                      const SizedBox(height: 4),
                      Text(((list[i]['reasons'] as List?) ?? const []).join(' · '), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                      const SizedBox(height: TtSpace.s2),
                      TratraButton(label: 'Confier la mission', size: TratraButtonSize.sm, loading: busy == 'd${list[i]['user_id']}', onPressed: () => onAct('d${list[i]['user_id']}', 'dispatch/', {'artisan': list[i]['user_id']})),
                    ]),
                  ),
              ],
            ]);
          },
        ),
      );
}

// ============================================================================ nouvelle demande

class BizNewRequestScreen extends StatefulWidget {
  const BizNewRequestScreen({super.key, required this.org, this.siteId, this.equipmentId, this.categoryId, this.fromQr = false});
  final OrgCtx org;
  final int? siteId;
  final int? equipmentId;
  final int? categoryId;
  final bool fromQr;
  @override
  State<BizNewRequestScreen> createState() => _BizNewRequestScreenState();
}

class _BizNewRequestScreenState extends State<BizNewRequestScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _cost = TextEditingController();
  late int? _site = widget.siteId;
  late int? _equipment = widget.equipmentId;
  String _priority = 'normal';
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _sites = const [];
  List<Map<String, dynamic>> _equip = const [];

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final s = await _api.getList(widget.org.path('sites/'));
        final e = await _api.getList(widget.org.path('equipment/'));
        if (mounted) setState(() { _sites = s; _equip = e; _site ??= s.length == 1 ? (s.first['id'] as num).toInt() : null; });
      } catch (e) {
        if (mounted) setState(() => _error = friendlyError(e, 'Sites indisponibles.'));
      }
    }();
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_site == null || _title.text.trim().isEmpty) return setState(() => _error = 'Choisissez le site et décrivez le problème.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.post(widget.org.path('requests/'), {
        'site': _site,
        'title': _title.text.trim(),
        'description': _details.text.trim(),
        'priority': _priority,
        if (_equipment != null) 'equipment': _equipment,
        if (widget.categoryId != null) 'category': widget.categoryId,
        if (_cost.text.trim().isNotEmpty) 'estimated_cost': _cost.text.trim(),
        if (widget.fromQr) 'from_qr': true,
      });
      if (!mounted) return;
      await showTratraSheet<void>(context, title: 'Demande ${r['number']} envoyée', description: r['status'] == 'pending_approval' ? 'Elle est en attente de validation.' : 'Elle est validée et sera confiée à un artisan.', child: TratraButton(label: 'OK', block: true, onPressed: () => Navigator.of(context).pop()));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'La demande n’a pas pu être créée.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged, {bool enabled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: TtSpace.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            initialValue: value,
            items: items,
            isExpanded: true,
            onChanged: enabled ? onChanged : null,
            decoration: InputDecoration(filled: true, fillColor: TtColors.surface, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(TtRadius.control), borderSide: const BorderSide(color: TtColors.line))),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final siteEquip = _equip.where((e) => _site == null || e['site'] == _site).toList();
    return DashPage(
      title: 'Nouvelle demande',
      body: ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
        _dropdown<int>('Site', _site, [for (final s in _sites) DropdownMenuItem(value: (s['id'] as num).toInt(), child: Text(_s(s['name'])))], (v) => setState(() { _site = v; _equipment = null; }), enabled: widget.siteId == null),
        _dropdown<int?>('Équipement concerné', _equipment, [const DropdownMenuItem<int?>(value: null, child: Text('Aucun / autre')), for (final e in siteEquip) DropdownMenuItem<int?>(value: (e['id'] as num).toInt(), child: Text(_s(e['name'])))], (v) => setState(() => _equipment = v), enabled: widget.equipmentId == null),
        TratraInput(controller: _title, label: 'Problème à traiter', hint: 'Ex. Fuite sous l’évier du bureau 12', maxLength: 200),
        const SizedBox(height: TtSpace.s3),
        TratraInput(controller: _details, label: 'Détails', optional: true, maxLines: 3, minLines: 3),
        const SizedBox(height: TtSpace.s3),
        _dropdown<String>('Priorité', _priority, [for (final p in priorityLabels.entries) DropdownMenuItem(value: p.key, child: Text(p.value))], (v) => setState(() => _priority = v ?? 'normal')),
        TratraInput(controller: _cost, label: 'Coût estimé (${widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency})', optional: true, keyboardType: TextInputType.number, helper: 'Détermine la validation nécessaire.'),
        if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
        const SizedBox(height: TtSpace.s4),
        TratraButton(label: 'Envoyer la demande', block: true, size: TratraButtonSize.lg, loading: _busy, onPressed: _submit),
      ]),
    );
  }
}

// ============================================================================ sites et équipements

class BizSitesScreen extends StatefulWidget {
  const BizSitesScreen({super.key, required this.org});
  final OrgCtx org;
  @override
  State<BizSitesScreen> createState() => _BizSitesScreenState();
}

class _BizSitesScreenState extends State<BizSitesScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();

  @override
  Widget build(BuildContext context) => DashPage(
        title: 'Sites et équipements',
        body: ApiView<List<List<Map<String, dynamic>>>>(
          errorTitle: 'Sites indisponibles',
          load: () async => [await _api.getList(widget.org.path('sites/')), await _api.getList(widget.org.path('equipment/'))],
          builder: (context, data, reload) {
            final sites = data[0], equipment = data[1];
            if (sites.isEmpty) return const TratraEmptyState(icon: Icons.apartment_rounded, title: 'Aucun site', description: 'Ajoutez vos sites depuis le site web.');
            return ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
              for (final s in sites) ...[
                TratraCard(
                  padding: TratraCard.compact,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_s(s['name']), style: TratraTheme.style(TtType.h3)),
                    Text([_s(s['address']), _s(s['city'])].where((e) => e.isNotEmpty).join(', '), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    const SizedBox(height: TtSpace.s2),
                    for (final e in equipment.where((e) => e['site'] == s['id']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(_s(e['name'])),
                        subtitle: Text([_s(e['building_name']), _s(e['location_detail'])].where((x) => x.isNotEmpty && x != 'null').join(' · ')),
                        trailing: widget.org.can('requests.create') ? const Icon(Icons.report_problem_outlined, size: 20) : null,
                        onTap: widget.org.can('requests.create')
                            ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizNewRequestScreen(org: widget.org, siteId: (s['id'] as num).toInt(), equipmentId: (e['id'] as num).toInt(), categoryId: (e['category'] as num?)?.toInt(), fromQr: false)))
                            : null,
                      ),
                  ]),
                ),
                const SizedBox(height: TtSpace.s3),
              ],
            ]);
          },
        ),
      );
}

// ============================================================================ scan d'équipement

/// Ouvert depuis le scanner : le QR d'équipement n'est lisible que par les membres de son organisation (sinon 404).
class EquipmentReportScreen extends StatelessWidget {
  const EquipmentReportScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final api = context.read<DashboardApi>();
    return DashPage(
      title: 'Équipement',
      body: FutureBuilder<Map<String, dynamic>>(
        future: api.getMap('/business/equipment/lookup/${Uri.encodeComponent(code)}/'),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return const TratraEmptyState(icon: Icons.build_outlined, title: 'Équipement introuvable', description: 'Ce QR n’existe pas, ou l’équipement n’appartient pas à une organisation dont vous êtes membre.');
          }
          final e = snap.data!;
          final org = OrgCtx({'id': e['organization'], 'name': e['organization_name'], 'currency': 'XOF', 'capabilities': e['can_request'] == true ? ['requests.create'] : []});
          return ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
            TratraCard(
              padding: TratraCard.compact,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_s(e['organization_name']).toUpperCase(), style: TratraTheme.style(TtType.eyebrow, color: TtColors.ash)),
                Text(_s(e['name']), style: TratraTheme.style(TtType.h2)),
                Text('${_s(e['site_name'])}${_s(e['location_detail']).isEmpty ? '' : ' · ${e['location_detail']}'}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                const SizedBox(height: TtSpace.s2),
                TratraBadge((e['open_requests'] ?? 0) > 0 ? '${e['open_requests']} demande(s) ouverte(s)' : 'Aucune demande ouverte', tone: (e['open_requests'] ?? 0) > 0 ? TratraTone.warning : TratraTone.success),
              ]),
            ),
            const SizedBox(height: TtSpace.s3),
            if (e['can_request'] == true)
              TratraButton(
                label: 'Signaler un problème',
                size: TratraButtonSize.lg,
                block: true,
                leading: const Icon(Icons.report_problem_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizNewRequestScreen(org: org, siteId: (e['site'] as num).toInt(), equipmentId: (e['id'] as num).toInt(), categoryId: (e['category'] as num?)?.toInt(), fromQr: true))),
              )
            else
              const TratraAlert(tone: TratraAlertTone.info, message: 'Votre rôle ne permet pas de créer une demande sur cet équipement.'),
          ]);
        },
      ),
    );
  }
}
