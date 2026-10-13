// lib/statuses/status_models.dart
//
// Statuts éphémères (mêmes charges utiles que le web) : élément, auteur, groupe par auteur, limites, fil et lecteurs.
import 'package:flutter/material.dart';

class StatusMedia {
  StatusMedia.fromJson(Map<String, dynamic> j)
      : url = j['url'] == null ? null : '${j['url']}',
        mime = '${j['mime'] ?? ''}',
        duration = (j['duration'] as num?)?.toDouble();
  final String? url;
  final String mime;
  final double? duration;
}

class StatusItem {
  StatusItem.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        type = '${j['type'] ?? 'text'}',
        kind = '${j['kind'] ?? 'text'}',
        text = '${j['text'] ?? ''}',
        background = j['background'] == null ? null : '${j['background']}',
        media = j['media'] is Map ? StatusMedia.fromJson((j['media'] as Map).cast<String, dynamic>()) : null,
        createdAt = DateTime.tryParse('${j['created_at'] ?? ''}') ?? DateTime.now(),
        expiresAt = DateTime.tryParse('${j['expires_at'] ?? ''}') ?? DateTime.now(),
        audience = j['audience'] == null ? null : '${j['audience']}',
        allowReplies = j['allow_replies'] == true,
        mine = j['mine'] == true,
        seen = j['seen'] == true,
        viewsUnique = (j['views'] is Map ? ((j['views'] as Map)['unique'] as num?)?.toInt() : null) ?? 0,
        viewsTotal = (j['views'] is Map ? ((j['views'] as Map)['total'] as num?)?.toInt() : null) ?? 0;
  final int id;
  final String type; // text | photo | video | text_media
  final String kind; // text | photo | video
  final String text;
  final String? background;
  final StatusMedia? media;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? audience;
  final bool allowReplies;
  final bool mine;
  final bool seen;
  final int viewsUnique;
  final int viewsTotal;

  /// Temps restant lisible (« 23 h », « 12 min »).
  String get timeLeft {
    final d = expiresAt.difference(DateTime.now());
    if (d.isNegative) return 'expiré';
    return d.inHours >= 1 ? '${d.inHours} h' : '${d.inMinutes.clamp(1, 59)} min';
  }
}

class StatusAuthor {
  StatusAuthor.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = '${j['name'] ?? 'Membre Tratra'}',
        avatar = j['avatar'] == null ? null : '${j['avatar']}';
  final int id;
  final String name;
  final String? avatar;
}

class StatusGroup {
  StatusGroup({required this.author, required this.statuses, required this.unseen});
  StatusGroup.fromJson(Map<String, dynamic> j)
      : author = StatusAuthor.fromJson((j['author'] as Map).cast<String, dynamic>()),
        statuses = ((j['statuses'] as List?) ?? const []).whereType<Map>().map((e) => StatusItem.fromJson(e.cast<String, dynamic>())).toList(),
        unseen = ((j['unseen'] ?? 0) as num).toInt();
  final StatusAuthor author;
  final List<StatusItem> statuses;
  final int unseen;
  bool get seen => unseen == 0;
}

class StatusLimits {
  StatusLimits.fromJson(Map<String, dynamic> j)
      : ttlHours = ((j['ttl_hours'] ?? 24) as num).toInt(),
        textMax = ((j['text_max'] ?? 700) as num).toInt(),
        videoMaxSeconds = ((j['video_max_seconds'] ?? 30) as num).toInt(),
        imageMaxBytes = ((j['image_max_bytes'] ?? 10485760) as num).toInt(),
        videoMaxBytes = ((j['video_max_bytes'] ?? 31457280) as num).toInt();
  final int ttlHours;
  final int textMax;
  final int videoMaxSeconds;
  final int imageMaxBytes;
  final int videoMaxBytes;
}

class StatusFeed {
  StatusFeed.fromJson(Map<String, dynamic> j)
      : mine = StatusGroup.fromJson((j['mine'] as Map).cast<String, dynamic>()),
        contacts = ((j['contacts'] as List?) ?? const []).whereType<Map>().map((e) => StatusGroup.fromJson(e.cast<String, dynamic>())).toList(),
        discoverCount = ((j['discover_count'] ?? 0) as num).toInt(),
        limits = StatusLimits.fromJson(((j['limits'] as Map?) ?? const {}).cast<String, dynamic>());
  final StatusGroup mine;
  final List<StatusGroup> contacts;
  final int discoverCount;
  final StatusLimits limits;
}

class StatusReader {
  StatusReader.fromJson(Map<String, dynamic> j)
      : user = StatusAuthor.fromJson((j['user'] as Map).cast<String, dynamic>()),
        viewedAt = DateTime.tryParse('${j['viewed_at'] ?? ''}'),
        count = (j['count'] as num?)?.toInt();
  final StatusAuthor user;
  final DateTime? viewedAt;
  final int? count;
}

/// Couleurs de fond d'un statut texte (clés envoyées au serveur).
const statusBackgrounds = <String, ({Color bg, Color fg, String label})>{
  'green': (bg: Color(0xFF2E8B57), fg: Colors.white, label: 'Vert'),
  'yellow': (bg: Color(0xFFF5C400), fg: Color(0xFF111111), label: 'Jaune'),
  'night': (bg: Color(0xFF10201A), fg: Colors.white, label: 'Nuit'),
  'sky': (bg: Color(0xFF2B6CB0), fg: Colors.white, label: 'Bleu'),
  'rose': (bg: Color(0xFFC2410C), fg: Colors.white, label: 'Orange'),
  'violet': (bg: Color(0xFF6B46C1), fg: Colors.white, label: 'Violet'),
};
