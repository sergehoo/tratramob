// lib/screens/dashboard/messages_screen.dart
//
// Messagerie par réservation (GET/POST /me/conversations/, /me/conversations/<id>/messages/).
// Les messages envoyés passent par POST /messages/ ; le serveur impose l'expéditeur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class ConversationSummary {
  ConversationSummary(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        counterpart = '${j['counterpart'] ?? 'Membre Tratra'}',
        lastMessage = j['last_message'] == null ? null : '${j['last_message']}',
        lastAt = DateTime.tryParse('${j['last_at'] ?? ''}'),
        unread = ((j['unread'] ?? 0) as num).toInt();
  final int id;
  final String counterpart;
  final String? lastMessage;
  final DateTime? lastAt;
  final int unread;
}

/// Ouvre (ou crée) la conversation d'une réservation puis affiche le fil.
Future<void> openBookingConversation(BuildContext context, int bookingId) async {
  final api = context.read<DashboardApi>();
  try {
    final r = await api.post('/me/conversations/', {'booking': bookingId});
    final id = (r['id'] as num).toInt();
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: id, title: 'Conversation')));
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e, 'La conversation n’a pas pu être ouverte.'), error: true);
  }
}

class MessagesList extends StatelessWidget {
  const MessagesList({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<DashboardApi>();
    return ApiView<List<ConversationSummary>>(
      errorTitle: 'Messagerie indisponible',
      load: () async => (await api.getList('/me/conversations/')).map(ConversationSummary.new).toList(),
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
            SizedBox(
              height: 420,
              child: TratraEmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Aucune conversation',
                description: 'Ouvrez une réservation pour écrire à l’artisan ou au client concerné.',
              ),
            ),
          ]);
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
          itemBuilder: (_, i) {
            final c = items[i];
            return TratraCard(
              padding: TratraCard.compact,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ConversationScreen(conversationId: c.id, title: c.counterpart),
                ));
                await reload();
                if (context.mounted) context.read<DashboardController>().load();
              },
              child: Row(children: [
                TratraAvatar(name: c.counterpart, size: 44),
                const SizedBox(width: TtSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(c.counterpart, maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title))),
                      if (c.lastAt != null) Text(formatWhen(c.lastAt!), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    ]),
                    Text(c.lastMessage ?? 'Aucun message pour le moment',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.bodySm, color: c.unread > 0 ? TtColors.ink : TtColors.ash)),
                  ]),
                ),
                if (c.unread > 0) ...[
                  const SizedBox(width: TtSpace.s2),
                  CircleAvatar(radius: 11, backgroundColor: TtColors.primary, child: Text('${c.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                ],
              ]),
            );
          },
        );
      },
    );
  }
}

class _Msg {
  _Msg(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        mine = j['mine'] == true,
        content = '${j['content'] ?? ''}',
        createdAt = DateTime.tryParse('${j['created_at'] ?? ''}'),
        isRead = j['is_read'] == true;
  final int id;
  final bool mine;
  final String content;
  final DateTime? createdAt;
  final bool isRead;
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, required this.title});
  final int conversationId;
  final String title;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<_Msg>? _messages;
  String _title = '';
  String? _error;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.getMap('/me/conversations/${widget.conversationId}/messages/');
      final list = ((r['results'] as List?) ?? const []).whereType<Map>().map((e) => _Msg(e.cast<String, dynamic>())).toList();
      final conv = r['conversation'];
      if (!mounted) return;
      final grew = (_messages?.length ?? 0) != list.length;
      setState(() {
        _messages = list;
        _error = null;
        if (conv is Map && conv['counterpart'] != null) _title = '${conv['counterpart']}';
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
      if (list.any((m) => !m.mine && !m.isRead)) {
        await _api.post('/me/conversations/${widget.conversationId}/messages/');
      }
    } catch (e) {
      if (mounted && _messages == null) setState(() => _error = friendlyError(e, 'Cette conversation ne peut pas être chargée.'));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final uid = int.tryParse(context.read<Session>().user?.id ?? '');
    if (text.isEmpty || uid == null || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.post('/messages/', {'conversation': widget.conversationId, 'sender': uid, 'content': text});
      _input.clear();
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le message n’a pas pu être envoyé.'), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _messages;
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(title: _title),
      body: Column(children: [
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
                          itemCount: msgs.length,
                          itemBuilder: (_, i) => _Bubble(msg: msgs[i]),
                        ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(TtSpace.s3, TtSpace.s2, TtSpace.s3, TtSpace.s2),
            decoration: const BoxDecoration(color: TtColors.surface, border: Border(top: BorderSide(color: TtColors.lineSoft))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TratraInput(
                  controller: _input,
                  hint: 'Votre message…',
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: TtSpace.s2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TratraButton(label: 'Envoyer', loading: _sending, leading: const Icon(Icons.send_rounded, size: 18), onPressed: _send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;
  @override
  Widget build(BuildContext context) {
    final mine = msg.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: TtSpace.s2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: mine ? TtColors.primary : TtColors.surface,
          border: mine ? null : Border.all(color: TtColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.content, style: TratraTheme.style(TtType.bodySm, color: mine ? Colors.white : TtColors.ink)),
          if (msg.createdAt != null)
            Text(formatWhen(msg.createdAt!), style: TratraTheme.style(TtType.caption, color: mine ? Colors.white70 : TtColors.ash).copyWith(fontSize: 10)),
        ]),
      ),
    );
  }
}
