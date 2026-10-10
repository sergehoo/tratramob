// lib/core/deep_links.dart
//
// Liens profonds des notifications : `tratra://booking/12`, `tratra://mission/12`, `tratra://conversation/5`,
// `tratra://reviews`, `tratra://announcement/3`… Le serveur décrit l'objet à ouvrir ; l'application ne devine rien.
// Une donnée de notification illisible ou inconnue ne plante jamais : elle ouvre simplement le centre de notifications.

/// Type d'objet désigné par un lien profond.
enum DeepLinkKind { booking, mission, conversation, reviews, kyc, businessRequest, announcement, notifications }

class DeepLink {
  const DeepLink(this.kind, {this.id});
  final DeepLinkKind kind;
  final int? id;

  /// Un lien qui exige un identifiant mais n'en porte pas ouvre le centre de notifications.
  bool get needsId => const {DeepLinkKind.booking, DeepLinkKind.mission, DeepLinkKind.conversation}.contains(kind);

  @override
  bool operator ==(Object other) => other is DeepLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'DeepLink($kind, $id)';
}

DeepLinkKind? _kind(String raw) => switch (raw) {
      'booking' => DeepLinkKind.booking,
      'mission' => DeepLinkKind.mission,
      'conversation' => DeepLinkKind.conversation,
      'reviews' => DeepLinkKind.reviews,
      'kyc' => DeepLinkKind.kyc,
      'business_request' => DeepLinkKind.businessRequest,
      'announcement' => DeepLinkKind.announcement,
      'notifications' => DeepLinkKind.notifications,
      _ => null,
    };

/// Interprète la charge utile d'un push ou d'une notification : `deeplink` (chaîne), sinon `kind` + `id`.
/// Toujours un lien exploitable : au pire, le centre de notifications.
DeepLink parseDeepLink(Map<String, dynamic>? data) {
  const fallback = DeepLink(DeepLinkKind.notifications);
  if (data == null || data.isEmpty) return fallback;

  String? kindRaw;
  int? id;
  final link = data['deeplink']?.toString();
  if (link != null && link.startsWith('tratra://')) {
    final uri = Uri.tryParse(link);
    if (uri != null) {
      kindRaw = uri.host;
      id = uri.pathSegments.isNotEmpty ? int.tryParse(uri.pathSegments.first) : null;
    }
  }
  kindRaw ??= data['kind']?.toString();
  id ??= int.tryParse('${data['id'] ?? ''}');

  final kind = kindRaw == null ? null : _kind(kindRaw);
  if (kind == null) return fallback;
  final parsed = DeepLink(kind, id: id);
  return parsed.needsId && id == null ? fallback : parsed;
}
