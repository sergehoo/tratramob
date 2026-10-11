// lib/screens/dashboard/reviews_screen.dart
//
// « Avis » : à rédiger / reçus (artisan) / donnés — GET /me/reviews/, POST /reviews/ (note globale 1-5 +
// critères facultatifs), photos (POST /reviews/{id}/photos/) et réponse publique de l'artisan
// (POST /reviews/{id}/reply/). Mêmes règles que le web : client concerné, mission terminée, 7 jours pour corriger.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/mutual_evaluations.dart';

const _criteria = <(String, String)>[
  ('quality', 'Qualité du travail'),
  ('punctuality', 'Ponctualité'),
  ('professionalism', 'Professionnalisme'),
  ('communication', 'Communication'),
  ('price', 'Rapport qualité / prix'),
];

enum _Tab { write, received, given }

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});
  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  _Tab _tab = _Tab.write;
  int _version = 0;

  void _refresh() {
    context.read<DashboardController>().load();
    setState(() => _version++);
  }

  Future<void> _write(Map<String, dynamic> item) async {
    final done = await showTratraSheet<bool>(
      context,
      title: 'Votre avis',
      description: '${item['service']} — ${item['artisan']}',
      child: _ReviewForm(api: _api, bookingId: (item['booking_id'] as num).toInt()),
    );
    if (done == true && mounted) _refresh();
  }

  Future<void> _edit(Map<String, dynamic> review) async {
    final done = await showTratraSheet<bool>(
      context,
      title: 'Modifier mon avis',
      description: '${review['service'] ?? 'Prestation'} — ${review['artisan'] ?? ''}',
      child: _ReviewForm(api: _api, review: review),
    );
    if (done == true && mounted) _refresh();
  }

  Future<void> _reply(Map<String, dynamic> review) async {
    final done = await showTratraSheet<bool>(
      context,
      title: 'Répondre à cet avis',
      description: 'Votre réponse est publique, sous l’avis du client.',
      child: _ReplyForm(api: _api, reviewId: (review['id'] as num).toInt(), initial: (review['reply'] as Map?)?['text'] as String?),
    );
    if (done == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = context.watch<DashboardController>().data?.isProvider ?? false;
    return DashPage(
      title: 'Avis',
      body: ApiView<Map<String, dynamic>>(
        key: ValueKey('reviews-$_version'),
        errorTitle: 'Avis indisponibles',
        load: () => _api.getMap('/me/reviews/'),
        builder: (context, data, reload) {
          List<Map<String, dynamic>> rows(String k) =>
              ((data[k] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          final toWrite = rows('to_write');
          final received = rows('received');
          final given = rows('given');
          final tab = (_tab == _Tab.received && !isProvider) ? _Tab.write : _tab;
          final list = tab == _Tab.write ? toWrite : (tab == _Tab.received ? received : given);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
            children: [
              MutualEvaluationsCard(onChanged: _refresh),
              Wrap(spacing: TtSpace.s2, children: [
                TratraChip(label: 'À rédiger (${toWrite.length})', selected: tab == _Tab.write, onTap: () => setState(() => _tab = _Tab.write)),
                if (isProvider) TratraChip(label: 'Reçus (${received.length})', selected: tab == _Tab.received, onTap: () => setState(() => _tab = _Tab.received)),
                TratraChip(label: 'Donnés (${given.length})', selected: tab == _Tab.given, onTap: () => setState(() => _tab = _Tab.given)),
              ]),
              const SizedBox(height: TtSpace.s3),
              if (list.isEmpty)
                SizedBox(
                  height: 300,
                  child: TratraEmptyState(
                    icon: Icons.star_outline_rounded,
                    title: tab == _Tab.write ? 'Aucun avis à rédiger' : (tab == _Tab.received ? 'Aucun avis reçu' : 'Aucun avis donné'),
                    description: tab == _Tab.write
                        ? 'Après chaque prestation terminée, vous pourrez la noter ici.'
                        : (tab == _Tab.received ? 'Les avis de vos clients apparaîtront ici.' : 'Vos avis publiés apparaîtront ici.'),
                  ),
                )
              else
                for (final r in list) ...[
                  if (tab == _Tab.write)
                    TratraCard(
                      padding: TratraCard.compact,
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r['service']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
                            Text('Artisan : ${r['artisan']}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                          ]),
                        ),
                        TratraButton(label: 'Noter', size: TratraButtonSize.sm, onPressed: () => _write(r)),
                      ]),
                    )
                  else
                    ReviewCard(
                      review: r,
                      received: tab == _Tab.received,
                      onReply: tab == _Tab.received && r['can_reply'] == true ? () => _reply(r) : null,
                      onEdit: tab == _Tab.given && r['can_edit'] == true ? () => _edit(r) : null,
                    ),
                  const SizedBox(height: TtSpace.s2),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Avis affiché : note, critères notés, commentaire, photos, réponse publique de l'artisan.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review, required this.received, this.onReply, this.onEdit});
  final Map<String, dynamic> review;
  final bool received;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final rating = ((review['rating'] ?? 0) as num).toInt();
    final date = DateTime.tryParse('${review['created_at'] ?? ''}');
    final comment = '${review['comment'] ?? ''}';
    final crit = (review['criteria'] as Map?) ?? const {};
    final photos = ((review['photos'] as List?) ?? const []).map((e) => '$e').toList();
    final reply = review['reply'] as Map?;
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: i <= rating ? TtColors.accent : TtColors.fog),
          const Spacer(),
          if (date != null) Text(formatWhen(date), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ]),
        if (crit.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s2),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in _criteria)
              if (crit[c.$1] != null)
                TratraBadge('${c.$2} ${crit[c.$1]}/5', tone: TratraTone.gray),
          ]),
        ],
        if (comment.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s2),
          Text(comment, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        ],
        if (photos.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s2),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(TtRadius.control),
                child: Image.network(photos[i], width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72)),
              ),
            ),
          ),
        ],
        if (reply != null) ...[
          const SizedBox(height: TtSpace.s3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(TtSpace.s3),
            decoration: BoxDecoration(color: TtColors.primarySoft.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(TtRadius.control)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Réponse de l’artisan', style: TratraTheme.style(TtType.caption, color: TtColors.primaryDark).copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${reply['text']}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            ]),
          ),
        ],
        const SizedBox(height: TtSpace.s2),
        Row(children: [
          Expanded(
            child: Text('${review['service'] ?? 'Prestation'} · ${received ? 'par ${review['author']}' : 'pour ${review['artisan']}'}',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ),
          if (onReply != null)
            TratraButton(label: reply != null ? 'Modifier ma réponse' : 'Répondre', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: onReply),
          if (onEdit != null) TratraButton(label: 'Modifier', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: onEdit),
        ]),
      ]),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged, this.size = 34, this.clearable = false});
  final int value;
  final ValueChanged<int> onChanged;
  final double size;
  final bool clearable;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i sur 5',
            iconSize: size,
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(clearable && value == i ? 0 : i),
            icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= value ? TtColors.accent : TtColors.fog),
          ),
      ]);
}

class _ReviewForm extends StatefulWidget {
  const _ReviewForm({required this.api, this.bookingId, this.review});
  final DashboardApi api;
  final int? bookingId;
  final Map<String, dynamic>? review;
  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  late final TextEditingController _comment = TextEditingController(text: '${widget.review?['comment'] ?? ''}');
  late int _rating = ((widget.review?['rating'] ?? 0) as num).toInt();
  late final Map<String, int> _crit = {
    for (final c in _criteria) c.$1: (((widget.review?['criteria'] as Map?)?[c.$1] ?? 0) as num).toInt(),
  };
  final _photos = <XFile>[];
  bool _busy = false;
  String? _error;

  int get _room => 4 - (((widget.review?['photos'] as List?) ?? const []).length);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 80);
      if (picked.isNotEmpty && mounted) setState(() => _photos..clear()..addAll(picked.take(_room)));
    } catch (_) {
      if (mounted) setState(() => _error = 'Les photos n’ont pas pu être sélectionnées.');
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'rating': _rating,
        'comment': _comment.text.trim(),
        for (final c in _criteria) c.$1: _crit[c.$1] == 0 ? null : _crit[c.$1],
      };
      final saved = widget.review != null
          ? await widget.api.patch('/reviews/${widget.review!['id']}/', body)
          : await widget.api.post('/reviews/', {'booking': widget.bookingId, ...body});
      for (final f in _photos) {
        await widget.api.postFile('/reviews/${saved['id']}/photos/', 'image', f.path);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'L’avis n’a pas pu être enregistré.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Note globale', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
      _Stars(value: _rating, onChanged: (v) => setState(() => _rating = v)),
      const SizedBox(height: TtSpace.s3),
      Text('Détails (facultatif)', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
      for (final c in _criteria)
        Row(children: [
          Expanded(child: Text(c.$2, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
          _Stars(value: _crit[c.$1] ?? 0, size: 24, clearable: true, onChanged: (v) => setState(() => _crit[c.$1] = v)),
        ]),
      const SizedBox(height: TtSpace.s3),
      TratraInput(controller: _comment, label: 'Commentaire', optional: true, maxLines: 4, minLines: 3, maxLength: 1000),
      if (_room > 0) ...[
        const SizedBox(height: TtSpace.s3),
        TratraButton(
          label: _photos.isEmpty ? 'Ajouter des photos' : 'Photos sélectionnées (${_photos.length})',
          variant: TratraButtonVariant.outline,
          leading: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          onPressed: _pick,
        ),
      ],
      if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
      const SizedBox(height: TtSpace.s4),
      TratraButton(label: widget.review != null ? 'Enregistrer' : 'Publier', block: true, loading: _busy, onPressed: _rating < 1 ? null : _submit),
    ]);
  }
}

class _ReplyForm extends StatefulWidget {
  const _ReplyForm({required this.api, required this.reviewId, this.initial});
  final DashboardApi api;
  final int reviewId;
  final String? initial;
  @override
  State<_ReplyForm> createState() => _ReplyFormState();
}

class _ReplyFormState extends State<_ReplyForm> {
  late final _text = TextEditingController(text: widget.initial ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/reviews/${widget.reviewId}/reply/', {'text': _text.text.trim()});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'La réponse n’a pas pu être publiée.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TratraInput(controller: _text, label: 'Votre réponse', maxLines: 4, minLines: 3, maxLength: 600),
        if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
        const SizedBox(height: TtSpace.s4),
        TratraButton(label: 'Publier la réponse', block: true, loading: _busy, onPressed: _send),
      ]);
}
