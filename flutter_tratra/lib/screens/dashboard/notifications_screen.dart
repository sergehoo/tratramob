// lib/screens/dashboard/notifications_screen.dart
//
// « Notifications » : GET /notifications/, PATCH is_read, POST /me/notifications/read-all/.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;
  bool _busy = false;

  void _refresh() {
    context.read<DashboardController>().load();
    setState(() => _version++);
  }

  Future<void> _markAll() async {
    setState(() => _busy = true);
    try {
      await _api.post('/me/notifications/read-all/');
      _refresh();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'L’opération a échoué.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markOne(Map<String, dynamic> n) async {
    if (n['is_read'] == true) return;
    try {
      await _api.patch('/notifications/${n['id']}/', {'is_read': true});
      if (mounted) _refresh();
    } catch (_) {
      // non bloquant : l'état se resynchronise au prochain chargement
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<DashboardController>().data?.unreadNotifications ?? 0;
    return DashPage(
      title: 'Notifications',
      actions: [
        if (unread > 0)
          TextButton(onPressed: _busy ? null : _markAll, child: const Text('Tout marquer lu')),
      ],
      body: ApiView<List<Map<String, dynamic>>>(
        key: ValueKey('notifs-$_version'),
        errorTitle: 'Notifications indisponibles',
        load: () => _api.getList('/notifications/?ordering=-created_at&page_size=50'),
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
              SizedBox(
                height: 420,
                child: TratraEmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Aucune notification',
                  description: 'Vous serez prévenu ici dès qu’il se passe quelque chose sur vos réservations ou vos missions.',
                ),
              ),
            ]);
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
            itemBuilder: (_, i) {
              final n = items[i];
              final read = n['is_read'] == true;
              final date = DateTime.tryParse('${n['created_at'] ?? ''}');
              return TratraCard(
                variant: read ? TratraCardVariant.standard : TratraCardVariant.soft,
                padding: TratraCard.compact,
                onTap: read ? null : () => _markOne(n),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: read ? TtColors.lineSoft : TtColors.primarySoft,
                      borderRadius: BorderRadius.circular(TtRadius.control),
                    ),
                    child: Icon(Icons.notifications_none_rounded, color: read ? TtColors.ash : TtColors.primary),
                  ),
                  const SizedBox(width: TtSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${n['message'] ?? ''}',
                          style: TratraTheme.style(TtType.bodySm, color: read ? TtColors.inkSoft : TtColors.ink)
                              .copyWith(fontWeight: read ? FontWeight.w400 : FontWeight.w600)),
                      if (date != null) Text(formatWhen(date), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
