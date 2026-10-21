// lib/screens/dashboard/notifications_screen.dart
//
// Centre de notifications : historique persistant du serveur (GET /notifications/), filtres par catégorie, compteur de
// non lues, lecture (PATCH / POST mark-read), navigation vers l'objet concerné (lien profond) et accès aux préférences.
// Les mêmes données alimentent le Web et l'API : lu sur un appareil = lu partout.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/continuity/offline_queue.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/notification_preferences_screen.dart';

/// Catégories du serveur (code → libellé, icône).
const List<(String, String, IconData)> notificationCategories = [
  ('booking', 'Réservations', Icons.event_available_outlined),
  ('message', 'Messages', Icons.chat_bubble_outline_rounded),
  ('payment', 'Paiements', Icons.payments_outlined),
  ('live', 'Suivi', Icons.my_location_rounded),
  ('review', 'Avis', Icons.star_outline_rounded),
  ('account', 'Compte', Icons.verified_user_outlined),
  ('business', 'Entreprise', Icons.business_center_outlined),
  ('engagement', 'Contrats et engagements', Icons.description_outlined),
  ('flash', 'Nouvelles missions', Icons.bolt_rounded),
  ('announcement', 'Annonces', Icons.campaign_outlined),
  ('system', 'Infos', Icons.info_outline_rounded),
];

IconData notificationIcon(String category) =>
    notificationCategories.firstWhere((c) => c.$1 == category, orElse: () => notificationCategories.last).$3;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsPage {
  _NotificationsPage(this.items, this.unread, this.byCategory);
  final List<Map<String, dynamic>> items;
  final int unread;
  final Map<String, int> byCategory;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  String? _category;
  int _version = 0;
  bool _busy = false;

  Future<_NotificationsPage> _load() async {
    final query = '?ordering=-created_at&page_size=50${_category == null ? '' : '&category=$_category'}';
    final items = await _api.getList('/notifications/$query');
    final counts = await _api.getMap('/notifications/unread-count/');
    final by = <String, int>{};
    (counts['by_category'] as Map? ?? {}).forEach((k, v) => by['$k'] = (v as num).toInt());
    return _NotificationsPage(items, (counts['unread'] as num?)?.toInt() ?? 0, by);
  }

  void _refresh() {
    context.read<DashboardController>().load(); // compteur de l'accueil et pastille de la cloche
    setState(() => _version++);
  }

  Future<void> _markAll() async {
    setState(() => _busy = true);
    try {
      await _api.post('/notifications/mark-read/', _category == null ? {} : {'category': _category});
      _refresh();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'L’opération a échoué.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final nav = Navigator.of(context);
    if (n['is_read'] != true) {
      // Accusé de lecture : action sûre, persistée dans la file hors ligne et rejouée au retour du réseau. La navigation
      // n'attend pas le serveur ; les compteurs se rechargent une fois l'accusé envoyé.
      unawaited(context.read<OfflineQueue>().enqueue('PATCH', '/notifications/${n['id']}/', {'is_read': true}).then((_) {
        if (mounted) _refresh();
      }).catchError((_) {}));
    }
    if (!mounted) return;
    final data = Map<String, dynamic>.from((n['data'] as Map?) ?? {});
    final link = parseDeepLink({...data, 'deeplink': n['deeplink']});
    if (link.kind == DeepLinkKind.notifications) return; // aucune cible : la notification reste simplement lue
    await openDeepLink(nav.context, link);
  }

  @override
  Widget build(BuildContext context) {
    return DashPage(
      title: 'Notifications',
      actions: [
        IconButton(
          tooltip: 'Préférences de notification',
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => pushPage(context, const NotificationPreferencesScreen()),
        ),
      ],
      body: ApiView<_NotificationsPage>(
        key: ValueKey('notifs-$_version-$_category'),
        errorTitle: 'Notifications indisponibles',
        load: _load,
        builder: (context, page, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: TtSpace.s2),
                      child: TratraChip(
                          label: page.unread > 0 && _category == null ? 'Toutes (${page.unread})' : 'Toutes',
                          selected: _category == null,
                          onTap: () => setState(() => _category = null)),
                    ),
                    for (final c in notificationCategories)
                      Padding(
                        padding: const EdgeInsets.only(right: TtSpace.s2),
                        child: TratraChip(
                          label: (page.byCategory[c.$1] ?? 0) > 0 ? '${c.$2} (${page.byCategory[c.$1]})' : c.$2,
                          icon: c.$3,
                          selected: _category == c.$1,
                          onTap: () => setState(() => _category = c.$1),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: TtSpace.s3),
              if (page.unread > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _busy ? null : _markAll, child: Text(_category == null ? 'Tout marquer lu' : 'Marquer cette catégorie comme lue')),
                ),
              if (page.items.isEmpty)
                const SizedBox(
                  height: 360,
                  child: TratraEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Aucune notification',
                    description: 'Vous serez prévenu ici dès qu’il se passe quelque chose sur vos réservations, missions ou messages.',
                  ),
                ),
              for (final n in page.items)
                Padding(padding: const EdgeInsets.only(bottom: TtSpace.s2), child: _NotificationTile(n: n, onTap: () => _open(n))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final Map<String, dynamic> n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final read = n['is_read'] == true;
    final date = DateTime.tryParse('${n['created_at'] ?? ''}');
    final title = '${n['title'] ?? ''}';
    return TratraCard(
      variant: read ? TratraCardVariant.standard : TratraCardVariant.soft,
      padding: TratraCard.compact,
      onTap: onTap,
      semanticLabel: '${read ? '' : 'Non lue : '}$title ${n['message'] ?? ''}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: read ? TtColors.lineSoft : TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)),
          child: Icon(notificationIcon('${n['category']}'), color: read ? TtColors.ash : TtColors.primary),
        ),
        const SizedBox(width: TtSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title.isNotEmpty)
              Text(title, style: TratraTheme.style(TtType.bodySm, color: read ? TtColors.inkSoft : TtColors.ink).copyWith(fontWeight: FontWeight.w700)),
            Text('${n['message'] ?? ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.bodySm, color: read ? TtColors.inkSoft : TtColors.ink).copyWith(fontWeight: read ? FontWeight.w400 : FontWeight.w500)),
            if (date != null) Text(formatWhen(date), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ]),
        ),
        if (!read)
          Container(margin: const EdgeInsets.only(left: TtSpace.s2, top: 6), width: 10, height: 10, decoration: const BoxDecoration(color: TtColors.accent, shape: BoxShape.circle)),
      ]),
    );
  }
}
