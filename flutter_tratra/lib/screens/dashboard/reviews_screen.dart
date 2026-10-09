// lib/screens/dashboard/reviews_screen.dart
//
// « Avis » : à rédiger / reçus (artisan) / donnés (GET /me/reviews/, POST /reviews/).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

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

  Future<void> _write(Map<String, dynamic> item) async {
    final done = await showTratraSheet<bool>(
      context,
      title: 'Votre avis',
      description: '${item['service']} — ${item['artisan']}',
      child: _ReviewForm(api: _api, bookingId: (item['booking_id'] as num).toInt()),
    );
    if (done == true && mounted) {
      context.read<DashboardController>().load();
      setState(() => _version++);
    }
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
                    _ReviewCard(review: r, received: tab == _Tab.received),
                  const SizedBox(height: TtSpace.s2),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.received});
  final Map<String, dynamic> review;
  final bool received;

  @override
  Widget build(BuildContext context) {
    final rating = ((review['rating'] ?? 0) as num).toInt();
    final date = DateTime.tryParse('${review['created_at'] ?? ''}');
    final comment = '${review['comment'] ?? ''}';
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 18, color: i <= rating ? TtColors.accent : TtColors.fog),
          const Spacer(),
          if (date != null) Text(formatWhen(date), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ]),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s2),
          Text(comment, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        ],
        const SizedBox(height: TtSpace.s2),
        Text('${review['service'] ?? 'Prestation'} · ${received ? 'par ${review['author']}' : 'pour ${review['artisan']}'}',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
      ]),
    );
  }
}

class _ReviewForm extends StatefulWidget {
  const _ReviewForm({required this.api, required this.bookingId});
  final DashboardApi api;
  final int bookingId;
  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  final _comment = TextEditingController();
  int _rating = 0;
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
      await widget.api.post('/reviews/', {'booking': widget.bookingId, 'rating': _rating, 'comment': _comment.text.trim()});
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
      Row(children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i sur 5',
            iconSize: 34,
            onPressed: () => setState(() => _rating = i),
            icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= _rating ? TtColors.accent : TtColors.fog),
          ),
      ]),
      const SizedBox(height: TtSpace.s2),
      TratraInput(controller: _comment, label: 'Commentaire', optional: true, maxLines: 4, minLines: 3),
      if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
      const SizedBox(height: TtSpace.s4),
      TratraButton(label: 'Publier', block: true, loading: _busy, onPressed: _rating < 1 ? null : _submit),
    ]);
  }
}
