// lib/engagements/engagements_ui.dart
//
// Briques d'interface partagées des écrans d'engagements : feuille d'action (champs → serveur → fermeture seulement après
// CONFIRMATION), éditeur de planning, pièces justificatives privées, listes « libellé / valeur ». Présentation uniquement.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart';
import 'package:flutter_tratra/engagements/labels.dart';

/// Erreurs par champ d'une réponse `{code:"invalid", fields:{champ: message}}`.
Map<String, String> fieldErrorsOf(Object e) {
  if (e is! ApiException) return const {};
  try {
    final d = json.decode(e.body);
    final f = d is Map ? d['fields'] : null;
    if (f is Map) return {for (final x in f.entries) '${x.key}': x.value is List && (x.value as List).isNotEmpty ? '${(x.value as List).first}' : '${x.value}'};
  } catch (_) {}
  return const {};
}

/// Code d'erreur métier du serveur (`terms_changed`, `version_conflict`…).
String? errorCodeOf(Object e) {
  if (e is! ApiException) return null;
  try {
    final d = json.decode(e.body);
    return d is Map && d['code'] is String ? d['code'] as String : null;
  } catch (_) {
    return null;
  }
}

/// Refus local d'un formulaire (avant tout envoi) : affiché tel quel dans la feuille.
class FormError implements Exception {
  const FormError(this.message);
  final String message;
}

String messageOf(Object e, [String fallback = 'Opération impossible. Rien n’a été modifié.']) => e is ApiException ? e.message : (e is FormError ? e.message : fallback);

class StatusChip extends StatelessWidget {
  const StatusChip(this.view, {super.key});
  final StatusView view;
  @override
  Widget build(BuildContext context) => TratraBadge(view.$1, tone: view.$2, dot: true);
}

/// Lignes « libellé / valeur » ; une valeur absente s'affiche « — ».
class Facts extends StatelessWidget {
  const Facts(this.items, {super.key});
  final List<(String, String?)> items;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.toUpperCase(), style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 2),
                  Text((v == null || v.isEmpty) ? '—' : v, style: TratraTheme.style(TtType.body)),
                ],
              ),
            ),
        ],
      );
}

enum FieldKind { text, multiline, number, date, time, datetime, select, checkbox }

class FieldSpec {
  const FieldSpec(this.key, this.label,
      {this.kind = FieldKind.text, this.required = false, this.optional = false, this.hint, this.options = const [], this.initial = '', this.maxLength, this.firstDate, this.lastDate});
  final String key;
  final String label;
  final FieldKind kind;
  final bool required;
  final bool optional;
  final String? hint;
  final List<(String, String)> options;
  final String initial;
  final int? maxLength;
  final DateTime? firstDate;
  final DateTime? lastDate;
}

/// Feuille d'action : saisie → envoi → erreur réelle du serveur dans la feuille (jamais un succès affiché avant sa confirmation).
/// Renvoie `true` quand le serveur a confirmé.
Future<bool> showActionSheet(
  BuildContext context, {
  required String title,
  String? description,
  required String confirmLabel,
  required List<FieldSpec> fields,
  required Future<void> Function(Map<String, String> values) submit,
  bool danger = false,
  Widget? header,
}) async {
  final done = await showTratraSheet<bool>(
    context,
    title: title,
    description: description,
    isDismissible: true,
    child: _ActionForm(fields: fields, submit: submit, confirmLabel: confirmLabel, danger: danger, header: header),
  );
  return done == true;
}

class _ActionForm extends StatefulWidget {
  const _ActionForm({required this.fields, required this.submit, required this.confirmLabel, required this.danger, this.header});
  final List<FieldSpec> fields;
  final Future<void> Function(Map<String, String>) submit;
  final String confirmLabel;
  final bool danger;
  final Widget? header;
  @override
  State<_ActionForm> createState() => _ActionFormState();
}

class _ActionFormState extends State<_ActionForm> {
  late final Map<String, String> _values = {for (final f in widget.fields) f.key: f.initial};
  late final Map<String, TextEditingController> _ctrl = {
    for (final f in widget.fields)
      if (f.kind != FieldKind.select && f.kind != FieldKind.checkbox) f.key: TextEditingController(text: _display(f, f.initial)),
  };
  Map<String, String> _errors = const {};
  String? _error;
  bool _busy = false;

  static String _display(FieldSpec f, String v) {
    if (v.isEmpty) return '';
    return switch (f.kind) {
      FieldKind.date => dateFr(v),
      FieldKind.time => timeFr('$v:00').replaceAll(' h ', ':'),
      FieldKind.datetime => dateTimeFr(v),
      _ => v,
    };
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready => widget.fields.every((f) => !f.required || (_values[f.key] ?? '').trim().isNotEmpty && _values[f.key] != 'false');

  Future<void> _pickDate(FieldSpec f) async {
    final now = DateTime.now();
    final current = parseDay(_values[f.key]) ?? now;
    final first = f.firstDate ?? DateTime(now.year - 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: f.lastDate ?? DateTime(now.year + 8),
      locale: const Locale('fr'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _values[f.key] = isoDay(picked);
      _ctrl[f.key]!.text = dateFr(isoDay(picked));
    });
  }

  Future<void> _pickTime(FieldSpec f) async {
    final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (picked == null || !mounted) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _values[f.key] = v;
      _ctrl[f.key]!.text = v;
    });
  }

  Future<void> _pickDateTime(FieldSpec f) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: DateTime(now.year + 2), locale: const Locale('fr'));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (t == null || !mounted) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      _values[f.key] = dt.toUtc().toIso8601String();
      _ctrl[f.key]!.text = dateTimeFr(dt.toUtc().toIso8601String());
    });
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _errors = const {};
    });
    try {
      await widget.submit({for (final e in _values.entries) e.key: e.value.trim()});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = fieldErrorsOf(e);
        _error = messageOf(e);
      });
    }
  }

  Widget _field(FieldSpec f) {
    switch (f.kind) {
      case FieldKind.select:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.label, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: f.options.any((o) => o.$1 == _values[f.key]) ? _values[f.key] : f.options.first.$1,
            isExpanded: true,
            items: [for (final o in f.options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
            onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v ?? ''),
            decoration: InputDecoration(errorText: _errors[f.key]),
          ),
        ]);
      case FieldKind.checkbox:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _values[f.key] == 'true',
          onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v == true ? 'true' : 'false'),
          title: Text(f.label, style: TratraTheme.style(TtType.bodySm)),
        );
      case FieldKind.date:
        return TratraInput(label: f.label, required: f.required, optional: f.optional, helper: f.hint, errorText: _errors[f.key], controller: _ctrl[f.key], readOnly: true, enabled: !_busy,
            leadingIcon: Icons.event_outlined, onTap: () => _pickDate(f));
      case FieldKind.time:
        return TratraInput(label: f.label, required: f.required, optional: f.optional, helper: f.hint, errorText: _errors[f.key], controller: _ctrl[f.key], readOnly: true, enabled: !_busy,
            leadingIcon: Icons.schedule_rounded, onTap: () => _pickTime(f));
      case FieldKind.datetime:
        return TratraInput(label: f.label, required: f.required, optional: f.optional, helper: f.hint, errorText: _errors[f.key], controller: _ctrl[f.key], readOnly: true, enabled: !_busy,
            leadingIcon: Icons.event_available_outlined, onTap: () => _pickDateTime(f));
      case FieldKind.multiline:
      case FieldKind.text:
      case FieldKind.number:
        return TratraInput(
          label: f.label,
          required: f.required,
          optional: f.optional,
          helper: f.hint,
          errorText: _errors[f.key],
          controller: _ctrl[f.key],
          enabled: !_busy,
          maxLines: f.kind == FieldKind.multiline ? 4 : 1,
          minLines: f.kind == FieldKind.multiline ? 3 : null,
          maxLength: f.maxLength,
          keyboardType: f.kind == FieldKind.number ? const TextInputType.numberWithOptions(decimal: true) : null,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) ...[widget.header!, const SizedBox(height: 14)],
          for (final f in widget.fields) ...[_field(f), const SizedBox(height: 14)],
          if (_error != null) ...[TratraAlert(tone: TratraAlertTone.danger, message: _error!), const SizedBox(height: 14)],
          TratraButton(
            label: widget.confirmLabel,
            variant: widget.danger ? TratraButtonVariant.danger : TratraButtonVariant.primary,
            loading: _busy,
            block: true,
            onPressed: _ready && !_busy ? _send : null,
          ),
        ],
      );
}

/// Éditeur du planning hebdomadaire : une ligne par créneau (jour, début, fin).
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key, required this.value, required this.onChanged, this.error});
  final List<Json> value;
  final ValueChanged<List<Json>> onChanged;
  final String? error;
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  Future<void> _time(int index, String key) async {
    final cur = widget.value[index].s(key, '08:00').split(':');
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(cur[0]) ?? 8, minute: int.tryParse(cur.length > 1 ? cur[1] : '0') ?? 0));
    if (picked == null) return;
    final v = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    widget.onChanged([for (var i = 0; i < widget.value.length; i++) i == index ? {...widget.value[i], key: v} : widget.value[i]]);
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Planning hebdomadaire', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        if (slots.isEmpty) Text('Aucun créneau fixe : les interventions seront convenues au fil de l’eau.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        for (var i = 0; i < slots.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    initialValue: slots[i].i('weekday').clamp(0, 6),
                    isExpanded: true,
                    items: [for (var d = 0; d < 7; d++) DropdownMenuItem(value: d, child: Text(weekdays[d]))],
                    onChanged: (v) => widget.onChanged([for (var k = 0; k < slots.length; k++) k == i ? {...slots[k], 'weekday': v ?? 0} : slots[k]]),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: OutlinedButton(onPressed: () => _time(i, 'start'), child: Text(slots[i].s('start', '08:00')))),
                const SizedBox(width: 6),
                Expanded(flex: 2, child: OutlinedButton(onPressed: () => _time(i, 'end'), child: Text(slots[i].s('end', '12:00')))),
                IconButton(tooltip: 'Retirer le créneau ${i + 1}', onPressed: () => widget.onChanged([...slots]..removeAt(i)), icon: const Icon(Icons.delete_outline_rounded)),
              ],
            ),
          ),
        if (widget.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(widget.error!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk))),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TratraButton(
            label: 'Ajouter un créneau',
            size: TratraButtonSize.sm,
            variant: TratraButtonVariant.soft,
            leading: const Icon(Icons.add_rounded, size: 18),
            onPressed: () {
              final last = slots.isEmpty ? null : slots.last;
              widget.onChanged([
                ...slots,
                {'weekday': last == null ? 0 : (last.i('weekday') + 1) % 7, 'start': last?.s('start', '08:00') ?? '08:00', 'end': last?.s('end', '12:00') ?? '12:00'},
              ]);
            },
          ),
        ),
      ],
    );
  }
}

/// Pièce justificative PRIVÉE : téléchargée avec la session (même origine uniquement). Image : affichée dans une feuille ; PDF : lu DANS
/// l'application (`EvidencePdfPage`, copie temporaire supprimée à la fermeture) — jamais confié à une application tierce.
class EvidenceLink extends StatefulWidget {
  const EvidenceLink({super.key, required this.api, required this.evidence, this.pdfBodyBuilder});
  final EngagementsApi api;
  final Json evidence;

  /// Remplaçable dans les tests (le moteur PDF natif n'existe pas hors appareil).
  final PdfBodyBuilder? pdfBodyBuilder;
  @override
  State<EvidenceLink> createState() => _EvidenceLinkState();
}

class _EvidenceLinkState extends State<EvidenceLink> {
  bool _busy = false;
  String? _error;

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.download(widget.evidence.s('url'));
      if (!mounted) return;
      final refused = EvidenceFiles.refusal(bytes);
      if (refused != null) throw FormError(refused);
      final isPdf = EvidenceFiles.looksLikePdf(bytes) || widget.evidence.s('name').toLowerCase().endsWith('.pdf');
      if (isPdf) {
        await Navigator.of(context).push<void>(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => EvidencePdfPage(bytes: bytes, title: 'Pièce jointe (PDF)', bodyBuilder: widget.pdfBodyBuilder, purgeOnClose: widget.pdfBodyBuilder == null),
        ));
        return;
      }
      await showTratraSheet<void>(
        context,
        title: 'Pièce jointe',
        description: 'Privée : visible des deux parties seulement.',
        child: ClipRRect(borderRadius: BorderRadius.circular(TtRadius.control), child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Image illisible.'))),
      );
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e, 'Pièce indisponible.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(onPressed: _busy ? null : _open, icon: const Icon(Icons.attach_file_rounded, size: 18), label: const Text('Voir la pièce jointe')),
          if (_error != null) Text(_error!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
        ],
      );
}

/// Bouton d'action avec attente et erreur réelle sous le bouton (confirmer, accepter, valider…).
class AsyncAction extends StatefulWidget {
  const AsyncAction({super.key, required this.label, required this.run, this.variant = TratraButtonVariant.primary, this.size = TratraButtonSize.sm, this.confirm});
  final String label;
  final Future<void> Function() run;
  final TratraButtonVariant variant;
  final TratraButtonSize size;

  /// Texte de confirmation (action destructive) : demandé avant l'exécution.
  final String? confirm;
  @override
  State<AsyncAction> createState() => _AsyncActionState();
}

class _AsyncActionState extends State<AsyncAction> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    if (widget.confirm != null && !await showTratraConfirm(context, title: widget.label, message: widget.confirm, confirmLabel: widget.label, danger: widget.variant == TratraButtonVariant.danger)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.run();
    } catch (e) {
      if (mounted) setState(() => _error = messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TratraButton(label: widget.label, variant: widget.variant, size: widget.size, loading: _busy, onPressed: _busy ? null : _go),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk))),
        ],
      );
}

/// Navigation locale (évite toute dépendance circulaire avec `dash_nav.dart`).
Future<T?> goTo<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Chargement d'une ressource pour un bloc NON défilant (à l'intérieur d'une liste) : squelette → contenu / erreur honnête
/// avec « Réessayer ». `reloadKey` change → rechargement.
class EngLoader<T> extends StatefulWidget {
  const EngLoader({super.key, required this.load, required this.builder, this.reloadKey, this.errorTitle = 'Chargement impossible'});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final Object? reloadKey;
  final String errorTitle;
  @override
  State<EngLoader<T>> createState() => _EngLoaderState<T>();
}

class _EngLoaderState<T> extends State<EngLoader<T>> {
  T? _data;
  String? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant EngLoader<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _reload();
  }

  Future<void> _reload() async {
    final mine = ++_seq;
    if (_data == null) setState(() => _loading = true);
    try {
      final d = await widget.load();
      if (!mounted || mine != _seq) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || mine != _seq) return;
      setState(() {
        _error = messageOf(e, 'Chargement impossible pour le moment.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const TratraSkeletonList(count: 3, padding: EdgeInsets.zero);
    final d = _data;
    if (d == null) {
      return TratraEmptyState(
        compact: true,
        icon: Icons.cloud_off_rounded,
        title: widget.errorTitle,
        description: _error,
        actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: () {
          setState(() => _loading = true);
          _reload();
        })],
      );
    }
    return widget.builder(context, d, _reload);
  }
}

/// Pièce jointe facultative d'un paiement ou d'un ajustement : photo du reçu (5 Mo maximum, vérifiée par le serveur).
class AttachPicker extends StatefulWidget {
  const AttachPicker({super.key, required this.onPicked});
  final ValueChanged<String?> onPicked;
  @override
  State<AttachPicker> createState() => _AttachPickerState();
}

class _AttachPickerState extends State<AttachPicker> {
  String? _name;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2200, imageQuality: 85);
    if (x == null) return;
    widget.onPicked(x.path);
    if (mounted) setState(() => _name = x.name);
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(_name == null ? 'Joindre une photo du reçu (facultatif)' : _name!, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (_name != null)
            IconButton(
              tooltip: 'Retirer la pièce jointe',
              onPressed: () {
                widget.onPicked(null);
                setState(() => _name = null);
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      );
}


/// Professionnel VÉRIFIÉ choisi par son nom (le serveur ne renvoie que nom public, commune et identifiant).
class PickedWorker {
  const PickedWorker(this.id, this.name, this.commune);
  final int id;
  final String name;
  final String commune;
}

class WorkerPicker extends StatefulWidget {
  const WorkerPicker({super.key, required this.api, required this.onPicked, this.picked, this.label = 'Professionnel'});
  final EngagementsApi api;
  final ValueChanged<PickedWorker?> onPicked;
  final PickedWorker? picked;
  final String label;
  @override
  State<WorkerPicker> createState() => _WorkerPickerState();
}

class _WorkerPickerState extends State<WorkerPicker> {
  List<PickedWorker> _rows = const [];
  String _state = 'idle'; // idle | loading | error
  int _seq = 0;
  String _q = '';
  PickedWorker? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.picked;
  }

  Future<void> _search(String q) async {
    _q = q.trim();
    final mine = ++_seq;
    if (_q.length < 2) {
      setState(() {
        _rows = const [];
        _state = 'idle';
      });
      return;
    }
    setState(() => _state = 'loading');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || mine != _seq) return;
    try {
      final r = await widget.api.getList('/workers/?q=${Uri.encodeQueryComponent(_q)}');
      if (!mounted || mine != _seq) return;
      setState(() {
        _rows = [for (final w in r) PickedWorker(w.i('id'), w.s('name'), w.s('commune'))];
        _state = 'idle';
      });
    } catch (_) {
      if (mounted && mine == _seq) setState(() => _state = 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _picked;
    if (p != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)),
        child: Row(children: [
          const Icon(Icons.person_outline_rounded, color: TtColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${p.name}${p.commune.isEmpty ? '' : ' · ${p.commune}'}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          TextButton(
            onPressed: () {
              setState(() => _picked = null);
              widget.onPicked(null);
            },
            child: const Text('Changer'),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TratraInput(label: widget.label, hint: 'Prénom ou nom (2 lettres minimum)', helper: 'Seuls les professionnels vérifiés par Tratra apparaissent.', leadingIcon: Icons.search_rounded, onChanged: _search),
      if (_state == 'error') Padding(padding: const EdgeInsets.only(top: 6), child: Text('Recherche indisponible. Réessayez.', style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk))),
      if (_state == 'loading') Padding(padding: const EdgeInsets.only(top: 6), child: Text('Recherche…', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
      if (_q.length >= 2 && _state == 'idle' && _rows.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Aucun professionnel vérifié ne correspond.', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
      for (final w in _rows)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(w.name, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
          subtitle: w.commune.isEmpty ? null : Text(w.commune),
          onTap: () {
            setState(() => _picked = w);
            widget.onPicked(w);
          },
        ),
    ]);
  }
}
