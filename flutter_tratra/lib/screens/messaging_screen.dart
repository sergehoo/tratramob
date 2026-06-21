// screens/messaging_screen.dart
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../widgets/custom_app_bar.dart';

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
  final List<Message> _messages = [
    Message(
      text: 'Bonjour, je suis intéressé par vos services de plomberie.',
      isMe: true,
      time: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
    Message(
      text:
          'Bonjour ! Je serais ravi de vous aider. Pouvez-vous me décrire le problème ?',
      isMe: false,
      time: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  void _sendMessage() {
    final txt = _messageController.text.trim();
    if (txt.isNotEmpty) {
      setState(() {
        _messages.insert(
            0, Message(text: txt, isMe: true, time: DateTime.now()));
        _messageController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: CustomAppBar(
        title: widget.artisanName,
        showBackButton: true,
        leading:
            CircleAvatar(backgroundImage: NetworkImage(widget.artisanImage)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                  _buildMessageBubble(_messages[index]),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: AppConstants.cardColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Tapez votre message...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isMe)
            CircleAvatar(
                radius: 16, backgroundImage: NetworkImage(widget.artisanImage)),
          if (!message.isMe) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isMe
                    ? AppConstants.primaryColor
                    : AppConstants.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1))
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                    color:
                        message.isMe ? Colors.white : AppConstants.textPrimary),
              ),
            ),
          ),
        ],
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
