// lib/screens/dashboard/bookings_screen.dart
//
// « Mes réservations » : uniquement celles que le compte a faites en tant que CLIENT
// (`/bookings/?client=<id>` — l'API renvoie aussi les missions d'un compte artisan).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class BookingsList extends StatelessWidget {
  const BookingsList({super.key, this.onExplore});
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    final api = context.read<DashboardApi>();
    final uid = context.read<Session>().user?.id ?? '';
    return ApiView<List<DashItem>>(
      errorTitle: 'Réservations indisponibles',
      load: () async {
        final rows = await api.getList('/bookings/?client=$uid&ordering=-created_at&page_size=50');
        return rows.map((b) {
          final svc = b['service_detail'];
          final art = b['handyman_detail'];
          return DashItem({
            'id': b['id'],
            'role': 'client',
            'title': svc is Map ? svc['title'] : null,
            'status': b['status'],
            'booking_date': b['booking_date'],
            'city': b['city'],
            'counterpart': art is Map ? (art['display_name'] ?? art['first_name']) : null,
          });
        }).toList();
      },
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
            SizedBox(
              height: 420,
              child: TratraEmptyState(
                icon: Icons.event_note_outlined,
                title: 'Aucune réservation pour le moment',
                description: 'Vos réservations apparaîtront ici dès que vous aurez demandé une intervention à un artisan.',
                actions: [
                  if (onExplore != null) TratraButton(label: 'Trouver un service', onPressed: onExplore),
                ],
              ),
            ),
          ]);
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
          itemBuilder: (_, i) => DashItemTile(item: items[i], onTap: () async {
            await openItem(context, items[i]);
            await reload();
          }),
        );
      },
    );
  }
}

class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const DashPage(title: 'Mes réservations', body: BookingsList());
}
