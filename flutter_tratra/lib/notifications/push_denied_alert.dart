// lib/notifications/push_denied_alert.dart
//
// Notifications refusées dans le téléphone : Tratra ne peut pas alerter, mais rien n'est perdu — le centre de notifications
// garde tout. Sur Android, un bouton ouvre directement les réglages de notification de Tratra ; au retour dans l'application,
// la permission est relue (PushService.recheck) et le message disparaît de lui-même.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/core/notification_links.dart';
import 'package:flutter_tratra/design/design.dart';

class PushDeniedAlert extends StatelessWidget {
  const PushDeniedAlert({super.key, required this.message});
  final String message;

  Future<void> _openSettings(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await NotificationLinks.openSystemSettings()) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Ouvrez les réglages du téléphone, puis Applications › Tratra › Notifications.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return TratraAlert(
      tone: TratraAlertTone.warning,
      title: 'Notifications désactivées sur ce téléphone',
      message: message,
      action: NotificationLinks.canOpenSystemSettings
          ? TratraButton(
              label: 'Ouvrir les réglages',
              size: TratraButtonSize.sm,
              variant: TratraButtonVariant.outline,
              onPressed: () => _openSettings(context),
            )
          : null,
    );
  }
}
