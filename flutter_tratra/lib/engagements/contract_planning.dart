// lib/engagements/contract_planning.dart
//
// Planning d'un contrat : calendrier généré à partir des conditions, congés / absences / repos et heures supplémentaires
// validés par la CONTREPARTIE, remplacements acceptés puis validés, présences DÉCLARÉES par le prestataire et CONFIRMÉES par
// le donneur d'ordre. Aucun suivi de position : Tratra ne localise jamais le prestataire.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';

class ContractPlanning extends StatefulWidget {
  const ContractPlanning({super.key, required this.api, required this.c, required this.onChanged});
  final EngagementsApi api;
  final Json c;
  final Future<void> Function() onChanged;
  @override
  State<ContractPlanning> createState() => _ContractPlanningState();
}

class _ContractPlanningState extends State<ContractPlanning> {
  late DateTime _start = DateTime.now().subtract(const Duration(days: 7));
  int _version = 0;
  List<Json> _events = const [];

  DateTime get _end => _start.add(const Duration(days: 37));

  void _refresh() {
    setState(() => _version++);
    widget.onChanged();
  }

  bool get _canRequest => widget.c.strs('actions').contains('request_event');

  Future<void> _request(String kind) async {
    final base = randomHex();
    final isOvertime = kind == 'overtime';
    final other = widget.c.s('my_role') == 'worker' ? widget.c.m('principal').s('name') : widget.c.m('worker').s('name');
    final now = DateTime.now();
    final done = await showActionSheet(
      context,
      title: isOvertime ? 'Déclarer des heures supplémentaires' : 'Demander un congé, une absence ou un repos',
      description: '$other doit la valider. ${isOvertime ? (widget.c.sn('overtime_hourly_rate') != null ? 'Une fois validées, elles sont ajoutées à l’échéance au taux du contrat.' : 'Le contrat ne fixe aucun taux : elles sont enregistrées mais Tratra ne les valorise pas.') : 'Les interventions couvertes sont retirées du planning une fois la demande validée.'}',
      confirmLabel: 'Envoyer la demande',
      fields: [
        if (!isOvertime) const FieldSpec('kind', 'Nature', kind: FieldKind.select, options: [('leave', 'Congé'), ('absence', 'Absence'), ('rest', 'Repos')], initial: 'leave'),
        FieldSpec('date', isOvertime ? 'Jour' : 'Du', kind: FieldKind.date, required: true, firstDate: now.subtract(const Duration(days: 14))),
        if (isOvertime) const FieldSpec('hours', 'Nombre d’heures', kind: FieldKind.number, required: true, hint: '12 heures au maximum par demande.') else const FieldSpec('end_date', 'Au (inclus)', kind: FieldKind.date, optional: true),
        const FieldSpec('note', 'Motif', kind: FieldKind.multiline, optional: true, maxLength: 500),
      ],
      submit: (v) {
        final body = {'kind': isOvertime ? 'overtime' : v['kind'], 'date': v['date'], if (!isOvertime && (v['end_date'] ?? '').isNotEmpty) 'end_date': v['end_date'], if (isOvertime) 'hours': v['hours'], 'note': v['note']};
        return widget.api.post('/contracts/${widget.c.i('id')}/events/', body, intentKey('event', base, body));
      },
    );
    if (done) _refresh();
  }

  Future<void> _replace() async {
    final shifts = _events.where((e) => e.s('kind') == 'shift' && const {'planned', 'approved'}.contains(e.s('status')) && e.s('date').compareTo(isoDay(DateTime.now())) >= 0).toList();
    final done = await showTratraSheet<bool>(
      context,
      title: 'Proposer un remplaçant',
      description: 'Le remplaçant doit être un professionnel vérifié ; il accepte, puis le donneur d’ordre valide. Le remplaçant déclare lui-même sa présence.',
      child: _ReplacementForm(api: widget.api, contractId: widget.c.i('id'), shifts: shifts),
    );
    if (done == true) _refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TratraAlert(
            tone: TratraAlertTone.brand,
            title: 'Aucun suivi de position',
            message: 'Le planning vient des conditions du contrat. La présence est déclarée par le prestataire puis confirmée par le donneur d’ordre : Tratra ne localise jamais le prestataire.',
          ),
          const SizedBox(height: 14),
          Row(children: [
            IconButton(tooltip: 'Période précédente', onPressed: () => setState(() => _start = _start.subtract(const Duration(days: 30))), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(child: Text('${dateShortFr(isoDay(_start))} → ${dateShortFr(isoDay(_end))}', textAlign: TextAlign.center, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Période suivante', onPressed: () => setState(() => _start = _start.add(const Duration(days: 30))), icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          if (_canRequest)
            Wrap(spacing: 8, runSpacing: 8, children: [
              TratraButton(label: 'Congé, absence ou repos', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _request('leave')),
              TratraButton(label: 'Heures supplémentaires', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _request('overtime')),
              if (widget.c.strs('actions').contains('propose_replacement')) TratraButton(label: 'Proposer un remplaçant', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: _replace),
            ]),
          const SizedBox(height: 14),
          EngLoader<List<Json>>(
            reloadKey: '$_version-${isoDay(_start)}',
            load: () async {
              final d = await widget.api.getMap('/contracts/${widget.c.i('id')}/calendar/?start=${isoDay(_start)}&end=${isoDay(_end)}');
              final events = d.l('events');
              _events = events;
              return events;
            },
            builder: (ctx, events, _) {
              if (events.isEmpty) {
                return TratraEmptyState(compact: true, icon: Icons.event_busy_outlined, title: 'Rien de prévu sur cette période',
                    description: widget.c.l('schedule').isEmpty ? 'Ce contrat n’a pas de planning fixe : les demandes validées apparaissent ici.' : 'Le calendrier se génère au fil du temps (60 jours à l’avance).');
              }
              final byDay = <String, List<Json>>{};
              for (final e in events) {
                byDay.putIfAbsent(e.s('date'), () => []).add(e);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final d in byDay.entries) ...[
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(dateShortFr(d.key).toUpperCase(), style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6))),
                  for (final e in d.value) _EventTile(api: widget.api, c: widget.c, e: e, onDone: _refresh),
                ],
              ]);
            },
          ),
        ],
      );
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.api, required this.c, required this.e, required this.onDone});
  final EngagementsApi api;
  final Json c;
  final Json e;
  final VoidCallback onDone;

  Future<void> _attendance(BuildContext context) async {
    final base = randomHex();
    final done = await showActionSheet(
      context,
      title: 'Déclarer ma présence',
      description: 'Sans position GPS : vous indiquez seulement vos heures. Le donneur d’ordre confirme ensuite. Laissez vide pour déclarer les heures prévues.',
      confirmLabel: 'Déclarer',
      fields: const [FieldSpec('actual_start', 'Arrivée réelle', kind: FieldKind.time, optional: true), FieldSpec('actual_end', 'Départ réel', kind: FieldKind.time, optional: true)],
      submit: (v) {
        final body = <String, dynamic>{if ((v['actual_start'] ?? '').isNotEmpty || (v['actual_end'] ?? '').isNotEmpty) ...{'actual_start': v['actual_start'], 'actual_end': v['actual_end']}};
        return api.post('/events/${e.i('id')}/attendance/', body, intentKey('attend', base, {...body, 'e': e.i('id')}));
      },
    );
    if (done) onDone();
  }

  Future<void> _contest(BuildContext context) async {
    final done = await showActionSheet(
      context,
      title: 'Contester cette présence',
      confirmLabel: 'Contester',
      danger: true,
      fields: const [FieldSpec('note', 'Motif', kind: FieldKind.multiline, required: true)],
      submit: (v) => api.post('/events/${e.i('id')}/attendance/respond/', {'confirm': false, 'note': v['note']}),
    );
    if (done) onDone();
  }

  @override
  Widget build(BuildContext context) {
    final status = e.s('status');
    final hours = e.sn('start_time') != null ? '${timeFr(e.sn('start_time'))} – ${timeFr(e.sn('end_time'))}' : (e.sn('hours') != null ? '${num.tryParse(e.s('hours'))} h' : '');
    final att = e.s('attendance_status');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TtColors.surface, border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.control)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${eventKindFr[e.s('kind')] ?? e.s('kind')}${hours.isEmpty ? '' : ' · $hours'}${e.sn('end_date') != null ? ' · jusqu’au ${dateShortFr(e.sn('end_date'))}' : ''}${e.s('kind') == 'replacement' && e.m('replacement_worker').sn('name') != null ? ' · ${e.m('replacement_worker').s('name')}' : ''}',
              style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
          TratraBadge(eventStatusFr[status] ?? status, tone: status == 'approved' || status == 'planned' ? TratraTone.primary : (status == 'requested' ? TratraTone.accent : TratraTone.gray)),
          if (att != 'none') TratraBadge(attendanceFr[att] ?? att, tone: att == 'confirmed' ? TratraTone.success : (att == 'disputed' ? TratraTone.danger : TratraTone.info)),
          if (e['booking_id'] != null) TratraBadge('Réservation n° ${e.s('booking_id')}', tone: TratraTone.gray),
        ]),
        if (e.s('note').isNotEmpty) Text(e.s('note'), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (e.sn('actual_start') != null) Text('Heures déclarées : ${timeFr(e.sn('actual_start'))} – ${timeFr(e.sn('actual_end'))}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        if (e.b('can_respond') || e.b('can_cancel') || e.b('can_declare_attendance') || e.b('can_confirm_attendance'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              if (e.b('can_respond')) ...[
                AsyncAction(label: 'Valider', run: () async {
                  await api.post('/events/${e.i('id')}/respond/', {'approve': true});
                  onDone();
                }),
                AsyncAction(label: 'Refuser', variant: TratraButtonVariant.outline, run: () async {
                  await api.post('/events/${e.i('id')}/respond/', {'approve': false});
                  onDone();
                }),
              ],
              if (e.b('can_cancel'))
                AsyncAction(label: 'Annuler ma demande', variant: TratraButtonVariant.outline, run: () async {
                  await api.post('/events/${e.i('id')}/cancel/');
                  onDone();
                }),
              if (e.b('can_declare_attendance')) TratraButton(label: 'Déclarer ma présence', size: TratraButtonSize.sm, variant: TratraButtonVariant.soft, onPressed: () => _attendance(context)),
              if (e.b('can_confirm_attendance')) ...[
                AsyncAction(label: 'Confirmer la présence', run: () async {
                  await api.post('/events/${e.i('id')}/attendance/respond/', {'confirm': true});
                  onDone();
                }),
                TratraButton(label: 'Contester', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _contest(context)),
              ],
            ]),
          ),
      ]),
    );
  }
}

class _ReplacementForm extends StatefulWidget {
  const _ReplacementForm({required this.api, required this.contractId, required this.shifts});
  final EngagementsApi api;
  final int contractId;
  final List<Json> shifts;
  @override
  State<_ReplacementForm> createState() => _ReplacementFormState();
}

class _ReplacementFormState extends State<_ReplacementForm> {
  final _base = randomHex();
  int? _shift;
  PickedWorker? _worker;
  String _note = '';
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {'shift': _shift, 'replacement_worker': _worker?.id, 'note': _note.trim()};
    try {
      await widget.api.post('/contracts/${widget.contractId}/replacements/', body, intentKey('replace', _base, body));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = messageOf(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.shifts.isEmpty) const TratraAlert(tone: TratraAlertTone.info, message: 'Aucune intervention à venir dans la période affichée.')
        else DropdownButtonFormField<int>(
          initialValue: _shift,
          isExpanded: true,
          hint: const Text('Intervention à remplacer'),
          items: [for (final s in widget.shifts) DropdownMenuItem(value: s.i('id'), child: Text('${dateShortFr(s.sn('date'))} · ${timeFr(s.sn('start_time'))} – ${timeFr(s.sn('end_time'))}'))],
          onChanged: (v) => setState(() => _shift = v),
        ),
        const SizedBox(height: 14),
        WorkerPicker(api: widget.api, label: 'Remplaçant', picked: _worker, onPicked: (w) => setState(() => _worker = w)),
        const SizedBox(height: 14),
        TratraInput(label: 'Motif', optional: true, maxLines: 2, maxLength: 500, onChanged: (v) => _note = v),
        const SizedBox(height: 14),
        if (_error != null) ...[TratraAlert(tone: TratraAlertTone.danger, message: _error!), const SizedBox(height: 12)],
        TratraButton(label: 'Proposer le remplacement', block: true, loading: _busy, onPressed: _shift != null && _worker != null && !_busy ? _send : null),
      ]);
}
