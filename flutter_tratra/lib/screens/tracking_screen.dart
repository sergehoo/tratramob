// screens/tracking_screen.dart
//
// Suivi d'une réservation : état réel (BookingService.detail), progression déduite du
// statut, détails de la réservation et annulation (BookingService.cancel, c'est-à-dire la
// transition d'état « cancelled » de la machine à états du backend).
// Écran bâti sur le Design System Tratra (lib/design) ; aucune donnée fictive.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/screens/dashboard/messages_screen.dart' show openBookingConversation;
import 'package:flutter_tratra/screens/trust/mission_qr_card.dart' show IdentityVerifyCard;
import 'package:flutter_tratra/services/booking_service.dart';

import 'booking_flow/booking_format.dart';
import 'booking_flow/booking_widgets.dart';

class TrackingScreen extends StatefulWidget {
  final String bookingId;
  const TrackingScreen({super.key, required this.bookingId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

/// Étapes du parcours, dans l'ordre de la machine à états : pending → confirmed →
/// in_progress → completed (« cancelled » sort du parcours).
const List<String> _steps = ['Envoyée', 'Confirmée', 'En cours', 'Terminée'];

int? _stepIndex(String status) {
  switch (status) {
    case 'pending':
      return 0;
    case 'confirmed':
      return 1;
    case 'in_progress':
      return 2;
    case 'completed':
      return 3;
  }
  return null;
}

class _TrackingScreenState extends State<TrackingScreen> {
  late final BookingService _service;

  Booking? _booking;
  bool _loading = true;
  String? _error;
  String? _actionError;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _service = context.read<BookingService>();
    _load();
  }

  /// `silent` : actualisation sans squelette (la page reste affichée).
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final b = await _service.detail(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = b;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _booking != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Actualisation impossible : ${cleanError(e)}')),
        );
      } else {
        setState(() => _error = cleanError(e));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _cancelBooking() async {
    final b = _booking;
    if (b == null || _cancelling) return;

    final confirmed = await showTratraConfirm(
      context,
      title: 'Annuler la réservation',
      message:
          'Êtes-vous sûr de vouloir annuler cette réservation ? Des frais d’annulation peuvent s’appliquer.',
      confirmLabel: 'Oui, annuler',
      cancelLabel: 'Non',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _cancelling = true;
      _actionError = null;
    });
    try {
      // Annulation = transition d'état « cancelled » (politique de pénalité côté backend).
      final updated = await _service.cancel(b.id);
      if (!mounted) return;
      setState(() => _booking = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: TtColors.accent),
              SizedBox(width: TtSpace.s3),
              Expanded(child: Text('Réservation annulée avec succès')),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError =
          'La réservation n’a pas pu être annulée. ${cleanError(e)}');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    // Comme sur le web : annulation possible tant que l'intervention n'a pas commencé.
    final canCancel = b != null && (b.status == 'pending' || b.status == 'confirmed');

    return Scaffold(
      appBar: TratraAppBar(
        title: 'Suivi de réservation',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: (_loading || _cancelling)
                ? null
                : () => _load(silent: _booking != null),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: canCancel
          ? BookingStickyBar(
              child: TratraButton(
                label: 'Annuler la réservation',
                variant: TratraButtonVariant.outline,
                size: TratraButtonSize.lg,
                block: true,
                loading: _cancelling,
                leading: const Icon(Icons.close_rounded),
                onPressed: _cancelBooking,
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) return const _TrackingSkeleton();

    final b = _booking;
    if (b == null) {
      return TratraEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Réservation indisponible',
        description: _error ?? 'Cette réservation ne peut pas être chargée pour le moment.',
        actions: [
          TratraButton(
            label: 'Réessayer',
            leading: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: TtColors.primaryDark,
      onRefresh: () => _load(silent: true),
      child: BookingContentWidth(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            if (_actionError != null) ...[
              TratraAlert(
                tone: TratraAlertTone.danger,
                message: _actionError!,
                onDismiss: () => setState(() => _actionError = null),
              ),
              const SizedBox(height: TtSpace.s4),
            ],
            BookingReveal(child: _SummaryCard(booking: b)),
            const SizedBox(height: TtSpace.s4),
            BookingReveal(index: 1, child: _StatusNote(status: b.status)),
            const SizedBox(height: TtSpace.s4),
            BookingReveal(index: 2, child: _DetailsCard(booking: b)),
            if (['confirmed', 'in_progress', 'completed'].contains(b.status) && int.tryParse(b.id) != null) ...[
              const SizedBox(height: TtSpace.s4),
              IdentityVerifyCard(bookingId: int.parse(b.id), active: b.status != 'completed'),
            ],
            if (b.handymanId.isNotEmpty && b.status != 'cancelled' && int.tryParse(b.id) != null) ...[
              const SizedBox(height: TtSpace.s4),
              TratraButton(
                label: 'Écrire à l’artisan',
                variant: TratraButtonVariant.outline,
                size: TratraButtonSize.lg,
                block: true,
                leading: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                onPressed: () => openBookingConversation(context, int.parse(b.id)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// En-tête : numéro, statut réel, service et progression.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final index = _stepIndex(b.status);
    final title = (b.serviceTitle != null && b.serviceTitle!.isNotEmpty)
        ? b.serviceTitle!
        : 'Votre réservation';

    return TratraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: BookingEyebrow('Réservation n° ${b.id}')),
              const SizedBox(width: TtSpace.s2),
              TratraStatusBadge(TratraStatus.booking, b.status),
            ],
          ),
          const SizedBox(height: TtSpace.s3),
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TratraTheme.style(TtType.h2),
            ),
          ),
          if (index != null) ...[
            const SizedBox(height: TtSpace.s6),
            _ProgressStepper(current: index, allDone: b.status == 'completed'),
          ],
        ],
      ),
    );
  }
}

/// Progression en quatre étapes déduite du statut réel de la réservation.
class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({required this.current, required this.allDone});
  final int current;
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = disableMotion ? Duration.zero : TtMotion.slow;

    return Semantics(
      container: true,
      label: allDone
          ? 'Progression : toutes les étapes sont terminées'
          : 'Progression : étape ${current + 1} sur ${_steps.length}, ${_steps[current]}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: _StepCell(
                  index: i,
                  current: current,
                  allDone: allDone,
                  duration: duration,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepCell extends StatelessWidget {
  const _StepCell({
    required this.index,
    required this.current,
    required this.allDone,
    required this.duration,
  });

  final int index;
  final int current;
  final bool allDone;
  final Duration duration;

  static const double _dot = 28;
  static const double _lineHeight = 3;

  @override
  Widget build(BuildContext context) {
    final isFirst = index == 0;
    final isLast = index == _steps.length - 1;
    final done = allDone || index < current;
    final isCurrent = !allDone && index == current;
    final reached = done || isCurrent;
    final leftActive = reached;
    final rightActive = allDone || index < current;

    Widget line(bool visible, bool active) => Expanded(
          child: AnimatedContainer(
            duration: duration,
            curve: TtMotion.emphasized,
            height: _lineHeight,
            decoration: BoxDecoration(
              color: !visible
                  ? Colors.transparent
                  : (active ? TtColors.primaryDark : TtColors.line),
              borderRadius: TtRadius.pillAll,
            ),
          ),
        );

    final Widget dot = AnimatedContainer(
      duration: duration,
      curve: TtMotion.emphasized,
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? TtColors.primaryDark
            : (isCurrent ? TtColors.accent : TtColors.surface),
        border: Border.all(
          color: done
              ? TtColors.primaryDark
              : (isCurrent ? TtColors.accentDark : TtColors.line),
          width: 2,
        ),
      ),
      child: Center(
        child: done
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : isCurrent
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                        color: TtColors.ink, shape: BoxShape.circle),
                    child: SizedBox(width: TtSpace.s2, height: TtSpace.s2),
                  )
                : Text(
                    '${index + 1}',
                    style: TratraTheme.style(TtType.caption,
                            color: TtColors.fog)
                        .copyWith(fontWeight: FontWeight.w700, height: 1),
                  ),
      ),
    );

    return Column(
      children: [
        Row(
          children: [
            line(!isFirst, leftActive),
            dot,
            line(!isLast, rightActive),
          ],
        ),
        const SizedBox(height: TtSpace.s2),
        // Une seule ligne, réduite si besoin : jamais de coupure au milieu d'un mot.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _steps[index],
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TratraTheme.style(
              TtType.caption,
              color: reached ? TtColors.ink : TtColors.ash,
            ).copyWith(
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Message d'état en langage clair (une phrase par statut réel).
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, TratraCardVariant variant) = switch (status) {
      'pending' => (
          Icons.hourglass_top_rounded,
          'Votre demande est en attente de confirmation.',
          TratraCardVariant.accent,
        ),
      'confirmed' => (
          Icons.check_circle_outline_rounded,
          'L’artisan a accepté votre demande.',
          TratraCardVariant.soft,
        ),
      'in_progress' => (
          Icons.build_circle_outlined,
          'L’intervention est en cours.',
          TratraCardVariant.night,
        ),
      'completed' => (
          Icons.task_alt_rounded,
          'Service terminé avec succès.',
          TratraCardVariant.soft,
        ),
      'cancelled' => (
          Icons.cancel_outlined,
          'Cette réservation a été annulée.',
          TratraCardVariant.flat,
        ),
      _ => (
          Icons.info_outline_rounded,
          'Statut de la réservation : $status.',
          TratraCardVariant.flat,
        ),
    };
    final onNight = variant == TratraCardVariant.night;

    return TratraCard(
      variant: variant,
      radius: TtRadius.panel,
      padding: TratraCard.compact,
      semanticLabel: text,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon,
                size: 24,
                color: onNight ? TtColors.accent : TtColors.primaryDark),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Text(
                text,
                style: TratraTheme.style(
                  TtType.body,
                  color: onNight ? Colors.white : TtColors.ink,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Détails réels de la réservation ; une ligne n'apparaît que si la donnée existe
/// (date et adresse affichent « Non renseignée » si elles manquent).
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.booking});
  final Booking booking;

  static String? _place(Booking b) {
    bool filled(String? s) => s != null && s.trim().isNotEmpty;
    final cityPart =
        [b.postalCode, b.city].where(filled).map((e) => e!.trim()).join(' ');
    final parts = [
      if (filled(b.address)) b.address!.trim(),
      if (cityPart.isNotEmpty) cityPart,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final place = _place(b);
    final hasDuration = b.service?.hasDuration ?? false;
    final hasAmount = b.amount != null && b.amount! > 0;
    final hasNotes = b.notes != null && b.notes!.trim().isNotEmpty;

    final rows = <Widget>[
      if (b.serviceTitle != null && b.serviceTitle!.isNotEmpty)
        BookingInfoRow(
          icon: Icons.home_repair_service_outlined,
          label: 'Service',
          value: b.serviceTitle!,
        ),
      BookingInfoRow(
        icon: Icons.event_outlined,
        label: 'Date et heure',
        value: b.bookingDate != null
            ? formatDateTimeLong(b.bookingDate!)
            : 'Non renseignée',
      ),
      if (hasDuration)
        BookingInfoRow(
          icon: Icons.schedule_rounded,
          label: 'Durée estimée',
          value: b.service!.durationDisplay,
        ),
      BookingInfoRow(
        icon: Icons.location_on_outlined,
        label: 'Adresse',
        value: place ?? 'Non renseignée',
      ),
      if (hasNotes)
        BookingInfoRow(
          icon: Icons.notes_rounded,
          label: 'Notes',
          value: b.notes!.trim(),
        ),
    ];

    return BookingStepCard(
      icon: Icons.assignment_outlined,
      title: 'Détails de la réservation',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: TtSpace.s3),
            rows[i],
          ],
          if (hasAmount) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: TtSpace.s4),
              child: Divider(),
            ),
            BookingInfoRow(
              label: 'Total',
              value: formatFcfa(b.amount!),
              strong: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Chargement : squelette de la page (annoncé une seule fois aux lecteurs d'écran).
class _TrackingSkeleton extends StatelessWidget {
  const _TrackingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement en cours',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: BookingContentWidth(
            child: const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(TtSpace.s4),
              child: Column(
                children: [
                  TratraSkeletonBox(
                      width: double.infinity, height: 190, radius: TtRadius.card),
                  SizedBox(height: TtSpace.s4),
                  TratraSkeletonBox(
                      width: double.infinity, height: 64, radius: TtRadius.panel),
                  SizedBox(height: TtSpace.s4),
                  TratraSkeletonBox(
                      width: double.infinity, height: 260, radius: TtRadius.card),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
