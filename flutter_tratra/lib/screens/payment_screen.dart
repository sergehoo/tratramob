// lib/screens/payment_screen.dart
//
// Paiement d'une réservation. Écran bâti sur le Design System Tratra (lib/design).
//
// Honnêteté : aucune création de paiement n'est branchée dans l'application mobile
// (le bouton « Payer maintenant » n'avait pas de traitement, seulement un TODO), et les
// moyens en ligne ne sont pas ouverts côté serveur. L'écran affiche donc le montant réel
// et dirige vers une destination existante au lieu de simuler un paiement.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';

import 'booking_flow/booking_format.dart';
import 'booking_flow/booking_widgets.dart';

class PaymentScreen extends StatelessWidget {
  final double amount;
  final String serviceName;

  /// Réservation concernée, quand la route la transmet (facultatif : aujourd'hui
  /// `PaymentArgs` ne la conserve pas). Permet d'ouvrir directement son suivi.
  final String? bookingId;

  const PaymentScreen({
    super.key,
    required this.amount,
    required this.serviceName,
    this.bookingId,
  });

  bool get _hasBooking => bookingId != null && bookingId!.isNotEmpty;

  void _openBookings(BuildContext context) {
    // La liste « Mes réservations » (route existante) remplace le tunnel de réservation :
    // on ne revient pas sur le formulaire déjà envoyé.
    Navigator.of(context).pushNamedAndRemoveUntil(
      RouteNames.booking,
      ModalRoute.withName(RouteNames.home),
    );
  }

  void _openTracking(BuildContext context) {
    Navigator.of(context).pushNamed(
      RouteNames.tracking,
      arguments: TrackingArgs(bookingId!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TratraAppBar(title: 'Paiement'),
      body: BookingContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            BookingReveal(
              child: _TotalCard(amount: amount, serviceName: serviceName),
            ),
            const SizedBox(height: TtSpace.s4),
            const BookingReveal(
              index: 1,
              child: TratraAlert(
                tone: TratraAlertTone.info,
                title: 'Paiement en ligne indisponible',
                message:
                    'Le règlement en ligne n’est pas encore proposé dans l’application. '
                    'Retrouvez votre réservation et son état dans « Mes réservations ».',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BookingStickyBar(
        child: _hasBooking
            ? TratraButton(
                label: 'Suivre ma réservation',
                size: TratraButtonSize.lg,
                block: true,
                trailing: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => _openTracking(context),
              )
            : TratraButton(
                label: 'Voir mes réservations',
                size: TratraButtonSize.lg,
                block: true,
                leading: const Icon(Icons.calendar_month_outlined),
                onPressed: () => _openBookings(context),
              ),
      ),
    );
  }
}

/// Montant et service : carte sombre de la marque, soulignement jaune.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.amount, required this.serviceName});
  final double amount;
  final String serviceName;

  @override
  Widget build(BuildContext context) {
    final hasAmount = amount > 0;
    final total = hasAmount ? formatFcfa(amount) : 'Montant non défini';

    return TratraCard(
      variant: TratraCardVariant.night,
      padding: const EdgeInsets.all(TtSpace.s6),
      semanticLabel: 'Total à payer : $total, pour $serviceName',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BookingEyebrow('Total à payer', onNight: true),
            const SizedBox(height: TtSpace.s4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                total,
                maxLines: 1,
                style: TratraTheme.style(
                  hasAmount ? TtType.displayLg : TtType.h1,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: TtSpace.s3),
            DecoratedBox(
              decoration: BoxDecoration(
                color: TtColors.accent,
                borderRadius: TtRadius.pillAll,
              ),
              child: const SizedBox(width: TtSpace.s10, height: TtSpace.s1),
            ),
            const SizedBox(height: TtSpace.s5),
            Divider(color: Colors.white.withValues(alpha: 0.12)),
            const SizedBox(height: TtSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.home_repair_service_outlined,
                      size: 18, color: TtColors.accent),
                ),
                const SizedBox(width: TtSpace.s3),
                Expanded(
                  child: Text(
                    serviceName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.body,
                        color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
