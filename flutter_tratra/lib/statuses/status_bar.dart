// lib/statuses/status_bar.dart
//
// Barre horizontale des statuts, juste sous l'en-tête de l'accueil : « Mon statut » en premier, puis les contacts Tratra (non lus avant les
// consultés, anneau distinctif sur les non lus), puis l'accès à « Découvrir les statuts ». Une panne des statuts ne dégrade jamais l'accueil.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_composer.dart';
import 'package:flutter_tratra/statuses/status_models.dart';
import 'package:flutter_tratra/statuses/status_presence.dart';
import 'package:flutter_tratra/statuses/status_viewer.dart';
import 'package:flutter_tratra/statuses/statuses_screen.dart';

/// Anneau des statuts, comme WhatsApp : un segment par statut (jusqu'à 30), vert pour un statut non vu, gris une fois vu ; les plus
/// anciens (déjà vus) d'abord dans le sens des aiguilles d'une montre.
class StatusRing extends StatelessWidget {
  const StatusRing({super.key, required this.unseen, required this.child, this.size = 64, this.count = 1, int? unseenCount})
      : unseenCount = unseenCount ?? (unseen ? count : 0);
  final bool unseen;
  final Widget child;
  final double size;
  final int count;
  final int unseenCount;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: StatusRingPainter(count: count, unseen: unseenCount),
          child: Padding(
            padding: EdgeInsets.all(size * 0.075),
            child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Center(child: child)),
          ),
        ),
      );
}

class StatusRingPainter extends CustomPainter {
  StatusRingPainter({required int count, required int unseen})
      : segments = count.clamp(1, 30),
        unseen = unseen.clamp(0, count.clamp(1, 30));
  final int segments;
  final int unseen;

  static const seenColor = Color(0xFFB8BEC6);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.045;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    final sweep = 2 * math.pi / segments;
    final gap = segments > 1 ? math.min(0.14, sweep * 0.25) : 0.0;
    for (var i = 0; i < segments; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = i >= segments - unseen ? TtColors.primary : seenColor;
      canvas.drawArc(rect, -math.pi / 2 + i * sweep + gap / 2, sweep - gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(StatusRingPainter old) => old.segments != segments || old.unseen != unseen;
}

/// Ouvre la visionneuse puis rafraîchit le fil avec ce qui a été vu.
Future<void> openStatusViewer(BuildContext context, List<StatusGroup> groups, int start, {VoidCallback? onDone}) async {
  await Navigator.of(context).push<ViewerResult>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => StatusViewerScreen(groups: groups, startGroup: start)));
  onDone?.call();
}

class StatusBar extends StatefulWidget {
  const StatusBar({super.key, this.horizontalPadding = TtSpace.s4});
  final double horizontalPadding;
  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  late final StatusApi _api = context.read<StatusApi>();
  late final InboxController _inbox = context.read<InboxController>();
  StatusFeed? _feed;
  List<StatusGroup> _public = const [];
  bool _failed = false;
  StreamSubscription<InboxEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _inbox.events.listen((e) {
      if (e.type == 'status' || e.type == 'status_view' || e.type == 'resync') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = await _api.feed();
      // Membres qui partagent avec tous : affichés un par un après les contacts (comme les « Actus » de WhatsApp), jamais cachés derrière
      // un compteur. Leur panne n'empêche pas la barre.
      var public = const <StatusGroup>[];
      if (f.discoverCount > 0) {
        try {
          public = (await _api.discover()).groups;
        } catch (_) {}
      }
      if (mounted) setState(() { _feed = f; _public = public; _failed = false; });
    } catch (_) {
      if (mounted && _feed == null) setState(() => _failed = true);
    }
    if (mounted) unawaited(maybeStatusPresence(context, listen: false)?.refresh(force: true));
  }

  Future<void> _compose() async {
    final f = _feed;
    if (f == null) return;
    final item = await Navigator.of(context).push<StatusItem>(MaterialPageRoute(builder: (_) => StatusComposerScreen(limits: f.limits)));
    if (item != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final f = _feed;
    if (_failed && f == null) return const SizedBox.shrink();
    if (f == null) return const SizedBox(height: 92);
    final mine = f.mine;
    final others = [...f.contacts, ..._public];
    final all = [if (mine.statuses.isNotEmpty) mine, ...others];
    final offset = mine.statuses.isNotEmpty ? 1 : 0;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding, vertical: 4),
        children: [
          _Cell(
            label: 'Mon statut',
            semantics: mine.statuses.isEmpty ? 'Publier un statut' : 'Voir mes statuts',
            onTap: () => mine.statuses.isEmpty ? _compose() : openStatusViewer(context, all, 0, onDone: _load),
            ring: mine.statuses.isEmpty
                ? Container(width: 64, height: 64, padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: TtColors.line, width: 2)), child: TratraAvatar(name: mine.author.name, photoUrl: mine.author.avatar == null ? null : resolveMediaUrl(mine.author.avatar!), size: 52))
                : StatusRing(unseen: false, count: mine.statuses.length, child: TratraAvatar(name: mine.author.name, photoUrl: mine.author.avatar == null ? null : resolveMediaUrl(mine.author.avatar!), size: 52)),
            badge: GestureDetector(onTap: _compose, child: const CircleAvatar(radius: 11, backgroundColor: TtColors.accent, child: Icon(Icons.add_rounded, size: 16, color: TtColors.night))),
          ),
          for (var i = 0; i < others.length; i++)
            _Cell(
              label: others[i].author.name,
              semantics: 'Statuts de ${others[i].author.name}${others[i].unseen > 0 ? ', ${others[i].unseen} non lu${others[i].unseen > 1 ? 's' : ''}' : ''}',
              bold: !others[i].seen,
              onTap: () => openStatusViewer(context, all, i + offset, onDone: _load),
              ring: StatusRing(
                  unseen: !others[i].seen,
                  count: others[i].statuses.length,
                  unseenCount: others[i].unseen,
                  child: TratraAvatar(name: others[i].author.name, photoUrl: others[i].author.avatar == null ? null : resolveMediaUrl(others[i].author.avatar!), size: 52)),
            ),
          if (f.discoverCount > _public.length)
            _Cell(
              label: 'Tout voir (${f.discoverCount})',
              semantics: 'Tous les statuts',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatusesScreen())).then((_) => _load()),
              ring: Container(width: 64, height: 64, decoration: const BoxDecoration(color: TtColors.primarySoft, shape: BoxShape.circle), child: const Icon(Icons.explore_outlined, color: TtColors.primary)),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.ring, required this.onTap, required this.semantics, this.badge, this.bold = false});
  final String label;
  final Widget ring;
  final VoidCallback onTap;
  final String semantics;
  final Widget? badge;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: TtSpace.s3),
        child: SizedBox(
          width: 68,
          child: Semantics(
            button: true,
            label: semantics,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Column(children: [
                Stack(clipBehavior: Clip.none, children: [ring, if (badge != null) Positioned(right: -2, bottom: -2, child: badge!)]),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TratraTheme.style(TtType.caption, color: bold ? TtColors.ink : TtColors.ash).copyWith(fontSize: 11, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
              ]),
            ),
          ),
        ),
      );
}
