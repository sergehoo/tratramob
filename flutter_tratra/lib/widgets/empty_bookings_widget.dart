// lib/widgets/empty_bookings_widget.dart
// Adaptateur : préférer TratraEmptyState (lib/design) pour tout nouveau code.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';

/// État vide de la liste de réservations. Décrit la situation réelle et mène à une
/// destination existante (catalogue des services, route `RouteNames.allServices`).
class EmptyBookingsWidget extends StatelessWidget {
  const EmptyBookingsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return TratraEmptyState(
      icon: Icons.calendar_month_outlined,
      title: 'Aucune réservation',
      description: 'Vos réservations apparaîtront ici.',
      actions: [
        TratraButton(
          label: 'Découvrir les services',
          trailing: const Icon(Icons.arrow_forward_rounded),
          onPressed: () => Navigator.of(context).pushNamed(RouteNames.allServices),
        ),
      ],
    );
  }
}
