// lib/core/notification_links.dart
//
// Notifications construites par l'application Android (annonces avec grande image, logo et bouton d'action) : quand on touche la
// notification ou son bouton, l'activité transmet le lien `tratra://…` (canal « tratra/links »). Lancement à froid : le lien est gardé
// côté Android jusqu'à ce que Dart le demande (takeLaunchLink), puis remis une seule fois. Seuls les liens `tratra://` sont acceptés ;
// la destination est ensuite vérifiée (session, rôle) par l'application comme pour toute notification.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationTap {
  const NotificationTap(this.link, {this.announcementId, this.notificationId});
  final String link;
  final int? announcementId;

  /// Notification du centre de notifications à marquer lue (quand le serveur l'a fournie).
  final int? notificationId;

  static NotificationTap? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final link = '${raw['link'] ?? ''}'.trim();
    if (!RegExp(r'^tratra://[a-z_]+(/[0-9]+)?$').hasMatch(link)) return null;
    final id = int.tryParse('${raw['announcement'] ?? ''}');
    final nid = int.tryParse('${raw['nid'] ?? ''}');
    return NotificationTap(link, announcementId: id != null && id > 0 ? id : null, notificationId: nid != null && nid > 0 ? nid : null);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationTap && other.link == link && other.announcementId == announcementId && other.notificationId == notificationId;

  @override
  int get hashCode => Object.hash(link, announcementId, notificationId);
}

class NotificationLinks {
  NotificationLinks._();
  static const MethodChannel _channel = MethodChannel('tratra/links');

  /// À appeler une fois l'application prête (navigation construite) : remet le lien de lancement puis écoute les suivants.
  static Future<void> start(void Function(NotificationTap tap) onTap) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final tap = NotificationTap.fromMap(call.arguments);
        if (tap != null) onTap(tap);
      }
      return null;
    });
    try {
      final tap = NotificationTap.fromMap(await _channel.invokeMethod<Object?>('takeLaunchLink'));
      if (tap != null) onTap(tap);
    } catch (_) {
      // plateforme sans canal (tests) : rien à remettre
    }
  }

  /// Le téléphone sait ouvrir directement les réglages de notification de Tratra (Android).
  static bool get canOpenSystemSettings => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Ouvre les réglages de notification de Tratra dans le téléphone. Faux si rien n'a pu être ouvert.
  static Future<bool> openSystemSettings() async {
    if (!canOpenSystemSettings) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
