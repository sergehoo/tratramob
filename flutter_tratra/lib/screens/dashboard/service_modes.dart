// lib/screens/dashboard/service_modes.dart
//
// Modes d'une offre : PONCTUEL (réservation), RÉCURRENT (interventions régulières sous contrat), CONTRACTUEL (engagement
// mensuel : nounou, chauffeur, gardien…). Bornés par la règle du métier, lue sur le serveur ; le serveur revalide tout.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

const serviceModes = [
  ('one_off', 'Ponctuel', 'Une intervention réservée par le client.'),
  ('recurring', 'Récurrent', 'Interventions régulières encadrées par un contrat (ex. ménage chaque semaine).'),
  ('contract', 'Contractuel (mensuel)', 'Engagement au mois : nounou, chauffeur, gardien…'),
];

/// Modes ouverts par le métier : le ponctuel l'est toujours ; récurrent et contractuel selon la règle.
Set<String> allowedModes(Map<String, dynamic>? rules) => {
      'one_off',
      if (rules?['allow_recurring'] == true) 'recurring',
      if (rules?['allow_long_term'] == true) 'contract',
    };

/// Retire les modes que le métier n'ouvre pas (ordre canonique) ; sans règle connue, rien n'est retiré.
List<String> sanitizeModes(Iterable<String> modes, Map<String, dynamic>? rules) {
  final allowed = rules == null ? null : allowedModes(rules);
  return [for (final m in serviceModes) if (modes.contains(m.$1) && (allowed == null || allowed.contains(m.$1))) m.$1];
}

String modesLabel(Object? modes) {
  final list = modes is List ? modes.map((e) => '$e').toSet() : const <String>{};
  return [for (final m in serviceModes) if (list.contains(m.$1)) m.$2].join(', ');
}

/// Règle du métier ; en cas d'échec, seuls les modes toujours ouverts sont proposés (jamais de règle supposée).
Future<Map<String, dynamic>> loadModeRules(DashboardApi api, Object categoryId) async {
  try {
    return await api.getMap('/engagements/rules/?category=$categoryId');
  } catch (_) {
    return const {'allow_recurring': false, 'allow_long_term': false};
  }
}

class ServiceModesField extends StatelessWidget {
  const ServiceModesField({super.key, required this.value, required this.onChanged, required this.rules, this.error, this.enabled = true});
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final Map<String, dynamic>? rules;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final allowed = allowedModes(rules);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final m in serviceModes)
        CheckboxListTile(
          key: ValueKey('mode-${m.$1}'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value.contains(m.$1),
          onChanged: !enabled || (rules != null && !allowed.contains(m.$1))
              ? null
              : (on) => onChanged(sanitizeModes(on == true ? [...value, m.$1] : value.where((x) => x != m.$1), rules)),
          title: Text(m.$2, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(rules != null && !allowed.contains(m.$1) ? '${m.$3} Non ouvert pour ce métier.' : m.$3,
              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ),
      if (error != null) Text(error!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
    ]);
  }
}

/// Modifier les modes d'une offre existante. Renvoie `true` si enregistré.
Future<bool> editServiceModes(BuildContext context, DashboardApi api, Map<String, dynamic> service) async {
  final saved = await showTratraSheet<bool>(
    context,
    title: 'Modes de l’offre',
    description: '${service['title']}',
    child: _ModesEditor(api: api, service: service),
  );
  return saved == true;
}

class _ModesEditor extends StatefulWidget {
  const _ModesEditor({required this.api, required this.service});
  final DashboardApi api;
  final Map<String, dynamic> service;
  @override
  State<_ModesEditor> createState() => _ModesEditorState();
}

class _ModesEditorState extends State<_ModesEditor> {
  Map<String, dynamic>? _rules;
  late List<String> _modes;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.service['modes'];
    _modes = current is List && current.isNotEmpty ? current.map((e) => '$e').toList() : ['one_off'];
    final category = widget.service['category_id'];
    if (category != null) {
      loadModeRules(widget.api, category).then((r) {
        if (mounted) setState(() => _rules = r);
      });
    }
  }

  Future<void> _save() async {
    final modes = sanitizeModes(_modes, _rules);
    if (modes.isEmpty) {
      setState(() => _error = 'Choisissez au moins un mode.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.patch('/services/${widget.service['id']}/', {'modes': modes});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'Les modes n’ont pas pu être enregistrés.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ServiceModesField(value: _modes, onChanged: (v) => setState(() => _modes = v), rules: _rules, error: _error, enabled: !_busy),
      const SizedBox(height: TtSpace.s3),
      TratraButton(key: const ValueKey('modes-save'), label: 'Enregistrer les modes', block: true, loading: _busy, onPressed: _busy ? null : _save),
    ]);
  }
}
