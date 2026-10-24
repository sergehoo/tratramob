// lib/engagements/terms_form.dart
//
// Conditions d'un besoin ou d'un contrat : un seul formulaire, deux modes (le serveur revalide toutes les règles — durée
// maximale, préavis, emploi salarié…). Tratra ne calcule aucun élément légal ; l'emploi salarié n'est proposé que si la règle
// du métier l'ouvre, avec un avertissement explicite.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_ui.dart';
import 'package:flutter_tratra/engagements/labels.dart';

class TermsValue {
  TermsValue();

  String category = '', title = '', description = '', conditions = '', missionType = 'long_term', relationship = 'independent';
  String city = '', address = '', startDate = '', endDate = '', deadline = '', amount = '', period = 'monthly', paymentDay = '5';
  String renewalMonths = '12', proration = 'none', overtimeRate = '', notice = '7', bookingsMode = 'none', organization = '';
  String benefits = '', durationMonths = '';
  bool ack = false, autoRenew = false;
  List<Json> schedule = [];

  static String _num(Object? v) {
    final n = num.tryParse('${v ?? ''}');
    return n == null ? '' : (n == n.roundToDouble() ? '${n.round()}' : '$n');
  }

  factory TermsValue.fromPosting(Json p) => TermsValue()
    ..category = p.m('category').s('id')
    ..title = p.s('title')
    ..description = p.s('description')
    ..conditions = p.s('conditions')
    ..benefits = p.s('benefits')
    ..durationMonths = p.s('duration_months')
    ..missionType = p.s('mission_type', 'long_term')
    ..relationship = p.s('work_relationship', 'independent')
    ..ack = p.b('employment_notice_ack')
    ..city = p.s('city')
    ..address = p.s('location_note')
    ..startDate = p.s('start_date')
    ..endDate = p.s('end_date')
    ..deadline = p.s('application_deadline')
    ..schedule = p.l('schedule')
    ..amount = _num(p['amount'])
    ..period = p.s('period', 'monthly')
    ..organization = p['organization'] is Map ? p.m('organization').s('id') : '';

  factory TermsValue.fromContract(Json c) => TermsValue()
    ..category = c.m('category').s('id')
    ..title = c.s('title')
    ..description = c.s('description')
    ..conditions = c.s('conditions')
    ..benefits = c.s('benefits')
    ..missionType = c.s('mission_type', 'long_term')
    ..relationship = c.s('work_relationship', 'independent')
    ..ack = c.b('legal_notice_ack')
    ..city = c.s('location_city')
    ..address = c.s('location_address')
    ..startDate = c.s('start_date')
    ..endDate = c.s('end_date')
    ..schedule = c.l('schedule')
    ..amount = _num(c['amount'])
    ..period = c.s('period', 'monthly')
    ..paymentDay = c.s('payment_day', '5')
    ..autoRenew = c.b('auto_renew')
    ..renewalMonths = c.s('renewal_term_months', '12')
    ..proration = c.s('proration_mode', 'none')
    ..overtimeRate = _num(c['overtime_hourly_rate'])
    ..notice = c.s('notice_period_days', '7')
    ..bookingsMode = c.s('bookings_mode', 'none');

  /// Corps d'un besoin publié.
  Map<String, dynamic> toPosting() => {
        'category': int.tryParse(category),
        'title': title.trim(),
        'description': description.trim(),
        'conditions': conditions.trim(),
        'mission_type': missionType,
        'work_relationship': relationship,
        'employment_notice_ack': relationship == 'employment' && ack,
        'city': city.trim(),
        'location_note': address.trim(),
        'start_date': startDate.isEmpty ? null : startDate,
        'end_date': endDate.isEmpty ? null : endDate,
        'application_deadline': deadline.isEmpty ? null : deadline,
        'benefits': benefits.trim(),
        'duration_months': int.tryParse(durationMonths.trim()),
        'schedule': schedule,
        'amount': amount.trim(),
        'period': period,
        if (organization.isNotEmpty) 'organization': int.tryParse(organization),
      };

  /// Corps d'un contrat (brouillon).
  Map<String, dynamic> toContract() => {
        'category_id': int.tryParse(category),
        'title': title.trim(),
        'description': description.trim(),
        'conditions': conditions.trim(),
        'mission_type': missionType,
        'work_relationship': relationship,
        'legal_notice_ack': relationship == 'employment' && ack,
        'benefits': benefits.trim(),
        'location_city': city.trim(),
        'location_address': address.trim(),
        'start_date': startDate,
        'end_date': endDate.isEmpty ? null : endDate,
        'auto_renew': autoRenew && endDate.isNotEmpty,
        'renewal_term_months': autoRenew && endDate.isNotEmpty ? int.tryParse(renewalMonths) : null,
        'schedule': schedule,
        'amount': amount.trim(),
        'period': period,
        'payment_day': int.tryParse(paymentDay),
        'proration_mode': proration,
        'overtime_hourly_rate': overtimeRate.trim().isEmpty ? null : overtimeRate.trim(),
        'notice_period_days': int.tryParse(notice),
        'bookings_mode': bookingsMode,
      };
}

class TermsFields extends StatefulWidget {
  const TermsFields({super.key, required this.contractMode, required this.value, required this.onChanged, required this.errors, required this.categories, required this.rules, this.organizations = const [], this.enabled = true});
  final bool contractMode;
  final TermsValue value;
  final VoidCallback onChanged;
  final Map<String, String> errors;
  final List<Json> categories;
  final Json? Function(String categoryId) rules;
  final List<Json> organizations;
  final bool enabled;
  @override
  State<TermsFields> createState() => _TermsFieldsState();
}

class _TermsFieldsState extends State<TermsFields> {
  late final Map<String, TextEditingController> _dates = {
    'start': TextEditingController(text: widget.value.startDate.isEmpty ? '' : dateFr(widget.value.startDate)),
    'end': TextEditingController(text: widget.value.endDate.isEmpty ? '' : dateFr(widget.value.endDate)),
    'deadline': TextEditingController(text: widget.value.deadline.isEmpty ? '' : dateFr(widget.value.deadline)),
  };

  @override
  void dispose() {
    for (final c in _dates.values) {
      c.dispose();
    }
    super.dispose();
  }

  TermsValue get v => widget.value;
  String? _e(String k) => widget.errors[k];
  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  Future<void> _pick(String which) async {
    final now = DateTime.now();
    final current = parseDay(switch (which) { 'start' => v.startDate, 'end' => v.endDate, _ => v.deadline }) ?? now;
    final picked = await showDatePicker(context: context, initialDate: current.isBefore(now) ? now : current, firstDate: now, lastDate: DateTime(now.year + 12), locale: const Locale('fr'));
    if (picked == null) return;
    _set(() {
      final iso = isoDay(picked);
      switch (which) {
        case 'start':
          v.startDate = iso;
        case 'end':
          v.endDate = iso;
        default:
          v.deadline = iso;
      }
      _dates[which]!.text = dateFr(iso);
    });
  }

  Widget _select(String label, String value, List<(String, String)> options, ValueChanged<String> onChanged, {String? error, String? helper}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: options.any((o) => o.$1 == value) ? value : null,
          isExpanded: true,
          items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
          onChanged: widget.enabled ? (x) => onChanged(x ?? '') : null,
          decoration: InputDecoration(errorText: error, helperText: helper, helperMaxLines: 3),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final r = widget.rules(v.category);
    final employmentOk = r?.b('allow_employment') ?? false;
    final isContract = widget.contractMode;
    final maxMonths = r?.sn('max_duration_months');
    final minNotice = r == null ? null : (v.relationship == 'employment' ? r.sn('min_notice_days_employment') : r.sn('min_notice_days_independent'));
    const gap = SizedBox(height: 16);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!isContract && widget.organizations.isNotEmpty) ...[
        _select('Publier au nom de', v.organization, [('', 'Moi-même'), for (final o in widget.organizations) ('${o.i('id')}', o.s('name'))], (x) => _set(() => v.organization = x), helper: 'Votre organisation Tratra Business, si vous y êtes habilité.'),
        gap,
      ],
      TratraInput(label: 'Intitulé', required: true, enabled: widget.enabled, initialValue: v.title, maxLength: 160, errorText: _e('title'), hint: 'Ex. Gardien de nuit — résidence', onChanged: (x) => v.title = x),
      gap,
      _select('Métier *', v.category, [for (final c in widget.categories) ('${c.i('id')}', c.s('name'))], (x) => _set(() => v.category = x), error: _e('category') ?? _e('category_id')),
      gap,
      _select('Type de mission', v.missionType, [for (final e in missionTypeFr.entries) (e.key, e.value)], (x) => _set(() => v.missionType = x), error: _e('mission_type'), helper: 'Une intervention unique se réserve depuis « Explorer ».'),
      gap,
      _select('Nature de la relation', v.relationship, [('independent', relationshipFr['independent']!), if (employmentOk || v.relationship == 'employment') ('employment', '${relationshipFr['employment']}${employmentOk ? '' : ' (non ouvert pour ce métier)'}')],
          (x) => _set(() => v.relationship = x), error: _e('work_relationship')),
      if (v.relationship == 'employment') ...[
        gap,
        TratraAlert(
          tone: TratraAlertTone.warning,
          title: 'Emploi salarié',
          message: 'Un emploi salarié relève du droit du travail applicable. Tratra met en relation et garde la trace de vos accords, mais n’est pas un conseil juridique et ne calcule ni cotisations, ni impôts, ni congés payés : vous restez responsables de vos obligations légales.',
          action: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: v.ack,
            onChanged: widget.enabled ? (x) => _set(() => v.ack = x == true) : null,
            title: Text('J’ai compris que Tratra ne gère pas le volet légal de l’emploi salarié.', style: TratraTheme.style(TtType.bodySm)),
            subtitle: (_e('employment_notice_ack') ?? _e('legal_notice_ack')) == null ? null : Text(_e('employment_notice_ack') ?? _e('legal_notice_ack')!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
          ),
        ),
      ],
      gap,
      TratraInput(label: isContract ? 'Missions confiées' : 'Description du besoin', required: !isContract, optional: isContract, enabled: widget.enabled, initialValue: v.description, maxLines: 5, minLines: 3, maxLength: 4000, errorText: _e('description'), onChanged: (x) => v.description = x),
      gap,
      TratraInput(label: 'Ville', required: true, enabled: widget.enabled, initialValue: v.city, errorText: _e('city') ?? _e('location_city'), onChanged: (x) => v.city = x),
      gap,
      TratraInput(label: isContract ? 'Adresse du lieu de travail' : 'Quartier ou zone', optional: true, enabled: widget.enabled, initialValue: v.address, errorText: _e('location_note') ?? _e('location_address'),
          helper: isContract ? 'Visible des deux parties une fois le contrat proposé.' : 'Ne mettez pas l’adresse exacte dans une offre publique.', onChanged: (x) => v.address = x),
      gap,
      TratraInput(label: isContract ? 'Début' : 'Début souhaité', required: isContract, optional: !isContract, controller: _dates['start'], readOnly: true, enabled: widget.enabled, leadingIcon: Icons.event_outlined, errorText: _e('start_date'), onTap: () => _pick('start')),
      gap,
      TratraInput(label: isContract ? 'Fin (vide = durée indéterminée)' : 'Fin souhaitée (vide = indéterminée)', optional: true, controller: _dates['end'], readOnly: true, enabled: widget.enabled, leadingIcon: Icons.event_outlined, errorText: _e('end_date'),
          helper: maxMonths == null ? null : 'Durée maximale pour ce métier : $maxMonths mois.', onTap: () => _pick('end')),
      if (v.endDate.isNotEmpty)
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: widget.enabled ? () => _set(() { v.endDate = ''; _dates['end']!.text = ''; v.autoRenew = false; }) : null, child: const Text('Effacer la date de fin'))),
      if (!isContract) ...[
        gap,
        TratraInput(label: 'Date limite de candidature', optional: true, controller: _dates['deadline'], readOnly: true, enabled: widget.enabled, leadingIcon: Icons.event_outlined, errorText: _e('application_deadline'), onTap: () => _pick('deadline')),
        gap,
        TratraInput(label: 'Durée envisagée (mois)', optional: true, enabled: widget.enabled, initialValue: v.durationMonths, keyboardType: TextInputType.number, errorText: _e('duration_months'),
            helper: 'Indicative : la durée exacte figure au contrat.', onChanged: (x) => v.durationMonths = x),
      ],
      gap,
      ScheduleEditor(value: v.schedule, onChanged: (s) => _set(() => v.schedule = s), error: _e('schedule')),
      gap,
      _select('Rémunération', v.period, [for (final e in periodLabel.entries) (e.key, e.value)], (x) => _set(() => v.period = x), error: _e('period')),
      gap,
      TratraInput(label: 'Montant (FCFA ${periodFr[v.period] ?? ''})', required: true, enabled: widget.enabled, initialValue: v.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), errorText: _e('amount'), onChanged: (x) => v.amount = x),
      if (isContract) ...[
        gap,
        TratraInput(label: 'Jour de paiement du mois', enabled: widget.enabled, initialValue: v.paymentDay, keyboardType: TextInputType.number, errorText: _e('payment_day'), helper: 'Entre 1 et 31 ; le paiement est déclaré puis confirmé par l’autre partie.', onChanged: (x) => v.paymentDay = x),
        gap,
        TratraInput(label: 'Préavis (jours)', enabled: widget.enabled, initialValue: v.notice, keyboardType: TextInputType.number, errorText: _e('notice_period_days'), helper: minNotice == null ? null : 'Minimum pour ce métier : $minNotice jours.', onChanged: (x) => v.notice = x),
        if (v.period == 'monthly') ...[
          gap,
          _select('Dernière période incomplète', v.proration, const [('none', 'Montant du contrat (aucun prorata)'), ('calendar_days', 'Prorata au nombre de jours calendaires (convenu)')], (x) => _set(() => v.proration = x),
              error: _e('proration_mode'), helper: 'Tratra n’invente aucun prorata : sans clause, la dernière période est payée au montant du contrat.'),
        ],
        gap,
        TratraInput(label: 'Taux horaire des heures supplémentaires (FCFA)', optional: true, enabled: widget.enabled, initialValue: v.overtimeRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), errorText: _e('overtime_hourly_rate'),
            helper: 'Sans taux au contrat, les heures supplémentaires sont enregistrées mais jamais valorisées par Tratra.', onChanged: (x) => v.overtimeRate = x),
        gap,
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: v.autoRenew && v.endDate.isNotEmpty,
          onChanged: widget.enabled && v.endDate.isNotEmpty ? (x) => _set(() => v.autoRenew = x == true) : null,
          title: Text(v.endDate.isEmpty ? 'Renouvellement automatique (contrat à durée déterminée seulement)' : 'Renouveler automatiquement à l’échéance (sauf non-renouvellement dans le délai de préavis)', style: TratraTheme.style(TtType.bodySm)),
        ),
        if (v.autoRenew && v.endDate.isNotEmpty) TratraInput(label: 'Durée de chaque renouvellement (mois)', enabled: widget.enabled, initialValue: v.renewalMonths, keyboardType: TextInputType.number, errorText: _e('renewal_term_months'), onChanged: (x) => v.renewalMonths = x),
        if (v.relationship == 'independent' && v.schedule.isNotEmpty)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: v.bookingsMode == 'per_occurrence',
            onChanged: widget.enabled ? (x) => _set(() => v.bookingsMode = x == true ? 'per_occurrence' : 'none') : null,
            title: Text('Créer une réservation Tratra par intervention (suivi, avis et litiges de chaque intervention)', style: TratraTheme.style(TtType.bodySm)),
            subtitle: _e('bookings_mode') == null ? null : Text(_e('bookings_mode')!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
          ),
      ],
      gap,
      TratraInput(label: 'Avantages', optional: true, enabled: widget.enabled, initialValue: v.benefits, maxLines: 3, minLines: 2, maxLength: 2000, errorText: _e('benefits'),
          helper: 'Repas, transport, logement… Uniquement ce qui est réellement proposé.', onChanged: (x) => v.benefits = x),
      gap,
      TratraInput(label: 'Conditions particulières', optional: true, enabled: widget.enabled, initialValue: v.conditions, maxLines: 4, minLines: 3, maxLength: 4000, errorText: _e('conditions'),
          helper: 'Tenue, matériel fourni, déplacements… Tout ce dont vous convenez doit figurer ici.', onChanged: (x) => v.conditions = x),
    ]);
  }
}
