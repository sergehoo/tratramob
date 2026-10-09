// screens/messaging_screen.dart
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/detail_shared/detail_helpers.dart';

class MessagingScreen extends StatefulWidget {
  final String artisanName;
  final String artisanImage;

  const MessagingScreen({
    super.key,
    required this.artisanName,
    required this.artisanImage,
  });

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Le plus récent en premier (liste inversée). Aucun message fictif au départ.
  final List<Message> _messages = [];

  @override
  void dispose() {
    _messageController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final txt = _messageController.text.trim();
    if (txt.isNotEmpty) {
      setState(() {
        _messages.insert(
            0, Message(text: txt, isMe: true, time: DateTime.now()));
        _messageController.clear();
      });
      _focus.requestFocus();
    }
  }

  String get _name {
    final n = widget.artisanName.trim();
    return n.isEmpty ? 'Artisan' : n;
  }

  /// Avis honnête : la conversation n'est pas encore reliée au serveur.
  Widget _notice() {
    return TratraAlert(
      tone: TratraAlertTone.warning,
      title: 'Messagerie en cours de déploiement',
      message: 'Pour l’instant, les messages écrits ici restent sur cet appareil : '
          'ils ne sont pas transmis à $_name. Pour convenir d’une intervention, '
          'passez par une réservation.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = realImageUrl(widget.artisanImage);

    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: TratraAppBar(
        titleWidget: Row(
          children: [
            TratraAvatar(name: _name, photoUrl: photo, size: 40),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Text(
                _name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.h3),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(TtSpace.s4),
                    children: [
                      _notice(),
                      const SizedBox(height: TtSpace.s6),
                      TratraEmptyState(
                        compact: true,
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Aucun message pour le moment',
                        description: 'Votre conversation avec $_name apparaîtra ici.',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(TtSpace.s4),
                    reverse: true,
                    itemCount: _messages.length + 1,
                    itemBuilder: (context, index) {
                      // Dernier élément d'une liste inversée = tout en haut.
                      if (index == _messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: TtSpace.s4),
                          child: _notice(),
                        );
                      }
                      return _Bubble(
                        message: _messages[index],
                        artisanName: _name,
                        artisanPhoto: photo,
                      );
                    },
                  ),
          ),
          _Composer(
            controller: _messageController,
            focusNode: _focus,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

/// Bulle sobre : envoyé = primaryDark / texte blanc ; reçu = surface / filet.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.artisanName,
    required this.artisanPhoto,
  });

  final Message message;
  final String artisanName;
  final String? artisanPhoto;

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final mine = message.isMe;
    final time = _hhmm(message.time);
    const big = Radius.circular(TtRadius.panel);
    const tail = Radius.circular(TtRadius.sm);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mine ? TtColors.primaryDark : TtColors.surface,
          border: mine ? null : Border.all(color: TtColors.line),
          borderRadius: BorderRadius.only(
            topLeft: big,
            topRight: big,
            bottomLeft: mine ? big : tail,
            bottomRight: mine ? tail : big,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TratraTheme.style(
                  TtType.body,
                  color: mine ? Colors.white : TtColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // Honnêteté : tant que la messagerie n'est pas reliée au serveur,
                // un message envoyé reste local et le dit.
                mine ? '$time · non transmis' : time,
                style: TratraTheme.style(
                  TtType.caption,
                  color: mine ? Colors.white70 : TtColors.ash,
                ).copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: mine
          ? 'Vous : ${message.text}, $time, non transmis'
          : '$artisanName : ${message.text}, $time',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!mine) ...[
                TratraAvatar(name: artisanName, photoUrl: artisanPhoto, size: 28),
                const SizedBox(width: TtSpace.s2),
              ],
              Flexible(child: bubble),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zone de saisie : champ de la marque + bouton d'envoi rond (actif si le texte
/// n'est pas vide).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(top: BorderSide(color: TtColors.lineSoft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(TtSpace.s3),
          child: Row(
            children: [
              Expanded(
                child: TratraInput(
                  controller: controller,
                  focusNode: focusNode,
                  hint: 'Écrivez votre message…',
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: TtSpace.s2),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty;
                  return IconButton.filled(
                    tooltip: 'Envoyer le message',
                    onPressed: canSend ? onSend : null,
                    style: IconButton.styleFrom(
                      backgroundColor: TtColors.primaryDark,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: TtColors.lineSoft,
                      disabledForegroundColor: TtColors.fog,
                      minimumSize: const Size(TtLayout.controlHeight, TtLayout.controlHeight),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 20),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Message {
  final String text;
  final bool isMe;
  final DateTime time;
  Message({required this.text, required this.isMe, required this.time});
}
