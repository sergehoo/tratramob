// lib/messaging/chat_models.dart
//
// Modèles de la messagerie (mêmes charges utiles que le web) : conversation, message, pièce jointe, états d'envoi.
// Un message « local » (en cours d'envoi ou en échec) garde son `clientId` : le renvoyer ne crée jamais de doublon côté serveur.

enum SendState { sending, failed }

class ChatAttachment {
  ChatAttachment.fromJson(Map<String, dynamic> j)
      : url = j['url'] == null ? null : '${j['url']}',
        kind = '${j['kind'] ?? 'file'}',
        mime = '${j['mime'] ?? ''}',
        size = ((j['size'] ?? 0) as num).toInt(),
        name = '${j['name'] ?? ''}',
        duration = (j['duration'] as num?)?.toDouble();
  final String? url;
  final String kind;
  final String mime;
  final int size;
  final String name;
  final double? duration;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversation,
    required this.mine,
    required this.content,
    required this.kind,
    required this.createdAt,
    this.state = 'sent',
    this.clientId,
    this.sender = '',
    this.viaStaff = false,
    this.attachment,
    this.statusContext,
    this.local,
    this.localPath,
    this.progress = 0,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] as num).toInt(),
        conversation: (j['conversation'] as num?)?.toInt() ?? 0,
        mine: j['mine'] == true,
        content: '${j['content'] ?? ''}',
        kind: '${j['kind'] ?? 'text'}',
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}') ?? DateTime.now(),
        state: '${j['state'] ?? 'sent'}',
        clientId: j['client_id'] == null ? null : '${j['client_id']}',
        sender: '${j['sender'] ?? ''}',
        viaStaff: j['via_staff'] == true,
        attachment: j['attachment'] is Map ? ChatAttachment.fromJson((j['attachment'] as Map).cast<String, dynamic>()) : null,
        statusContext: j['context'] is Map ? (j['context'] as Map).cast<String, dynamic>() : null,
      );

  final int id;
  final int conversation;
  final bool mine;
  final String content;
  final String kind; // text | image | video | file
  final DateTime createdAt;
  final String state; // sent | delivered | read
  final String? clientId;
  final String sender;
  final bool viaStaff;
  final ChatAttachment? attachment;
  final Map<String, dynamic>? statusContext;
  final SendState? local;
  final String? localPath;
  final double progress;

  ChatMessage copyWith({String? state, SendState? local, bool clearLocal = false, double? progress}) => ChatMessage(
        id: id,
        conversation: conversation,
        mine: mine,
        content: content,
        kind: kind,
        createdAt: createdAt,
        state: state ?? this.state,
        clientId: clientId,
        sender: sender,
        viaStaff: viaStaff,
        attachment: attachment,
        statusContext: statusContext,
        local: clearLocal ? null : (local ?? this.local),
        localPath: localPath,
        progress: progress ?? this.progress,
      );
}

class ChatConversation {
  ChatConversation.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        kind = '${j['kind'] ?? 'booking'}',
        bookingId = (j['booking_id'] as num?)?.toInt(),
        counterpart = '${j['counterpart'] ?? 'Membre Tratra'}',
        counterpartId = (j['counterpart_id'] as num?)?.toInt(),
        lastMessage = j['last_message'] == null ? null : '${j['last_message']}',
        lastAt = DateTime.tryParse('${j['last_at'] ?? ''}'),
        unread = ((j['unread'] ?? 0) as num).toInt(),
        blocked = j['blocked'] == true,
        canSend = j['can_send'] != false;
  final int id;
  final String kind; // booking | direct | support
  final int? bookingId;
  final String counterpart;
  final int? counterpartId;
  final String? lastMessage;
  final DateTime? lastAt;
  final int unread;
  final bool blocked;
  final bool canSend;

  bool get isSupport => kind == 'support';
}
