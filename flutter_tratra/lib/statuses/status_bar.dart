// lib/statuses/status_bar.dart
//
// Barre horizontale des statuts, juste sous l'en-tête de l'accueil : « Mon statut » en premier, puis les contacts Tratra (non lus avant les
// consultés, anneau distinctif sur les non lus), puis l'accès à « Découvrir les statuts ». Une panne des statuts ne dégrade jamais l'accueil.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_composer.dart';
import 'package:flutter_tratra/statuses/status_models.dart';
import 'package:flutter_tratra/statuses/status_viewer.dart';
import 'package:flutter_tratra/statuses/statuses_screen.dart';

/// Anneau : dégradé vert → jaune pour un statut non lu, gris discret pour un statut déjà vu.
class StatusRing extends StatelessWidget {
  const StatusRing({super.key, required this.unseen, required this.child, this.size = 64});
  final bool unseen;
  final Widget child;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: unseen ? const LinearGradient(colors: [TtColors.primary, TtColors.accent], begin: Alignment.bottomLeft, end: Alignment.topRight) : null, color: unseen ? null : TtColors.line),
        child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: child),
      );
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
      if (mounted) setState(() { _feed = f; _failed = false; });
    } catch (_) {
      if (mounted && _feed == null) setState(() => _failed = true);
    }
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
    final all = [if (mine.statuses.isNotEmpty) mine, ...f.contacts];
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
                : StatusRing(unseen: false, child: TratraAvatar(name: mine.author.name, photoUrl: mine.author.avatar == null ? null : resolveMediaUrl(mine.author.avatar!), size: 52)),
            badge: GestureDetector(onTap: _compose, child: const CircleAvatar(radius: 11, backgroundColor: TtColors.accent, child: Icon(Icons.add_rounded, size: 16, color: TtColors.night))),
          ),
          for (var i = 0; i < f.contacts.length; i++)
            _Cell(
              label: f.contacts[i].author.name,
              semantics: 'Statuts de ${f.contacts[i].author.name}${f.contacts[i].unseen > 0 ? ', ${f.contacts[i].unseen} non lu${f.contacts[i].unseen > 1 ? 's' : ''}' : ''}',
              bold: !f.contacts[i].seen,
              onTap: () => openStatusViewer(context, all, i + (mine.statuses.isNotEmpty ? 1 : 0), onDone: _load),
              ring: StatusRing(unseen: !f.contacts[i].seen, child: TratraAvatar(name: f.contacts[i].author.name, photoUrl: f.contacts[i].author.avatar == null ? null : resolveMediaUrl(f.contacts[i].author.avatar!), size: 52)),
            ),
          if (f.discoverCount > 0)
            _Cell(
              label: 'Découvrir (${f.discoverCount})',
              semantics: 'Découvrir les statuts',
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
