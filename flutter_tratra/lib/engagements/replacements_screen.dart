// lib/engagements/replacements_screen.dart
//
// Espace du remplaçant : voit ses propres remplacements uniquement — jamais le contrat ni la rémunération.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show ApiView, DashPage;

class ReplacementsScreen extends StatefulWidget {
  const ReplacementsScreen({super.key});
  @override
  State<ReplacementsScreen> createState() => _ReplacementsScreenState();
}

class _ReplacementsScreenState extends State<ReplacementsScreen> {
  late final EngagementsApi _api = context.read<EngagementsApi>();
  @override
  Widget build(BuildContext context) => DashPage(
        title: 'Mes remplacements',
        body: ApiView<EngPage>(
          errorTitle: 'Remplacements indisponibles',
          load: () => _api.getPage('/me/replacements/?limit=50'),
          builder: (context, page, reload) {
            if (page.results.isEmpty) {
              return ListView(children: const [
                TratraEmptyState(icon: Icons.repeat_rounded, title: 'Aucun remplacement', description: 'Quand un prestataire vous propose de le remplacer, la demande apparaît ici et vous êtes notifié(e).'),
              ]);
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
              children: [
                for (final e in page.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TratraCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Text(e.s('contract_title'), style: TratraTheme.style(TtType.h3))),
                          TratraBadge(e.s('replacement_status') == 'accepted' ? 'Accepté' : (e.s('replacement_status') == 'proposed' ? 'Proposé' : 'Refusé'),
                              tone: e.s('replacement_status') == 'accepted' ? TratraTone.success : (e.s('replacement_status') == 'proposed' ? TratraTone.accent : TratraTone.gray)),
                        ]),
                        Text('${e.s('category')} · ${e.s('city')} · ${e.m('principal').s('name')}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                        const SizedBox(height: 4),
                        Text('${dateShortFr(e.sn('date'))} · ${timeFr(e.sn('start_time'))} – ${timeFr(e.sn('end_time'))}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          if (e.b('can_answer_replacement')) ...[
                            AsyncAction(label: 'Accepter ce remplacement', run: () async {
                              await _api.post('/events/${e.i('id')}/replacement/respond/', {'accept': true});
                              await reload();
                            }),
                            AsyncAction(label: 'Refuser', variant: TratraButtonVariant.outline, run: () async {
                              await _api.post('/events/${e.i('id')}/replacement/respond/', {'accept': false});
                              await reload();
                            }),
                          ],
                          if (e.b('can_declare_attendance'))
                            AsyncAction(label: 'Déclarer ma présence', variant: TratraButtonVariant.soft, run: () async {
                              await _api.post('/events/${e.i('id')}/attendance/', const <String, dynamic>{}, intentKey('attend', 'rep${e.i('id')}', e.i('id')));
                              await reload();
                            }),
                        ]),
                        if (e.b('can_answer_replacement'))
                          Padding(padding: const EdgeInsets.only(top: 8), child: Text('Après votre acceptation, le donneur d’ordre doit encore valider le remplacement. Votre présence sera déclarée par vous, sans position GPS.', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
