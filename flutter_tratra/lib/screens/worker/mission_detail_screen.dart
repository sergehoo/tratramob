// lib/screens/worker/mission_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/services/booking_service.dart';
import 'package:flutter_tratra/screens/worker/worker_home_screen.dart' show StatusChip;

class MissionDetailScreen extends StatefulWidget {
  final String bookingId;
  const MissionDetailScreen({super.key, required this.bookingId});

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  late Future<Booking> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<BookingService>().detail(widget.bookingId);
  }

  /// Prochaines transitions proposées à l'artisan selon le statut courant.
  List<_Action> _actionsFor(String status) {
    switch (status) {
      case 'pending':
        return const [
          _Action('confirmed', 'Accepter la mission', Icons.check_circle, false),
          _Action('cancelled', 'Refuser', Icons.cancel, true),
        ];
      case 'confirmed':
        return const [
          _Action('in_progress', 'Démarrer l\'intervention', Icons.play_arrow, false),
          _Action('cancelled', 'Annuler', Icons.cancel, true),
        ];
      case 'in_progress':
        return const [
          _Action('completed', 'Terminer la mission', Icons.done_all, false),
        ];
      default:
        return const [];
    }
  }

  Future<void> _transition(String to) async {
    setState(() => _busy = true);
    try {
      final updated =
          await context.read<BookingService>().transition(widget.bookingId, to);
      if (!mounted) return;
      setState(() => _future = Future.value(updated));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Statut mis à jour.'),
          backgroundColor: AppConstants.successColor));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Transition refusée : $e'),
          backgroundColor: AppConstants.dangerColor));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail de la mission')),
      body: FutureBuilder<Booking>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('Erreur : ${snap.error}'));
          }
          final b = snap.data!;
          final actions = _actionsFor(b.status);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(b.serviceTitle ?? 'Mission #${b.id}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  StatusChip(status: b.status),
                ],
              ),
              const SizedBox(height: 16),
              _row(Icons.calendar_today, 'Date',
                  b.bookingDate?.toLocal().toString().split('.').first ?? '—'),
              _row(Icons.location_on_outlined, 'Adresse',
                  [b.address, b.city].where((s) => (s ?? '').isNotEmpty).join(', ')),
              if (b.amount != null)
                _row(Icons.payments_outlined, 'Montant',
                    '${b.amount!.toStringAsFixed(0)} FCFA'),
              if ((b.notes ?? '').isNotEmpty)
                _row(Icons.notes, 'Note', b.notes!),
              const SizedBox(height: 24),
              if (actions.isEmpty)
                const Text('Aucune action disponible pour ce statut.',
                    style: TextStyle(color: AppConstants.textSecondary))
              else
                ...actions.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: a.destructive
                            ? OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppConstants.dangerColor),
                                onPressed: _busy ? null : () => _transition(a.to),
                                icon: Icon(a.icon),
                                label: Text(a.label),
                              )
                            : ElevatedButton.icon(
                                onPressed: _busy ? null : () => _transition(a.to),
                                icon: Icon(a.icon),
                                label: Text(a.label),
                              ),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppConstants.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppConstants.textSecondary)),
                Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action {
  final String to;
  final String label;
  final IconData icon;
  final bool destructive;
  const _Action(this.to, this.label, this.icon, this.destructive);
}
