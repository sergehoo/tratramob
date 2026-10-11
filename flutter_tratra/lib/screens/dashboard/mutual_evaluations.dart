// lib/screens/dashboard/mutual_evaluations.dart
//
// Évaluation réciproque (miroir de frontend/src/components/reviews/MutualEvaluations.tsx) : notes rapides (étoiles, commentaire
// facultatif), critères adaptés à la personne évaluée, réputation réelle (aucune moyenne sous 3 notes), contestation d'une note reçue.
// Les notes restent masquées à l'autre partie jusqu'à réciprocité ou expiration du délai : le serveur est l'autorité.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

/// Message lisible d'une erreur d'évaluation (le serveur renvoie un code stable et, pour une saisie invalide, un message par champ).
String evaluationErrorMessage(Object e, String fallback) {
  if (e is ApiException) {
    try {
      final d = json.decode(e.body);
      if (d is Map) {
        final fields = d['fields'];
        if (fields is Map && fields.isNotEmpty) return '${fields.values.first}';
        if (d['detail'] != null) return '${d['detail']}';
      }
    } catch (_) {}
    return e.message;
  }
  return fallback;
}

class EvalStars extends StatelessWidget {
  const EvalStars({super.key, required this.value, required this.onChanged, this.size = 36, this.clearable = false});
  final int value;
  final ValueChanged<int> onChanged;
  final double size;
  final bool clearable;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints(minWidth: size + 8, minHeight: size + 8),
            padding: EdgeInsets.zero,
            tooltip: '$i sur 5',
            icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= value ? TtColors.accent : TtColors.fog),
            onPressed: () => onChanged(clearable && value == i ? 0 : i),
          ),
      ]);
}

class MutualEvaluationsCard extends StatefulWidget {
  const MutualEvaluationsCard({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<MutualEvaluationsCard> createState() => _MutualEvaluationsCardState();
}

class _MutualEvaluationsCardState extends State<MutualEvaluationsCard> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;

  Future<void> _evaluate(Map<String, dynamic> p) async {
    final done = await showTratraSheet<String>(
      context,
      title: p['evaluated_role'] == 'provider' ? 'Évaluer le prestataire' : 'Évaluer le demandeur',
      description: '${p['service']}',
      child: _EvaluationForm(api: _api, pending: p),
    );
    if (done != null && mounted) {
      showMessage(context, done);
      setState(() => _version++);
      widget.onChanged?.call();
    }
  }

  Future<void> _contest(Map<String, dynamic> r) async {
    final done = await showTratraSheet<bool>(
      context,
      title: 'Contester cette évaluation',
      description: 'Expliquez pourquoi elle vous semble injustifiée. L’équipe Tratra l’examine ; seule une décision humaine peut la masquer.',
      child: _ContestForm(api: _api, id: (r['id'] as num).toInt()),
    );
    if (done == true && mounted) {
      showMessage(context, 'Contestation envoyée : l’équipe Tratra l’examine.');
      setState(() => _version++);
    }
  }

  Widget _score(String label, Map<String, dynamic> s, int minPublic) {
    final count = (s['count'] as num?)?.toInt() ?? 0;
    final avg = s['public'] == true ? (s['average'] as num?)?.toDouble() : null;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        Text(avg != null ? '${avg.toStringAsFixed(1)} / 5' : '—', style: TratraTheme.style(TtType.h3)),
        Text(count == 0 ? 'Aucune note' : '$count note${count > 1 ? 's' : ''}${avg == null ? ' · moyenne dès $minPublic' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ApiView<Map<String, dynamic>>(
      key: ValueKey('mutual-$_version'),
      errorTitle: 'Évaluations indisponibles',
      load: () => _api.getMap('/me/evaluations/'),
      builder: (context, data, reload) {
        List<Map<String, dynamic>> rows(String k) => ((data[k] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        final providerPending = rows('pending').where((p) => p['role'] == 'provider').toList();
        final received = rows('received_as_requester');
        final prov = (data['provider_score'] as Map).cast<String, dynamic>();
        final req = (data['requester_score'] as Map).cast<String, dynamic>();
        final rules = (data['rules'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (((prov['count'] as num?) ?? 0) == 0 && ((req['count'] as num?) ?? 0) == 0 && providerPending.isEmpty && received.isEmpty) return const SizedBox.shrink();
        final minPublic = (rules['min_public_count'] as num?)?.toInt() ?? 3;
        return Padding(
          padding: const EdgeInsets.only(bottom: TtSpace.s4),
          child: TratraCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Évaluations réciproques', style: TratraTheme.style(TtType.h3)),
              const SizedBox(height: TtSpace.s1),
              Text('Après chaque mission, les deux parties se notent. Les notes restent masquées jusqu’à ce que chacun ait évalué (ou après ${rules['reveal_days'] ?? 7} jours).',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              const SizedBox(height: TtSpace.s3),
              Row(children: [
                _score('Comme prestataire', prov, minPublic),
                _score('Comme demandeur', req, minPublic),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Missions évaluées', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    Text('${data['missions_evaluated'] ?? 0}', style: TratraTheme.style(TtType.h3)),
                  ]),
                ),
              ]),
              if (providerPending.isNotEmpty) ...[
                const SizedBox(height: TtSpace.s3),
                Text('Évaluer vos clients', style: TratraTheme.style(TtType.title)),
                for (final p in providerPending)
                  Padding(
                    padding: const EdgeInsets.only(top: TtSpace.s2),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['service']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
                          Text(p['other_party_evaluated'] == true ? 'Le client a déjà évalué : vos deux notes seront visibles.' : 'Sa note reste masquée tant que vous n’avez pas évalué.',
                              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                        ]),
                      ),
                      TratraButton(label: 'Évaluer', size: TratraButtonSize.sm, onPressed: () => _evaluate(p)),
                    ]),
                  ),
              ],
              if (received.isNotEmpty) ...[
                const SizedBox(height: TtSpace.s3),
                Text('Notes reçues comme demandeur', style: TratraTheme.style(TtType.title)),
                for (final r in received)
                  Padding(
                    padding: const EdgeInsets.only(top: TtSpace.s2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['rating']} / 5 · par ${r['from']}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
                          if ('${r['comment'] ?? ''}'.isNotEmpty) Text('${r['comment']}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                        ]),
                      ),
                      if (r['can_contest'] == true) TratraButton(label: 'Contester', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: () => _contest(r)) else const TratraBadge('Contestation envoyée', tone: TratraTone.gray),
                    ]),
                  ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

class _EvaluationForm extends StatefulWidget {
  const _EvaluationForm({required this.api, required this.pending});
  final DashboardApi api;
  final Map<String, dynamic> pending;
  @override
  State<_EvaluationForm> createState() => _EvaluationFormState();
}

class _EvaluationFormState extends State<_EvaluationForm> {
  final _comment = TextEditingController();
  int _rating = 0;
  final Map<String, int> _crit = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/bookings/${widget.pending['booking_id']}/evaluation/', {
        'rating': _rating,
        if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
        if (_crit.isNotEmpty) 'criteria': _crit,
      });
      final other = widget.pending['other_party_evaluated'] == true;
      if (mounted) Navigator.of(context).pop(other ? 'Merci ! Les deux évaluations sont maintenant visibles.' : 'Merci ! Votre note sera visible quand l’autre partie aura évalué à son tour, ou à l’expiration du délai.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = evaluationErrorMessage(e, 'L’évaluation n’a pas pu être enregistrée.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final criteria = ((widget.pending['criteria'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Votre note', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
      EvalStars(value: _rating, onChanged: (v) => setState(() => _rating = v)),
      const SizedBox(height: TtSpace.s3),
      TratraInput(controller: _comment, label: 'Commentaire', optional: true, maxLines: 4, minLines: 3, maxLength: 1000, helper: 'Pas de lien, d’e-mail ni de numéro de téléphone.'),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Détailler par critère (facultatif)', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
        children: [
          for (final c in criteria)
            Row(children: [
              Expanded(child: Text('${c['label']}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
              EvalStars(value: _crit['${c['key']}'] ?? 0, size: 24, clearable: true, onChanged: (v) => setState(() => v == 0 ? _crit.remove('${c['key']}') : _crit['${c['key']}'] = v)),
            ]),
        ],
      ),
      if (_error != null) ...[const SizedBox(height: TtSpace.s2), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
      const SizedBox(height: TtSpace.s3),
      TratraButton(label: 'Envoyer', block: true, loading: _busy, onPressed: _rating < 1 ? null : _submit),
    ]);
  }
}

class _ContestForm extends StatefulWidget {
  const _ContestForm({required this.api, required this.id});
  final DashboardApi api;
  final int id;
  @override
  State<_ContestForm> createState() => _ContestFormState();
}

class _ContestFormState extends State<_ContestForm> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/client-reviews/${widget.id}/contest/', {'reason': _reason.text.trim()});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = evaluationErrorMessage(e, 'La contestation n’a pas pu être envoyée.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TratraInput(controller: _reason, label: 'Votre explication', maxLines: 4, minLines: 3, maxLength: 500, onChanged: (_) => setState(() {})),
        if (_error != null) ...[const SizedBox(height: TtSpace.s2), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
        const SizedBox(height: TtSpace.s3),
        TratraButton(label: 'Envoyer', block: true, loading: _busy, onPressed: _reason.text.trim().length < 10 ? null : _submit),
      ]);
}
