// lib/core/announcement_action.dart
//
// Action d'une annonce (bouton « Voir »…) : le serveur la valide déjà, l'application la revérifie avant d'agir.
//  * lien externe : https uniquement (jamais javascript:, http:, intent:, ni schéma d'une autre application) ;
//  * écran de l'application : uniquement les destinations connues de [parseDeepLink].
// Une action illisible est ignorée (aucun bouton), jamais exécutée à l'aveugle.
import 'package:flutter_tratra/core/deep_links.dart';

sealed class AnnouncementAction {
  const AnnouncementAction(this.label);
  final String label;
}

class OpenExternalLink extends AnnouncementAction {
  const OpenExternalLink(this.uri, super.label);
  final Uri uri;
}

class OpenAppScreen extends AnnouncementAction {
  const OpenAppScreen(this.link, super.label);
  final DeepLink link;
}

/// `action` tel que renvoyé par `GET /me/announcements/` : `{kind, label, value}` ou null.
AnnouncementAction? parseAnnouncementAction(Map<String, dynamic>? action) {
  if (action == null) return null;
  final kind = '${action['kind'] ?? ''}';
  final value = '${action['value'] ?? ''}'.trim();
  final raw = '${action['label'] ?? ''}'.trim();
  final label = raw.isEmpty ? 'Voir' : raw;
  if (value.isEmpty) return null;

  if (kind == 'link') {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return OpenExternalLink(uri, label);
  }
  if (kind == 'deeplink') {
    final link = parseDeepLink({'deeplink': 'tratra://$value'});
    // parseDeepLink retombe sur le centre de notifications pour tout lien inconnu : ce n'est pas la destination demandée.
    if (link.kind == DeepLinkKind.notifications && !value.startsWith('notifications')) return null;
    return OpenAppScreen(link, label);
  }
  return null;
}
