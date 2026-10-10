// lib/screens/worker/mission_detail_screen.dart
//
// Détail d'une mission côté artisan + transitions d'état (machine à états backend).
// Interface : Design System Tratra.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/booking.dart';
import 'package:flutter_tratra/screens/dashboard/messages_screen.dart' show openBookingConversation;
import 'package:flutter_tratra/screens/worker/dashboard/worker_ui.dart';
import 'package:flutter_tratra/screens/trust/mission_qr_card.dart';
import 'package:flutter_tratra/services/booking_service.dart';

class MissionDetailScreen extends StatefulWidget {
  final String bookingId;
  const MissionDetailScreen({super.key, required this.bookingId});

  @override
  State<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends State<MissionDetailScreen> {
  late Future<Booking> _future;
  bool _busy = false;

  /// Transition en cours (affiche le chargement sur le bon bouton).
  String? _pendingTo;

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
          _Action(
              'confirmed', 'Accepter la mission', Icons.check_circle, false),
          _Action('cancelled', 'Refuser', Icons.cancel, true),
        ];
      case 'confirmed':
        return const [
          _Action('in_progress', 'Démarrer l’intervention', Icons.play_arrow,
              false),
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

  /// Aide contextuelle affichée au-dessus des actions (texte explicatif, aucune donnée).
  String? _hintFor(String status) {
    switch (status) {
      case 'pending':
        return 'Cette demande attend votre réponse : acceptez-la ou refusez-la.';
      case 'confirmed':
        return 'Démarrez l’intervention lorsqu’elle commence.';
      case 'in_progress':
        return 'Terminez la mission une fois l’intervention achevée.';
      case 'completed':
        return 'Cette mission est terminée.';
      case 'cancelled':
        return 'Cette mission est annulée.';
      default:
        return null;
    }
  }

  Future<void> _transition(String to) async {
    setState(() {
      _busy = true;
      _pendingTo = to;
    });
    try {
      final updated =
          await context.read<BookingService>().transition(widget.bookingId, to);
      if (!mounted) return;
      setState(() {
      _future = Future.value(updated);
    });
      showWorkerToast(context, 'Statut mis à jour.',
          tone: WorkerToastTone.success);
    } catch (e) {
      if (!mounted) return;
      showWorkerToast(context, 'Transition refusée : $e',
          tone: WorkerToastTone.danger);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pendingTo = null;
        });
      }
    }
  }

  void _reload() {
    setState(() =>
        _future = context.read<BookingService>().detail(widget.bookingId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Détail de la mission'),
      body: FutureBuilder<Booking>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const _DetailSkeleton();
          }
          if (snap.hasError || !snap.hasData) {
            return ListView(
              padding: _pagePadding,
              children: [
                TratraAlert(
                  tone: TratraAlertTone.danger,
                  title: 'Impossible de charger la mission',
                  message: '${snap.error}',
                  action: TratraButton(
                    label: 'Réessayer',
                    size: TratraButtonSize.sm,
                    variant: TratraButtonVariant.outline,
                    leading: const Icon(Icons.refresh_rounded),
                    onPressed: _reload,
                  ),
                ),
              ],
            );
          }
          final b = snap.data!;
          final actions = _actionsFor(b.status);
          final hint = _hintFor(b.status);
          final place =
              [b.address, b.city].where((s) => (s ?? '').isNotEmpty).join(', ');
          return ListView(
            padding: _pagePadding,
            children: [
              WorkerReveal(child: _MissionHeader(booking: b)),
              const SizedBox(height: TtSpace.s5),
              WorkerReveal(
                index: 1,
                child: TratraCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: TtSpace.s5, vertical: TtSpace.s2),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: b.bookingDate == null
                            ? '—'
                            : formatWhen(b.bookingDate!, long: true),
                      ),
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        label: 'Adresse',
                        value: place,
                      ),
                      if (b.amount != null)
                        _DetailRow(
                          icon: Icons.payments_outlined,
                          label: 'Montant',
                          value: formatFcfa(b.amount!),
                        ),
                      if ((b.notes ?? '').isNotEmpty)
                        _DetailRow(
                          icon: Icons.notes_rounded,
                          label: 'Note',
                          value: b.notes!,
                        ),
                    ],
                  ),
                ),
              ),
              if (b.status != 'cancelled' && int.tryParse(b.id) != null) ...[
                const SizedBox(height: TtSpace.s3),
                TratraButton(
                  label: 'Écrire au client',
                  variant: TratraButtonVariant.outline,
                  size: TratraButtonSize.lg,
                  block: true,
                  leading: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  onPressed: () => openBookingConversation(context, int.parse(b.id)),
                ),
              ],
              if ((b.status == 'confirmed' || b.status == 'in_progress') && int.tryParse(b.id) != null) ...[
                const SizedBox(height: TtSpace.s4),
                MissionQrCard(bookingId: int.parse(b.id)),
              ],
              const SizedBox(height: TtSpace.s4),
              WorkerReveal(
                index: 2,
                child: TratraCard(
                  variant: TratraCardVariant.soft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Prochaine étape',
                          style: TratraTheme.style(TtType.h3)),
                      if (hint != null) ...[
                        const SizedBox(height: TtSpace.s1 + 2),
                        Text(hint,
                            style: TratraTheme.style(TtType.bodySm,
                                color: TtColors.inkSoft)),
                      ],
                      if (b.status != 'cancelled') ...[
                        const SizedBox(height: TtSpace.s5),
                        _StatusProgress(status: b.status),
                      ],
                      const SizedBox(height: TtSpace.s5),
                      if (actions.isEmpty)
                        Text(
                          'Aucune action disponible pour ce statut.',
                          style: TratraTheme.style(TtType.bodySm,
                              color: TtColors.ash),
                        )
                      else
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(height: TtSpace.s3),
                          TratraButton(
                            label: actions[i].label,
                            size: TratraButtonSize.lg,
                            block: true,
                            variant: actions[i].destructive
                                ? TratraButtonVariant.outline
                                : TratraButtonVariant.primary,
                            loading: _pendingTo == actions[i].to,
                            leading: Icon(
                              actions[i].icon,
                              color: actions[i].destructive
                                  ? TtColors.danger
                                  : null,
                            ),
                            onPressed:
                                _busy ? null : () => _transition(actions[i].to),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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

const _pagePadding = EdgeInsets.fromLTRB(
  TtLayout.gutterMobile,
  TtSpace.s5,
  TtLayout.gutterMobile,
  TtSpace.s8,
);

/// Sur-titre + statut + titre de la mission.
class _MissionHeader extends StatelessWidget {
  const _MissionHeader({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final title = booking.serviceTitle ?? 'Mission #${booking.id}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: WorkerEyebrow(booking.serviceTitle != null
                    ? 'Mission #${booking.id}'
                    : 'Mission'),
              ),
            ),
            const SizedBox(width: TtSpace.s3),
            TratraStatusBadge(TratraStatus.booking, booking.status),
          ],
        ),
        const SizedBox(height: TtSpace.s3),
        Semantics(
          header: true,
          child: Text(title, style: TratraTheme.style(TtType.h1)),
        ),
        const SizedBox(height: TtSpace.s2),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: TtColors.accent,
            borderRadius: BorderRadius.all(Radius.circular(TtRadius.pill)),
          ),
          child: SizedBox(width: 40, height: 4),
        ),
      ],
    );
  }
}

/// Ligne d'information : pastille d'icône, étiquette discrète, valeur.
class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TtSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkerIconTile(icon, size: 40),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style:
                        TratraTheme.style(TtType.eyebrow, color: TtColors.ash)),
                const SizedBox(height: TtSpace.s1),
                Text(
                  value.isEmpty ? '—' : value,
                  style: TratraTheme.style(TtType.body)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Frise d'avancement dérivée du statut courant (affichage uniquement, aucune donnée en plus).
class _StatusProgress extends StatelessWidget {
  const _StatusProgress({required this.status});

  final String status;

  static const _steps = ['pending', 'confirmed', 'in_progress', 'completed'];

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexOf(status);
    if (current < 0) return const SizedBox.shrink();
    final finished = status == 'completed';
    return Semantics(
      container: true,
      label: 'Avancement de la mission',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: _ProgressStep(
                index: i,
                label: TratraStatus.of(TratraStatus.booking, _steps[i]).label,
                done: i < current || finished,
                active: i == current && !finished,
                firstStep: i == 0,
                lastStep: i == _steps.length - 1,
                leftLit: i <= current || finished,
                rightLit: i < current || finished,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.index,
    required this.label,
    required this.done,
    required this.active,
    required this.firstStep,
    required this.lastStep,
    required this.leftLit,
    required this.rightLit,
  });

  final int index;
  final String label;
  final bool done;
  final bool active;
  final bool firstStep;
  final bool lastStep;
  final bool leftLit;
  final bool rightLit;

  Widget _line(BuildContext context,
      {required bool visible, required bool lit}) {
    return Expanded(
      child: AnimatedContainer(
        duration: workerMotion(context, TtMotion.slow),
        curve: TtMotion.emphasized,
        height: 2,
        color: !visible
            ? Colors.transparent
            : (lit ? TtColors.primaryDark : TtColors.line),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state =
        done ? 'étape terminée' : (active ? 'étape en cours' : 'étape à venir');
    final Color circleColor = done
        ? TtColors.primaryDark
        : (active ? TtColors.accent : TtColors.lineSoft);
    return Semantics(
      label: '$label, $state',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            children: [
              _line(context, visible: !firstStep, lit: leftLit),
              AnimatedContainer(
                duration: workerMotion(context, TtMotion.slow),
                curve: TtMotion.emphasized,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  border: active
                      ? Border.all(color: TtColors.accentDark, width: 2)
                      : null,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TratraTheme.style(
                            TtType.caption,
                            color: active ? TtColors.ink : TtColors.ash,
                          ).copyWith(fontWeight: FontWeight.w700, height: 1),
                        ),
                ),
              ),
              _line(context, visible: !lastStep, lit: rightLit),
            ],
          ),
          const SizedBox(height: TtSpace.s2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TratraTheme.style(
                TtType.caption,
                color: active
                    ? TtColors.ink
                    : (done ? TtColors.inkSoft : TtColors.ash),
              ).copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Squelette de la page pendant le chargement du détail.
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement en cours',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: _pagePadding,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TratraSkeletonBox(
                    width: 140, height: 24, radius: TtRadius.pill),
                SizedBox(height: TtSpace.s3),
                TratraSkeletonBox(width: 260, height: 30),
                SizedBox(height: TtSpace.s6),
                TratraSkeletonCard(),
                SizedBox(height: TtSpace.s3),
                TratraSkeletonCard(),
                SizedBox(height: TtSpace.s3),
                TratraSkeletonCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
