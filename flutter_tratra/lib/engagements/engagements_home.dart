// lib/engagements/engagements_home.dart
//
// « Engagements » : prestations récurrentes et missions de longue durée — à faire, contrats, besoins publiés, candidatures.
// Une intervention ponctuelle reste une réservation classique. Toutes les données viennent du serveur.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/contract_form.dart';
import 'package:flutter_tratra/engagements/contract_screen.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/engagements/offers_screen.dart';
import 'package:flutter_tratra/engagements/posting_form.dart';
import 'package:flutter_tratra/engagements/posting_screen.dart';
import 'package:flutter_tratra/engagements/replacements_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show ApiView, DashPage;

enum _Tab { contracts, postings, applications }

class EngagementsHomeScreen extends StatefulWidget {
  const EngagementsHomeScreen({super.key});
  @override
  State<EngagementsHomeScreen> createState() => _EngagementsHomeScreenState();
}

class _EngagementsHomeScreenState extends State<EngagementsHomeScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  _Tab _tab = _Tab.contracts;
  bool _ended = false;
  int _version = 0;

  Future<void> _go(Widget page) async {
    await goTo<void>(context, page);
    if (mounted) setState(() => _version++);
  }

  void _openTodo(Json t) {
    final (target, id) = todoTarget(t);
    switch (target) {
      case TodoTarget.contractPay:
        if (id != null) _go(ContractScreen(id: id, tab: ContractTab.pay));
      case TodoTarget.contractPlanning:
        if (id != null) _go(ContractScreen(id: id, tab: ContractTab.planning));
      case TodoTarget.posting:
        if (id != null) _go(PostingScreen(id: id));
      case TodoTarget.replacements:
        _go(const ReplacementsScreen());
      case TodoTarget.contract:
        if (id != null) _go(ContractScreen(id: id));
    }
  }

  @override
  Widget build(BuildContext context) => DashPage(
        title: 'Engagements',
        body: ApiView<Json>(
          key: ValueKey('eng-$_version'),
          errorTitle: 'Engagements indisponibles',
          load: () => _api.getMap('/me/overview/'),
          builder: (context, overview, reload) {
            final todo = overview.l('todo');
            final counts = overview.m('counts');
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
              children: [
                Text('Prestations récurrentes et missions de longue durée : candidatures, contrat accepté par les deux parties, planning, rémunération mensuelle et évaluations.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TratraButton(label: 'Offres', variant: TratraButtonVariant.outline, leading: const Icon(Icons.search_rounded, size: 18), onPressed: () => _go(const OffersScreen()))),
                  const SizedBox(width: 10),
                  Expanded(child: TratraButton(label: 'Publier un besoin', leading: const Icon(Icons.add_rounded, size: 18), onPressed: () => _go(const PostingFormScreen()))),
                ]),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _go(const ReplacementsScreen()), icon: const Icon(Icons.repeat_rounded, size: 18), label: const Text('Mes remplacements'))),
                const TratraAlert(tone: TratraAlertTone.brand, title: 'Une intervention ponctuelle ?', message: 'Elle reste une réservation classique (onglet Explorer). Cet espace est réservé à ce qui se répète ou dure dans le temps.'),
                if (todo.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TratraCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('À faire', style: TratraTheme.style(TtType.h2)),
                      const SizedBox(height: 2),
                      Text('Ce qui attend une réponse de votre part.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                      const SizedBox(height: 8),
                      for (final t in todo)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.s('label'), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                          subtitle: Text('${t.s('title')}${t.sn('at') != null ? ' · ${dateFr(t.s('at'))}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openTodo(t),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 14),
                Text('${counts.i('active')} en cours${counts.i('pending_acceptance') > 0 ? ' · ${counts.i('pending_acceptance')} à accepter' : ''}${counts.i('suspended') > 0 ? ' · ${counts.i('suspended')} suspendu(s)' : ''}${counts.i('notice') > 0 ? ' · ${counts.i('notice')} en préavis' : ''}',
                    style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (t, l) in const [(_Tab.contracts, 'Contrats'), (_Tab.postings, 'Mes besoins'), (_Tab.applications, 'Mes candidatures')])
                      Padding(padding: const EdgeInsets.only(right: 8), child: TratraChip(label: l, selected: _tab == t, onTap: () => setState(() => _tab = t))),
                  ]),
                ),
                const SizedBox(height: 14),
                switch (_tab) {
                  _Tab.contracts => _contracts(),
                  _Tab.postings => _postings(),
                  _Tab.applications => _applications(),
                },
              ],
            );
          },
        ),
      );

  Widget _contracts() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(padding: const EdgeInsets.only(right: 8), child: TratraChip(label: 'En cours', selected: !_ended, onTap: () => setState(() => _ended = false))),
            TratraChip(label: 'Terminés', selected: _ended, onTap: () => setState(() => _ended = true)),
          ]),
        ),
        const SizedBox(height: 12),
        EngLoader<EngPage>(
          reloadKey: '$_ended-$_version',
          load: () => _api.getPage('/contracts/?status=${_ended ? 'terminated,completed,cancelled' : 'pending_acceptance,accepted,active,suspended,notice,draft'}&limit=50'),
          builder: (ctx, page, _) => page.results.isEmpty
              ? TratraEmptyState(
                  icon: Icons.description_outlined,
                  title: _ended ? 'Aucun contrat terminé' : 'Aucun contrat en cours',
                  description: _ended ? 'Les contrats terminés restent consultables ici, avec leur historique.' : 'Publiez un besoin, ou répondez à une offre : le contrat se prépare ici, accepté par les deux parties.',
                  actions: _ended ? const [] : [TratraButton(label: 'Préparer un contrat', variant: TratraButtonVariant.outline, onPressed: () => _go(const ContractFormScreen()))],
                )
              : Column(children: [
                  for (final c in page.results)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TratraCard(
                        padding: TratraCard.compact,
                        onTap: () => _go(ContractScreen(id: c.i('id'))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(c.s('title'), style: TratraTheme.style(TtType.h3))), StatusChip(contractStatus(c.s('status')))]),
                          const SizedBox(height: 4),
                          Text('${c.s('my_role') == 'worker' ? 'Pour' : 'Avec'} ${c.m('counterpart').s('name')}${c['organization'] is Map ? ' · ${c.m('organization').s('name')}' : ''} · ${missionTypeFr[c.s('mission_type')] ?? ''}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                          const SizedBox(height: 2),
                          Text('${fcfa(c.s('amount'), c.s('currency', 'XOF'))} ${periodFr[c.s('period')] ?? ''} · ${durationLabel(c)} · dès le ${dateFr(c.sn('start_date'))}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]);

  Widget _postings() => EngLoader<EngPage>(
        reloadKey: _version,
        load: () => _api.getPage('/postings/mine/?limit=50'),
        builder: (ctx, page, _) => page.results.isEmpty
            ? TratraEmptyState(icon: Icons.work_outline_rounded, title: 'Aucun besoin publié', description: 'Décrivez ce dont vous avez besoin sur la durée : des prestataires vérifiés pourront postuler.',
                actions: [TratraButton(label: 'Publier un besoin', onPressed: () => _go(const PostingFormScreen()))])
            : Column(children: [
                for (final p in page.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TratraCard(
                      padding: TratraCard.compact,
                      onTap: () => _go(PostingScreen(id: p.i('id'))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(p.s('title'), style: TratraTheme.style(TtType.h3))), StatusChip(postingStatus(p.s('status')))]),
                        const SizedBox(height: 4),
                        Text('${p.m('category').s('name')} · ${p.s('city')} · ${missionTypeFr[p.s('mission_type')] ?? ''}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                        Text('${fcfa(p.sn('amount'), p.s('currency', 'XOF'))} ${periodFr[p.s('period')] ?? ''}${p.i('applications_count') > 0 ? ' · ${p.i('applications_count')} candidature(s)' : ''}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                      ]),
                    ),
                  ),
              ]),
      );

  Widget _applications() => EngLoader<EngPage>(
        reloadKey: _version,
        load: () => _api.getPage('/applications/mine/?limit=50'),
        builder: (ctx, page, _) => page.results.isEmpty
            ? TratraEmptyState(icon: Icons.search_rounded, title: 'Aucune candidature', description: 'Parcourez les offres de longue durée : postuler est possible dès que votre profil est vérifié.',
                actions: [TratraButton(label: 'Parcourir les offres', onPressed: () => _go(const OffersScreen()))])
            : Column(children: [
                for (final a in page.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TratraCard(
                      padding: TratraCard.compact,
                      onTap: () => _go(a['contract_id'] != null ? ContractScreen(id: a.i('contract_id')) : PostingScreen(id: a.i('posting'))),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.s('posting_title'), style: TratraTheme.style(TtType.h3)),
                            Text('Candidature du ${dateFr(a.sn('created_at'))}${a.l('interviews').any((i) => i.s('status') == 'proposed' || i.s('status') == 'confirmed') ? ' · entretien prévu' : ''}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                          ]),
                        ),
                        StatusChip(applicationStatus(a.s('status'))),
                      ]),
                    ),
                  ),
              ]),
      );
}
