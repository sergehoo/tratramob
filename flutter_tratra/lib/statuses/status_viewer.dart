// lib/statuses/status_viewer.dart
//
// Visionneuse plein écran : barres de progression, passage automatique au statut suivant, pause (appui maintenu) et reprise, précédent /
// suivant (appui sur les bords), réponse par message, signalement, et — pour l'auteur — compteur de vues et liste nominative des lecteurs.
// Une vue n'est envoyée au serveur que lorsque le statut est RÉELLEMENT affiché (texte : au premier affichage ; photo : image décodée ;
// vidéo : lecture démarrée), jamais au préchargement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart' show showMessage;
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_models.dart';

/// Résultat renvoyé à la fermeture : statuts vus et indicateur de modification (suppression).
class ViewerResult {
  ViewerResult(this.viewed, this.changed);
  final List<int> viewed;
  final bool changed;
}

Duration statusTextDuration(String text) => Duration(milliseconds: (3500 + text.length * 35).clamp(5000, 12000));

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({super.key, required this.groups, this.startGroup = 0});
  final List<StatusGroup> groups;
  final int startGroup;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> with SingleTickerProviderStateMixin {
  late final StatusApi _api = context.read<StatusApi>();
  late final AnimationController _anim = AnimationController(vsync: this)..addStatusListener(_onAnimStatus);
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  final _viewed = <int>{};
  final _removed = <int>{};
  VideoPlayerController? _video;
  late int _gi = widget.startGroup;
  int _si = 0;
  bool _holding = false;
  bool _sheet = false;
  bool _muted = true;
  bool _changed = false;
  String? _notice;
  int _gen = 0;
  int _photoShownFor = -1;

  List<StatusItem> get _live => widget.groups[_gi].statuses.where((s) => !_removed.contains(s.id)).toList();
  StatusItem? get _status => _si < _live.length ? _live[_si] : null;
  bool get _paused => _holding || _sheet || _replyFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    final first = widget.groups[_gi].statuses.indexWhere((s) => !s.seen && !s.mine);
    _si = first > 0 ? first : 0;
    _replyFocus.addListener(_syncPause);
    _show();
  }

  @override
  void dispose() {
    _gen++;
    _anim.dispose();
    _video?.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _syncPause() {
    if (!mounted) return;
    setState(() {});
    if (_paused) {
      _anim.stop();
      _video?.pause();
    } else if (_status?.kind == 'video') {
      _video?.play();
    } else if (_anim.duration != null && !_anim.isCompleted) {
      _anim.forward();
    }
  }

  void _onAnimStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) _next();
  }

  Future<void> _show() async {
    final gen = ++_gen;
    _photoShownFor = -1;
    _anim.stop();
    _anim.value = 0;
    await _video?.dispose();
    _video = null;
    final st = _status;
    if (st == null || !mounted) return;
    setState(() => _notice = null);
    if (st.kind == 'text') {
      _begin(statusTextDuration(st.text), st);
    } else if (st.kind == 'video' && st.media?.url != null) {
      final c = VideoPlayerController.networkUrl(Uri.parse(resolveMediaUrl(st.media!.url!)));
      _video = c;
      try {
        await c.initialize();
        if (!mounted || gen != _gen) return;
        await c.setVolume(_muted ? 0 : 1);
        setState(() {});
        c.addListener(() {
          if (!mounted || gen != _gen || !c.value.isInitialized) return;
          final total = c.value.duration.inMilliseconds;
          if (total > 0 && !_paused) _anim.value = (c.value.position.inMilliseconds / total).clamp(0.0, 1.0);
          if (total > 0 && c.value.position >= c.value.duration && !c.value.isPlaying) _next();
        });
        _recordView(st); // lecture démarrée : le statut est affiché
        await c.play();
      } catch (_) {
        if (mounted && gen == _gen) setState(() => _notice = 'Cette vidéo n’a pas pu être lue.');
      }
    }
    // photo : la durée démarre quand l'image est affichée (voir _photo)
  }

  void _begin(Duration d, StatusItem st) {
    _anim.duration = d;
    _recordView(st);
    if (!_paused) _anim.forward(from: 0);
  }

  void _recordView(StatusItem st) {
    if (st.mine || !_viewed.add(st.id)) return;
    _api.view(st.id).catchError((_) => false);
  }

  void _next() {
    if (!mounted) return;
    final live = _live;
    if (_si + 1 < live.length) {
      setState(() => _si++);
      _show();
    } else if (_gi + 1 < widget.groups.length) {
      setState(() {
        _gi++;
        final first = widget.groups[_gi].statuses.indexWhere((s) => !s.seen && !s.mine);
        _si = first > 0 ? first : 0;
      });
      _show();
    } else {
      _close();
    }
  }

  void _prev() {
    if (_si > 0) {
      setState(() => _si--);
      _show();
    } else if (_gi > 0) {
      setState(() {
        _gi--;
        _si = (widget.groups[_gi].statuses.length - 1).clamp(0, 999);
      });
      _show();
    } else {
      _show();
    }
  }

  void _close() {
    if (mounted) Navigator.of(context).pop(ViewerResult(_viewed.toList(), _changed));
  }

  Future<void> _openReaders() async {
    final st = _status;
    if (st == null) return;
    setState(() => _sheet = true);
    _syncPause();
    try {
      final readers = await _api.viewers(st.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.all(16), child: Text('Lecteurs de ce statut', style: TratraTheme.style(TtType.h3))),
              if (readers.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Text('Personne n’a encore vu ce statut.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final r in readers)
                      ListTile(
                        leading: TratraAvatar(name: r.user.name, photoUrl: r.user.avatar == null ? null : resolveMediaUrl(r.user.avatar!), size: 36),
                        title: Text(r.user.name),
                        trailing: Text(r.viewedAt == null ? '' : _hm(r.viewedAt!.toLocal()) + ((r.count ?? 1) > 1 ? ' · ×${r.count}' : ''), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'La liste des lecteurs n’a pas pu être chargée.'), error: true);
    } finally {
      if (mounted) {
        setState(() => _sheet = false);
        _syncPause();
      }
    }
  }

  String _hm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _delete() async {
    final st = _status;
    if (st == null) return;
    setState(() => _sheet = true);
    _syncPause();
    final sure = await showTratraConfirm(context, title: 'Supprimer ce statut ?', message: 'Cette action est définitive.', confirmLabel: 'Supprimer', danger: true);
    if (!mounted) return;
    setState(() => _sheet = false);
    if (!sure) return _syncPause();
    try {
      await _api.delete(st.id);
      _changed = true;
      _removed.add(st.id);
      if (_live.isEmpty) return _close();
      if (_si >= _live.length) _si = _live.length - 1;
      setState(() {});
      _show();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le statut n’a pas pu être supprimé.'), error: true);
      _syncPause();
    }
  }

  Future<void> _sendReply() async {
    final st = _status;
    final text = _reply.text.trim();
    if (st == null || text.isEmpty) return;
    try {
      await _api.reply(st.id, text);
      _reply.clear();
      _replyFocus.unfocus();
      if (mounted) setState(() => _notice = 'Réponse envoyée dans vos messages.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'La réponse n’a pas pu être envoyée.'), error: true);
    }
  }

  Future<void> _report() async {
    final st = _status;
    if (st == null) return;
    final reason = TextEditingController();
    setState(() => _sheet = true);
    _syncPause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler ce statut'),
        content: TextField(controller: reason, maxLength: 500, maxLines: 3, decoration: const InputDecoration(hintText: 'Motif du signalement')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer'))],
      ),
    );
    if (mounted) setState(() => _sheet = false);
    _syncPause();
    if (ok != true || reason.text.trim().length < 3) return;
    try {
      await _api.report(st.id, reason.text.trim());
      if (mounted) setState(() => _notice = 'Merci. Le signalement a été transmis à l’équipe Tratra.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le signalement n’a pas pu être envoyé.'), error: true);
    }
  }

  Widget _content(StatusItem st) {
    if (st.kind == 'text') {
      final c = statusBackgrounds[st.background ?? 'green'] ?? statusBackgrounds['green']!;
      return Container(color: c.bg, alignment: Alignment.center, padding: const EdgeInsets.all(32), child: Text(st.text, textAlign: TextAlign.center, style: TratraTheme.style(TtType.h2, color: c.fg)));
    }
    if (st.kind == 'photo' && st.media?.url != null) {
      return Image.network(
        resolveMediaUrl(st.media!.url!),
        fit: BoxFit.contain,
        frameBuilder: (ctx, child, frame, sync) {
          // La durée ne démarre — et la vue n'est comptée — qu'à l'affichage effectif de l'image.
          if (frame != null && _photoShownFor != st.id) {
            _photoShownFor = st.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _status?.id == st.id) _begin(const Duration(seconds: 6), st);
            });
          }
          return child;
        },
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48)),
      );
    }
    final v = _video;
    if (v != null && v.value.isInitialized) {
      return Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)));
    }
    return const Center(child: CircularProgressIndicator(color: TtColors.accent));
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    if (st == null) return const Scaffold(backgroundColor: Colors.black);
    final group = widget.groups[_gi];
    final live = _live;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: _content(st)),
                if (st.kind != 'text' && st.text.isNotEmpty)
                  Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(20, 40, 20, 16), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Text(st.text, textAlign: TextAlign.center, style: TratraTheme.style(TtType.body, color: Colors.white)))),
                // Zones tactiles : appui court = précédent / suivant ; appui maintenu = pause
                Positioned.fill(
                  child: Row(children: [
                    Expanded(flex: 1, child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _prev, onLongPressStart: (_) { setState(() => _holding = true); _syncPause(); }, onLongPressEnd: (_) { setState(() => _holding = false); _syncPause(); })),
                    Expanded(flex: 2, child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _next, onLongPressStart: (_) { setState(() => _holding = true); _syncPause(); }, onLongPressEnd: (_) { setState(() => _holding = false); _syncPause(); })),
                  ]),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 16),
                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent])),
                    child: Column(children: [
                      AnimatedBuilder(
                        animation: _anim,
                        builder: (_, __) => Row(children: [
                          for (var i = 0; i < live.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: i < _si ? 1 : (i == _si ? _anim.value : 0), minHeight: 3, color: Colors.white, backgroundColor: Colors.white30)),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        TratraAvatar(name: group.author.name, photoUrl: group.author.avatar == null ? null : resolveMediaUrl(group.author.avatar!), size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(st.mine ? 'Mon statut' : group.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title, color: Colors.white)),
                            Text('Expire dans ${st.timeLeft}', style: TratraTheme.style(TtType.caption, color: Colors.white70)),
                          ]),
                        ),
                        if (st.kind == 'video')
                          IconButton(tooltip: _muted ? 'Activer le son' : 'Couper le son', icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white), onPressed: () { setState(() => _muted = !_muted); _video?.setVolume(_muted ? 0 : 1); }),
                        IconButton(tooltip: _holding ? 'Reprendre' : 'Pause', icon: Icon(_anim.isAnimating || (_video?.value.isPlaying ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white), onPressed: () { setState(() => _holding = !_holding); _syncPause(); }),
                        IconButton(tooltip: 'Fermer', icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: _close),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
            Container(
              color: TtColors.night,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_notice!, style: TratraTheme.style(TtType.caption, color: TtColors.accent))),
                if (st.mine)
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton.icon(
                      onPressed: _openReaders,
                      icon: const Icon(Icons.visibility_outlined, color: Colors.white),
                      label: Text('${st.viewsUnique} ${st.viewsUnique > 1 ? 'vues' : 'vue'}', style: const TextStyle(color: Colors.white)),
                    ),
                    IconButton(tooltip: 'Supprimer ce statut', icon: const Icon(Icons.delete_outline_rounded, color: Colors.white), onPressed: _delete),
                  ])
                else
                  Row(children: [
                    Expanded(
                      child: st.allowReplies
                          ? TextField(
                              controller: _reply,
                              focusNode: _replyFocus,
                              maxLength: 1000,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'Répondre par message…',
                                hintStyle: const TextStyle(color: Colors.white60),
                                filled: true,
                                fillColor: Colors.white10,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              ),
                              onSubmitted: (_) => _sendReply(),
                            )
                          : Center(child: Text('Les réponses sont désactivées pour ce statut.', style: TratraTheme.style(TtType.caption, color: Colors.white60))),
                    ),
                    if (st.allowReplies) IconButton(tooltip: 'Envoyer la réponse', icon: const Icon(Icons.send_rounded, color: TtColors.accent), onPressed: _sendReply),
                    IconButton(tooltip: 'Signaler ce statut', icon: const Icon(Icons.flag_outlined, color: Colors.white), onPressed: _report),
                  ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
