// lib/engagements/offers_screen.dart
//
// Offres de longue durée ouvertes. Le serveur filtre ; « Postuler » n'est proposé qu'à un profil vérifié (sinon la raison
// est expliquée). Aucune offre fictive : une liste vide dit simplement qu'il n'y a rien.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/engagements/posting_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show DashPage;

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});
  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  String _q = '';
  String _type = '';
  Timer? _debounce;
  int _version = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String get _path {
    final qs = <String, String>{'limit': '30', if (_q.trim().isNotEmpty) 'q': _q.trim(), if (_type.isNotEmpty) 'mission_type': _type};
    return '/postings/?${qs.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  @override
  Widget build(BuildContext context) => DashPage(
        title: 'Offres de longue durée',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            Text('Missions régulières ou sur plusieurs mois. Chaque offre est publiée par un compte Tratra ; postuler exige un profil vérifié.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
            const SizedBox(height: 14),
            _Invitations(api: _api, onChanged: () => setState(() => _version++)),
            TratraInput(
              hint: 'Gardien, ménage, jardinier…',
              leadingIcon: Icons.search_rounded,
              onChanged: (v) {
                _q = v;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _version++));
              },
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (v, l) in const [('', 'Toutes'), ('recurring', 'Récurrentes'), ('long_term', 'Longue durée')])
                  Padding(padding: const EdgeInsets.only(right: 8), child: TratraChip(label: l, selected: _type == v, onTap: () => setState(() {
                        _type = v;
                        _version++;
                      }))),
              ]),
            ),
            const SizedBox(height: 14),
            EngLoader<EngPage>(
              reloadKey: _version,
              load: () => _api.getPage(_path),
              builder: (ctx, page, _) {
                if (page.results.isEmpty) {
                  return const TratraEmptyState(icon: Icons.search_off_rounded, title: 'Aucune offre ne correspond', description: 'Modifiez votre recherche, ou revenez plus tard : les offres sont publiées par des utilisateurs réels, aucune n’est affichée par défaut.');
                }
                final blocked = page.results.any((p) => !p.b('mine') && !p.b('applied') && p['can_apply'] == false);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (blocked) const Padding(padding: EdgeInsets.only(bottom: 12), child: TratraAlert(tone: TratraAlertTone.info, title: 'Postuler demande un profil vérifié', message: 'Complétez votre profil professionnel et votre vérification d’identité (Plus → Mon profil et KYC).')),
                  for (final p in page.results)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TratraCard(
                        padding: TratraCard.compact,
                        onTap: () => goTo<void>(context, PostingScreen(id: p.i('id'))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Text(p.s('title'), style: TratraTheme.style(TtType.h3))),
                            if (p.b('mine')) const TratraBadge('Mon offre', tone: TratraTone.gray) else if (p.b('applied')) const TratraBadge('Candidature envoyée', tone: TratraTone.info),
                          ]),
                          const SizedBox(height: 4),
                          Text('${p.m('category').s('name')} · ${p.s('city')} · ${missionTypeFr[p.s('mission_type')] ?? ''}${p.sn('start_date') != null ? ' · dès le ${dateFr(p.sn('start_date'))}' : ''}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                          const SizedBox(height: 6),
                          Text('${fcfa(p.sn('amount'), p.s('currency', 'XOF'))} ${periodFr[p.s('period')] ?? ''}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                          Text('${scheduleLabel(p.l('schedule'))} · publié par ${p['organization'] is Map ? p.m('organization').s('name') : p.m('publisher').s('name')}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                        ]),
                      ),
                    ),
                ]);
              },
            ),
          ],
        ),
      );
}


/// Invitations reçues : un donneur d'ordre vous invite à candidater. Accepter envoie votre candidature (mêmes contrôles qu'une
/// candidature spontanée : profil vérifié) ; décliner prévient l'auteur. Rien n'est affiché sans invitation réelle.
class _Invitations extends StatelessWidget {
  const _Invitations({required this.api, required this.onChanged});
  final EngagementsApi api;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => EngLoader<Json>(
        load: () => api.getMap('/invitations/mine/'),
        builder: (ctx, data, reload) {
          final open = data.l('results').where((i) => i.b('can_respond')).toList();
          if (open.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Invitations à candidater', style: TratraTheme.style(TtType.h2)),
            const SizedBox(height: 8),
            for (final i in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TratraCard(
                  variant: TratraCardVariant.accent,
                  padding: TratraCard.compact,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.m('posting').s('title'), style: TratraTheme.style(TtType.h3)),
                    const SizedBox(height: 4),
                    Text('${i.m('posting').s('category')} · ${i.m('posting').s('city')} · ${fcfa(i.m('posting').sn('amount'))} ${periodFr[i.m('posting').s('period')] ?? ''}',
                        style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                    if (i.s('message').isNotEmpty) ...[const SizedBox(height: 6), Text('« ${i.s('message')} » — ${i.m('invited_by').s('name')}', style: TratraTheme.style(TtType.bodySm))],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      TratraButton(label: 'Voir l’offre', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline,
                          onPressed: () => goTo<void>(context, PostingScreen(id: i.m('posting').i('id')))),
                      AsyncAction(label: 'Candidater', run: () async {
                        await api.post('/invitations/${i.i('id')}/respond/', {'accept': true});
                        await reload();
                        onChanged();
                      }),
                      AsyncAction(label: 'Décliner', variant: TratraButtonVariant.ghost, confirm: 'L’auteur de l’offre sera prévenu que vous déclinez.', run: () async {
                        await api.post('/invitations/${i.i('id')}/respond/', {'accept': false});
                        await reload();
                      }),
                    ]),
                  ]),
                ),
              ),
            const SizedBox(height: 6),
          ]);
        },
      );
}
