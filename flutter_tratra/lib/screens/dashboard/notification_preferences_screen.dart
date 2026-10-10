// lib/screens/dashboard/notification_preferences_screen.dart
//
// Préférences de notification par catégorie (GET/PUT /me/notification-preferences/) et consentement aux
// communications promotionnelles (PUT /me/marketing-consent/). Le serveur est l'autorité : l'interface n'affiche
// un changement qu'après sa confirmation. L'autorisation système (Android 13+, iOS) reste le choix de l'utilisateur
// dans les réglages du téléphone : l'application ne la contourne jamais.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/notifications_screen.dart' show notificationIcon;
import 'package:flutter_tratra/services/push_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;
  bool _busy = false;

  Future<void> _setPush(String category, bool enabled) async {
    setState(() => _busy = true);
    try {
      await _api.put('/me/notification-preferences/', {'preferences': {category: enabled}});
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le réglage n’a pas pu être enregistré.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setMarketing(bool granted) async {
    setState(() => _busy = true);
    try {
      await _api.put('/me/marketing-consent/', {'granted': granted, 'source': 'app'});
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le choix n’a pas pu être enregistré.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pushStatus = context.watch<PushService>().status;
    return DashPage(
      title: 'Préférences de notification',
      body: ApiView<Map<String, dynamic>>(
        key: ValueKey('prefs-$_version'),
        errorTitle: 'Préférences indisponibles',
        load: () => _api.getMap('/me/notification-preferences/'),
        builder: (context, data, reload) {
          final prefs = ((data['preferences'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          final consent = (data['marketing_consent'] as Map?)?.cast<String, dynamic>() ?? const {};
          return ListView(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
            children: [
              if (pushStatus == PushStatus.denied)
                const Padding(
                  padding: EdgeInsets.only(bottom: TtSpace.s3),
                  child: TratraAlert(
                    tone: TratraAlertTone.warning,
                    message: 'Les notifications sont désactivées dans les réglages de votre téléphone : vous ne recevrez pas d’alerte même si elles sont activées ici.',
                  ),
                ),
              Text('Choisissez les alertes que vous souhaitez recevoir sur vos appareils. L’historique reste disponible dans l’application.',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              const SizedBox(height: TtSpace.s3),
              TratraCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < prefs.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    SwitchListTile(
                      secondary: Icon(notificationIcon('${prefs[i]['category']}'), color: TtColors.primary),
                      title: Text('${prefs[i]['label']}'),
                      subtitle: prefs[i]['locked'] == true ? const Text('Toujours actif : sécurité et vérification de votre compte') : null,
                      value: prefs[i]['push_enabled'] == true,
                      onChanged: prefs[i]['locked'] == true || _busy ? null : (v) => _setPush('${prefs[i]['category']}', v),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Offres et annonces promotionnelles', style: TratraTheme.style(TtType.h3)),
                  const SizedBox(height: TtSpace.s2),
                  Text(
                    'Tratra n’envoie aucune communication promotionnelle sans votre accord. Les informations de service '
                    '(réservations, sécurité, changements importants) ne dépendent pas de ce choix. Vous pouvez retirer votre accord à tout moment.',
                    style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('J’accepte de recevoir des offres et annonces promotionnelles'),
                    value: consent['granted'] == true,
                    onChanged: _busy ? null : _setMarketing,
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
