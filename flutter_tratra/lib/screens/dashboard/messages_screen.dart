// lib/screens/dashboard/messages_screen.dart
//
// Messagerie : liste des conversations (recherche, pagination, non-lus en temps réel) et fil d'une conversation (messages persistants,
// états envoyé / distribué / lu, photos, vidéos et PDF, envoi idempotent avec reprise, blocage et signalement). Le temps réel vient de
// InboxController (WebSocket) ; si la connexion est coupée, l'API reste la source de vérité et la liste se rattrape toute seule.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/chat_models.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

/// Ouvre (ou crée) la conversation d'une réservation puis affiche le fil.
Future<void> openBookingConversation(BuildContext context, int bookingId) async {
  final api = context.read<MessagingApi>();
  try {
    final id = await api.openBooking(bookingId);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: id, title: 'Conversation')));
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e, 'La conversation n’a pas pu être ouverte.'), error: true);
  }
}

/// Ouvre (ou retrouve) le fil privé UNIQUE avec un membre (ex. depuis un statut).
Future<void> openDirectConversation(BuildContext context, int userId, {String title = 'Conversation'}) async {
  final api = context.read<MessagingApi>();
  try {
    final id = await api.openDirect(userId);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: id, title: title)));
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e, 'La conversation n’a pas pu être ouverte.'), error: true);
  }
}

class _NetworkNote extends StatelessWidget {
  const _NetworkNote();
  @override
  Widget build(BuildContext context) {
    final s = context.select<InboxController, InboxStatus>((c) => c.status);
    if (s == InboxStatus.live) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: TtColors.warningSoft,
      padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4, vertical: 6),
      child: Row(children: [
        const Icon(Icons.wifi_off_rounded, size: 16, color: TtColors.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            s == InboxStatus.connecting ? 'Connexion en cours…' : 'Hors connexion : vos messages sont enregistrés et la liste se met à jour dès le retour du réseau.',
            style: TratraTheme.style(TtType.caption, color: TtColors.warning),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────── Liste des conversations ───────────────────────────────────────────────

class MessagesList extends StatefulWidget {
  const MessagesList({super.key});
  @override
  State<MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<MessagesList> {
  late final MessagingApi _api = context.read<MessagingApi>();
  late final InboxController _inbox = context.read<InboxController>();
  final _search = TextEditingController();
  List<ChatConversation>? _items;
  int? _next;
  String? _error;
  Timer? _debounce;
  StreamSubscription<InboxEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _inbox.events.listen((e) {
      if (!mounted) return;
      if (e.type == 'message' && e.conversation != null) {
        setState(() {
          final rest = (_items ?? const <ChatConversation>[]).where((c) => c.id != e.conversation!.id).toList();
          _items = [e.conversation!, ...rest];
        });
      } else if (e.type == 'resync') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    try {
      final page = more && _next != null ? _next! : 1;
      final r = await _api.conversations(query: _search.text, page: page);
      if (!mounted) return;
      setState(() {
        _items = more ? [...?_items, ...r.items] : r.items;
        _next = r.nextPage;
        _error = null;
      });
    } catch (e) {
      if (mounted && _items == null) setState(() => _error = friendlyError(e, 'Vos conversations ne peuvent pas être chargées.'));
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(children: [
      const _NetworkNote(),
      Padding(
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, 0),
        child: TratraInput(controller: _search, hint: 'Rechercher une conversation ou un message', leadingIcon: Icons.search_rounded, onChanged: _onSearch),
      ),
      Expanded(
        child: _error != null && items == null
            ? TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Messagerie indisponible', description: _error, actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: _load)])
            : items == null
                ? const TratraSkeletonList(count: 4)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: items.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                            SizedBox(
                              height: 420,
                              child: TratraEmptyState(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: _search.text.isEmpty ? 'Aucune conversation' : 'Aucun résultat',
                                description: _search.text.isEmpty ? 'Ouvrez une réservation ou répondez à un statut pour écrire à un membre.' : 'Essayez un autre mot.',
                              ),
                            ),
                          ])
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
                            itemCount: items.length + (_next != null ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
                            itemBuilder: (_, i) {
                              if (i == items.length) {
                                return TratraButton(label: 'Voir plus', variant: TratraButtonVariant.outline, onPressed: () => _load(more: true));
                              }
                              return _ConversationTile(
                                conv: items[i],
                                onOpen: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: items[i].id, title: items[i].counterpart)));
                                  await _load();
                                  if (context.mounted) context.read<DashboardController>().load();
                                },
                              );
                            },
                          ),
                  ),
      ),
    ]);
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conv, required this.onOpen});
  final ChatConversation conv;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = conv;
    return TratraCard(
      padding: TratraCard.compact,
      onTap: onOpen,
      child: Row(children: [
        TratraAvatar(name: c.counterpart, size: 44),
        const SizedBox(width: TtSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(c.counterpart, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title))),
              if (c.isSupport) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_user_outlined, size: 14, color: TtColors.primary)),
              if (c.blocked) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.block_rounded, size: 14, color: TtColors.ash)),
              const Spacer(),
              if (c.lastAt != null) Text(formatWhen(c.lastAt!), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            ]),
            Text(c.lastMessage ?? 'Aucun message pour le moment',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.bodySm, color: c.unread > 0 ? TtColors.ink : TtColors.ash)),
          ]),
        ),
        if (c.unread > 0) ...[
          const SizedBox(width: TtSpace.s2),
          CircleAvatar(radius: 11, backgroundColor: TtColors.primary, child: Text(c.unread > 99 ? '99+' : '${c.unread}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
        ],
      ]),
    );
  }
}

// ───────────────────────────────────────────────────── Fil d'une conversation ─────────────────────────────────────────────────────

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, required this.title});
  final int conversationId;
  final String title;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final MessagingApi _api = context.read<MessagingApi>();
  late final InboxController _inbox = context.read<InboxController>();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  List<ChatMessage>? _messages;
  ChatConversation? _conv;
  String? _error;
  String? _notice;
  bool _hasMore = false;
  int? _before;
  bool _loadingOlder = false;
  XFile? _attachment;
  bool _stick = true;
  StreamSubscription<InboxEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.hasClients) _stick = _scroll.position.maxScrollExtent - _scroll.offset < 80;
    });
    _sub = _inbox.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _stick) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  Future<void> _load() async {
    try {
      final t = await _api.thread(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conv = t.conversation;
        final locals = (_messages ?? const <ChatMessage>[]).where((m) => m.local != null && !t.messages.any((r) => r.clientId != null && r.clientId == m.clientId));
        _messages = [...t.messages, ...locals];
        _hasMore = t.hasMore;
        _before = t.nextBefore;
        _error = null;
      });
      _toBottom();
      if (t.messages.any((m) => !m.mine && m.state != 'read')) _markRead();
    } catch (e) {
      if (mounted && _messages == null) setState(() => _error = friendlyError(e, 'Cette conversation ne peut pas être chargée.'));
    }
  }

  Future<void> _markRead() async {
    try {
      await _api.markRead(widget.conversationId);
      _inbox.refreshUnread();
    } catch (_) {}
  }

  void _onEvent(InboxEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case 'message' when e.conversationId == widget.conversationId && e.message != null:
        final m = e.message!;
        setState(() {
          final list = (_messages ?? <ChatMessage>[]).where((x) => !(x.local != null && x.clientId != null && x.clientId == m.clientId)).toList();
          if (!list.any((x) => x.id == m.id)) list.add(m);
          _messages = list;
        });
        _toBottom();
        if (!m.mine) _markRead();
      case 'delivered':
        setState(() => _messages = _messages?.map((m) => e.ids.contains(m.id) && m.state == 'sent' ? m.copyWith(state: 'delivered') : m).toList());
      case 'read' when e.conversationId == widget.conversationId:
        setState(() => _messages = _messages?.map((m) => m.mine && m.id <= (e.upto ?? 0) ? m.copyWith(state: 'read') : m).toList());
      case 'resync':
        _load();
    }
  }

  Future<void> _older() async {
    if (_before == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    _stick = false;
    try {
      final t = await _api.thread(widget.conversationId, before: _before);
      if (!mounted) return;
      setState(() {
        _messages = [...t.messages, ...?_messages];
        _hasMore = t.hasMore;
        _before = t.nextBefore;
      });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Les messages précédents n’ont pas pu être chargés.'), error: true);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _pick(String kind) async {
    try {
      final XFile? f = switch (kind) {
        'photo' => await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82),
        'camera' => await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 82),
        _ => await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60)),
      };
      if (f != null && mounted) setState(() => _attachment = f);
    } catch (_) {
      if (mounted) showMessage(context, 'Le fichier n’a pas pu être choisi.', error: true);
    }
  }

  void _attachSheet() => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo'), onTap: () { Navigator.pop(ctx); _pick('camera'); }),
            ListTile(leading: const Icon(Icons.photo_outlined), title: const Text('Choisir une photo'), onTap: () { Navigator.pop(ctx); _pick('photo'); }),
            ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Choisir une vidéo'), onTap: () { Navigator.pop(ctx); _pick('video'); }),
          ]),
        ),
      );

  Future<void> _send() async {
    final text = _input.text.trim();
    final file = _attachment;
    if (text.isEmpty && file == null) return;
    final lower = file?.path.toLowerCase() ?? '';
    final local = ChatMessage(
      id: -DateTime.now().microsecondsSinceEpoch,
      conversation: widget.conversationId,
      mine: true,
      content: text,
      kind: file == null ? 'text' : (lower.endsWith('.mp4') || lower.endsWith('.mov') ? 'video' : 'image'),
      createdAt: DateTime.now(),
      clientId: newClientId(),
      local: SendState.sending,
      localPath: file?.path,
    );
    _stick = true;
    setState(() {
      _messages = [...?_messages, local];
      _input.clear();
      _attachment = null;
      _notice = null;
    });
    _toBottom();
    await _deliver(local);
  }

  Future<void> _deliver(ChatMessage local) async {
    setState(() => _messages = _messages?.map((m) => m.clientId == local.clientId ? m.copyWith(local: SendState.sending, progress: 0) : m).toList());
    try {
      final saved = await _api.send(widget.conversationId,
          content: local.content,
          clientId: local.clientId!,
          filePath: local.localPath,
          onProgress: (p) {
            if (mounted) setState(() => _messages = _messages?.map((m) => m.clientId == local.clientId && m.local != null ? m.copyWith(progress: p) : m).toList());
          });
      if (!mounted) return;
      setState(() {
        final list = (_messages ?? <ChatMessage>[]).where((m) => !(m.local != null && m.clientId == local.clientId)).toList();
        if (!list.any((m) => m.id == saved.id)) list.add(saved);
        _messages = list;
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages?.map((m) => m.clientId == local.clientId ? m.copyWith(local: SendState.failed) : m).toList();
        _notice = friendlyError(e, 'Connexion interrompue : le message est conservé, touchez « Renvoyer » (il ne sera envoyé qu’une fois).');
      });
    }
  }

  Future<void> _report() async {
    final reason = TextEditingController();
    var alsoBlock = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Signaler cette conversation'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: reason, maxLength: 500, maxLines: 3, decoration: const InputDecoration(hintText: 'Motif du signalement')),
            CheckboxListTile(value: alsoBlock, onChanged: (v) => setS(() => alsoBlock = v ?? false), title: const Text('Bloquer aussi ce membre'), contentPadding: EdgeInsets.zero),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer'))],
        ),
      ),
    );
    if (ok != true || reason.text.trim().length < 3) return;
    try {
      await _api.report(widget.conversationId, reason.text.trim(), block: alsoBlock);
      if (mounted) showMessage(context, 'Merci. Le signalement a été transmis à l’équipe Tratra.');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le signalement n’a pas pu être envoyé.'), error: true);
    }
  }

  Future<void> _toggleBlock() async {
    final c = _conv;
    if (c?.counterpartId == null) return;
    try {
      if (c!.blocked) {
        await _api.unblock(c.counterpartId!);
      } else {
        await _api.block(c.counterpartId!);
      }
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'L’opération n’a pas pu être enregistrée.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _messages;
    final conv = _conv;
    final canSend = conv?.canSend ?? true;
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(
        title: conv?.counterpart ?? widget.title,
        actions: [
          if (conv != null && !conv.isSupport)
            PopupMenuButton<String>(
              tooltip: 'Options de la conversation',
              onSelected: (v) => v == 'report' ? _report() : _toggleBlock(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'report', child: Text('Signaler')),
                PopupMenuItem(value: 'block', child: Text(conv.blocked ? 'Débloquer ce membre' : 'Bloquer ce membre')),
              ],
            ),
        ],
      ),
      body: Column(children: [
        const _NetworkNote(),
        Expanded(
          child: _error != null
              ? TratraEmptyState(icon: Icons.cloud_off_rounded, title: 'Conversation indisponible', description: _error)
              : msgs == null
                  ? const TratraSkeletonList(count: 3)
                  : msgs.isEmpty
                      ? Center(child: Text('Aucun message. Écrivez le premier.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(TtSpace.s4),
                          itemCount: msgs.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (_hasMore && i == 0) {
                              return Center(child: TextButton(onPressed: _loadingOlder ? null : _older, child: Text(_loadingOlder ? 'Chargement…' : 'Messages précédents')));
                            }
                            final m = msgs[i - (_hasMore ? 1 : 0)];
                            return _Bubble(msg: m, onRetry: m.local == SendState.failed ? () => _deliver(m) : null, onDiscard: m.local == SendState.failed ? () => setState(() => _messages = _messages?.where((x) => x.clientId != m.clientId).toList()) : null);
                          },
                        ),
        ),
        if (_notice != null) Padding(padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4), child: TratraAlert(tone: TratraAlertTone.danger, message: _notice!)),
        if (!canSend)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(TtSpace.s4),
            color: TtColors.surface,
            child: Text('Vous ne pouvez plus écrire dans cette conversation.${conv?.blocked == true ? ' Débloquez ce membre pour reprendre.' : ''}', textAlign: TextAlign.center, style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          )
        else
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(TtSpace.s3, TtSpace.s2, TtSpace.s3, TtSpace.s2),
              decoration: const BoxDecoration(color: TtColors.surface, border: Border(top: BorderSide(color: TtColors.lineSoft))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_attachment != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      const Icon(Icons.attach_file_rounded, size: 18, color: TtColors.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_attachment!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.caption))),
                      IconButton(tooltip: 'Retirer la pièce jointe', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _attachment = null)),
                    ]),
                  ),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  IconButton(tooltip: 'Joindre une photo ou une vidéo', icon: const Icon(Icons.attach_file_rounded), onPressed: _attachSheet),
                  Expanded(
                    child: TratraInput(controller: _input, hint: 'Votre message…', maxLines: 4, minLines: 1, maxLength: 4000, textInputAction: TextInputAction.newline),
                  ),
                  const SizedBox(width: TtSpace.s2),
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: TratraButton(label: 'Envoyer', leading: const Icon(Icons.send_rounded, size: 18), onPressed: _send)),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, this.onRetry, this.onDiscard});
  final ChatMessage msg;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  Widget _ticks() {
    if (!msg.mine) return const SizedBox.shrink();
    if (msg.local == SendState.sending) return const Icon(Icons.schedule_rounded, size: 12, color: Colors.white70);
    if (msg.local == SendState.failed) return const Text('Échec', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700));
    return Icon(msg.state == 'sent' ? Icons.check_rounded : Icons.done_all_rounded, size: 14, color: msg.state == 'read' ? TtColors.accent : Colors.white70);
  }

  Widget _attachment(BuildContext context) {
    final a = msg.attachment;
    if (a?.url == null) {
      return msg.localPath == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('📎 ${msg.localPath!.split('/').last}', style: const TextStyle(color: Colors.white70, fontSize: 12)));
    }
    final url = resolveMediaUrl(a!.url!);
    if (msg.kind == 'image') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 80, child: Center(child: Icon(Icons.broken_image_outlined))))),
      );
    }
    if (msg.kind == 'video') {
      return GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatVideoScreen(url: url))),
        child: Container(width: 220, height: 120, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44))),
      );
    }
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description_outlined, size: 18), const SizedBox(width: 6), Flexible(child: Text(a.name.isEmpty ? 'Document PDF' : a.name, style: const TextStyle(decoration: TextDecoration.underline)))])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = msg.mine;
    final fg = mine ? Colors.white : TtColors.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: TtSpace.s2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: mine ? TtColors.primary : TtColors.surface,
          border: msg.local == SendState.failed ? Border.all(color: TtColors.danger, width: 2) : (mine ? null : Border.all(color: TtColors.line)),
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 4), bottomRight: Radius.circular(mine ? 4 : 18)),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (msg.statusContext?['status'] != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: (mine ? Colors.white : TtColors.primarySoft).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: mine ? TtColors.accent : TtColors.primary, width: 3))),
                child: Text('Réponse à un statut${(msg.statusContext?['text'] ?? '').toString().isEmpty ? '' : ' : « ${msg.statusContext!['text']} »'}', style: const TextStyle(fontSize: 12)),
              ),
            _attachment(context),
            if (msg.content.isNotEmpty) Text(msg.content, style: TratraTheme.style(TtType.bodySm, color: fg)),
            if (msg.local == SendState.sending && msg.localPath != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: msg.progress == 0 ? null : msg.progress, color: TtColors.accent, backgroundColor: Colors.white24, minHeight: 4)),
            Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(formatWhen(msg.createdAt), style: TratraTheme.style(TtType.caption, color: mine ? Colors.white70 : TtColors.ash).copyWith(fontSize: 10)),
              const SizedBox(width: 4),
              _ticks(),
            ]),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(style: TextButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 10)), onPressed: onRetry, child: const Text('Renvoyer', style: TextStyle(fontSize: 12))),
                  const SizedBox(width: 6),
                  TextButton(onPressed: onDiscard, child: const Text('Supprimer', style: TextStyle(fontSize: 12, color: Colors.white))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
