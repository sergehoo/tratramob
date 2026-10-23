// lib/core/deep_links.dart
//
// Liens profonds des notifications et des annonces : `tratra://booking/12`, `tratra://service/40`, `tratra://reputation`… Le serveur décrit
// l'objet à ouvrir ; l'application ne devine rien. Même liste que le registre central du serveur (handy/destinations.py) : une clé
// ajoutée d'un côté doit l'être de l'autre (tests : test/deep_links_test.dart et announcements/test_destinations_push.py).
// Une donnée de notification illisible ou inconnue ne plante jamais : elle ouvre simplement le centre de notifications. Un écran réservé
// à un rôle (professionnel, entreprise) n'est jamais affiché à un autre compte (voir [requiredRole] et openDeepLink).

import 'package:flutter/foundation.dart';

/// Type d'objet désigné par un lien profond.
enum DeepLinkKind {
  booking, mission, conversation, reviews, kyc, businessRequest, announcement, contract, posting, replacements, notifications,
  // Destinations des raccourcis d'application et du widget d'accueil (sans identifiant).
  explore, bookings, messages, pro,
  // Tratra Flash : proposition de mission (pro), demande (client), disponibilité ; décision Tratra Trust.
  flashOffer, flashRequest, availability, trustPenalty,
  // Destinations des annonces (registre central) : découvrir, commander, compte, espace professionnel, entreprises.
  home, categories, category, services, service, search, urgent, flashOrder, favorites, profile, addresses, reputation, badge,
  engagements, business,
}

/// Rôle exigé par un écran : un compte qui ne l'a pas est ramené à l'accueil avec un message, jamais sur la page.
enum LinkRole { provider, business }

LinkRole? requiredRole(DeepLinkKind kind) => switch (kind) {
      DeepLinkKind.mission || DeepLinkKind.availability || DeepLinkKind.flashOffer || DeepLinkKind.reputation || DeepLinkKind.badge ||
      DeepLinkKind.replacements || DeepLinkKind.trustPenalty =>
        LinkRole.provider,
      DeepLinkKind.business || DeepLinkKind.businessRequest => LinkRole.business,
      _ => null,
    };

/// Onglet de l'espace à afficher (0 accueil, 1 explorer, 2 réservations, 3 messages) : demandé par un raccourci ou le widget,
/// appliqué par l'écran principal dès qu'il est prêt (y compris au lancement à froid).
final ValueNotifier<int?> dashboardTabRequest = ValueNotifier<int?>(null);

/// Liens qui exigent un compte connecté (sinon : écran de connexion).
bool requiresSignIn(DeepLink link) => link.kind != DeepLinkKind.explore;

class DeepLink {
  const DeepLink(this.kind, {this.id});
  final DeepLinkKind kind;
  final int? id;

  /// Un lien qui exige un identifiant mais n'en porte pas ouvre le centre de notifications.
  bool get needsId => const {DeepLinkKind.booking, DeepLinkKind.mission, DeepLinkKind.conversation, DeepLinkKind.contract, DeepLinkKind.posting,
        DeepLinkKind.flashOffer, DeepLinkKind.flashRequest, DeepLinkKind.category, DeepLinkKind.service}.contains(kind);

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
      'contract' => DeepLinkKind.contract,
      'posting' => DeepLinkKind.posting,
      'replacements' => DeepLinkKind.replacements,
      'notifications' => DeepLinkKind.notifications,
      'explore' => DeepLinkKind.explore,
      'bookings' => DeepLinkKind.bookings,
      'messages' => DeepLinkKind.messages,
      'pro' => DeepLinkKind.pro,
      'flash_offer' => DeepLinkKind.flashOffer,
      'flash_request' => DeepLinkKind.flashRequest,
      'availability' => DeepLinkKind.availability,
      'trust_penalty' => DeepLinkKind.trustPenalty,
      'home' => DeepLinkKind.home,
      'categories' => DeepLinkKind.categories,
      'category' => DeepLinkKind.category,
      'services' => DeepLinkKind.services,
      'service' => DeepLinkKind.service,
      'search' => DeepLinkKind.search,
      'urgent' => DeepLinkKind.urgent,
      'flash_order' => DeepLinkKind.flashOrder,
      'favorites' => DeepLinkKind.favorites,
      'profile' => DeepLinkKind.profile,
      'addresses' => DeepLinkKind.addresses,
      'reputation' => DeepLinkKind.reputation,
      'badge' => DeepLinkKind.badge,
      'engagements' => DeepLinkKind.engagements,
      'business' => DeepLinkKind.business,
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

/// Clés `tratra://` reconnues (même liste que le registre central du serveur).
const Set<String> knownLinkKeys = {
  'booking', 'mission', 'conversation', 'reviews', 'kyc', 'business_request', 'announcement', 'contract', 'posting', 'replacements',
  'notifications', 'explore', 'bookings', 'messages', 'pro', 'flash_offer', 'flash_request', 'availability', 'trust_penalty', 'home',
  'categories', 'category', 'services', 'service', 'search', 'urgent', 'flash_order', 'favorites', 'profile', 'addresses', 'reputation',
  'badge', 'engagements', 'business',
};
