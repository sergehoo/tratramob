// lib/screens/live/live_cards.dart
//
// Cartes du suivi en direct : client (suivre l'artisan, partage de SA position facultatif et retirable) et artisan
// (« Je suis en route » avec consentement explicite, « Je suis arrivé »). Démarrer / terminer la mission reste géré par
// les boutons de la machine à états.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/live/live_controller.dart';
import 'package:flutter_tratra/screens/live/live_map.dart';
import 'package:flutter_tratra/screens/live/live_state.dart';

const _steps = <(String, String)>[
  ('confirmed', 'Confirmée'),
  ('en_route', 'En route'),
  ('arrived', 'Arrivé'),
  ('in_progress', 'En cours'),
  ('completed', 'Terminée'),
];

class LiveSteps extends StatelessWidget {
  const LiveSteps({super.key, required this.phase});
  final String phase;

  @override
  Widget build(BuildContext context) {
    if (phase == 'cancelled') return const TratraBadge('Annulée', tone: TratraTone.danger);
    final idx = _steps.indexWhere((s) => s.$1 == phase);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var i = 0; i < _steps.length; i++)
        Semantics(
          label: '${_steps[i].$2}, ${i < idx || phase == 'completed' ? 'terminé' : i == idx ? 'en cours' : 'à venir'}',
          child: TratraBadge(
            _steps[i].$2,
            tone: (i < idx || phase == 'completed') ? TratraTone.primary : (i == idx ? TratraTone.accent : TratraTone.gray),
            icon: (i < idx || phase == 'completed') ? Icons.check_circle_rounded : Icons.circle_outlined,
          ),
        ),
    ]);
  }
}

/// Carte, ETA, distance et alertes. Honnête : rien sans donnée reçue ; position ancienne signalée ; ETA estimée indiquée.
class LivePanel extends StatelessWidget {
  const LivePanel({super.key, required this.controller});
  final LiveController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state!;
    final route = s.route;
    // Pas de carte vide : elle n'apparaît que s'il y a au moins un repère réel à y placer.
    final showMap = s.artisan != null || s.client != null || s.destination != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LiveSteps(phase: s.phase),
      if (controller.offline) ...[
        const SizedBox(height: TtSpace.s3),
        const TratraAlert(tone: TratraAlertTone.warning, title: 'Connexion perdue', message: 'Le suivi reprendra automatiquement dès que le réseau sera de retour.'),
      ],
      if (s.phase == 'en_route') ...[
        const SizedBox(height: TtSpace.s3),
        if (route != null)
          Row(children: [
            Expanded(child: _Metric(icon: Icons.timer_outlined, label: 'Arrivée estimée', value: formatEta(route.etaMinutes))),
            const SizedBox(width: TtSpace.s2),
            Expanded(child: _Metric(icon: Icons.navigation_outlined, label: 'Distance', value: formatDistance(route.distanceM))),
          ])
        else
          Text(
            s.artisan != null
                ? 'Le lieu d’intervention n’est pas localisé : la distance et l’heure d’arrivée ne peuvent pas être calculées.'
                : (s.isArtisan ? 'Partage de votre position en attente de la première mesure.' : 'L’artisan est en route. Sa position apparaîtra dès qu’il la partage.'),
            style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
          ),
        if (route != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(route.isEstimate ? 'Estimation à vol d’oiseau (vitesse moyenne urbaine) : le trajet réel peut différer.' : 'Itinéraire routier calculé.',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ),
        if (s.artisan?.stale == true) ...[
          const SizedBox(height: TtSpace.s2),
          TratraAlert(tone: TratraAlertTone.warning, title: 'Position ancienne', message: 'Dernière position reçue ${ageLabel(s.artisan!.ageSeconds)}. Elle n’est plus à jour (réseau ou GPS de l’artisan).'),
        ],
        if (!s.isArtisan && !s.artisanSharing) ...[
          const SizedBox(height: TtSpace.s2),
          const TratraAlert(tone: TratraAlertTone.info, message: 'L’artisan a suspendu le partage de sa position. Il reste en route.'),
        ],
      ],
      if (s.phase == 'arrived') ...[
        const SizedBox(height: TtSpace.s3),
        TratraAlert(
          tone: TratraAlertTone.success,
          title: s.isArtisan ? 'Arrivée enregistrée' : 'Votre artisan est arrivé',
          message: s.isArtisan ? 'Le partage de position est arrêté.' : 'Vérifiez son identité avec le QR de mission avant de commencer.',
        ),
      ],
      if (showMap) ...[
        const SizedBox(height: TtSpace.s3),
        LiveMap(snapshot: s),
        const SizedBox(height: 6),
        Row(children: [
          const _Legend(color: TtColors.primary, label: 'Artisan'),
          const SizedBox(width: TtSpace.s3),
          const _Legend(color: TtColors.accent, label: 'Client'),
          const Spacer(),
          Text(controller.realtime ? 'Temps réel actif' : 'Actualisation toutes les 5 s', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ]),
      ],
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(TtSpace.s3),
        decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.panel)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: TtColors.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text(value, style: TratraTheme.style(TtType.h2)),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
      ]);
}

/// Hôte commun : crée le contrôleur de la mission et le libère à la fermeture de l'écran.
class _LiveHost extends StatefulWidget {
  const _LiveHost({required this.bookingId, required this.builder});
  final int bookingId;
  final Widget Function(BuildContext context, LiveController controller) builder;
  @override
  State<_LiveHost> createState() => _LiveHostState();
}

class _LiveHostState extends State<_LiveHost> {
  late final LiveController _c = LiveController(context.read<BaseApi>(), widget.bookingId)..start();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _c, builder: (context, _) => widget.builder(context, _c));
}

/// Client : suivre l'arrivée de l'artisan ; partage de SA position facultatif, explicite et retirable.
class ClientLiveCard extends StatefulWidget {
  const ClientLiveCard({super.key, required this.bookingId});
  final int bookingId;
  @override
  State<ClientLiveCard> createState() => _ClientLiveCardState();
}

class _ClientLiveCardState extends State<ClientLiveCard> {
  bool _ack = false;
  bool _busy = false;

  Future<void> _toggle(LiveController c, bool next) async {
    setState(() => _busy = true);
    await c.setConsent(next);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => _LiveHost(
        bookingId: widget.bookingId,
        builder: (context, c) {
          final s = c.state;
          if (s == null) return c.error != null ? TratraAlert(tone: TratraAlertTone.danger, message: c.error!) : const SizedBox.shrink();
          if (!s.isOpen) return const SizedBox.shrink();
          return TratraCard(
            padding: TratraCard.compact,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suivi de l’artisan', style: TratraTheme.style(TtType.h3)),
              Text('Position et heure d’arrivée en direct pendant son trajet.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              const SizedBox(height: TtSpace.s3),
              if (s.phase == 'confirmed')
                Padding(
                  padding: const EdgeInsets.only(bottom: TtSpace.s3),
                  child: Text('L’artisan n’a pas encore démarré son trajet. Vous serez notifié dès qu’il sera en route.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                ),
              if (s.phase == 'in_progress')
                Padding(
                  padding: const EdgeInsets.only(bottom: TtSpace.s3),
                  child: Text('L’intervention est en cours : le suivi de position est terminé.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                ),
              LivePanel(controller: c),
              if (s.canShare) ...[
                const SizedBox(height: TtSpace.s4),
                Container(
                  padding: const EdgeInsets.all(TtSpace.s3),
                  decoration: BoxDecoration(border: Border.all(color: TtColors.lineSoft), borderRadius: BorderRadius.circular(TtRadius.panel)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Partager ma position (facultatif)', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    if (s.clientSharing) ...[
                      Text('Votre position est partagée avec l’artisan jusqu’à son arrivée.${c.geo == GeoStatus.waiting ? ' En attente du signal GPS…' : ''}',
                          style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                      if (c.geoNote != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.geoNote!, style: TratraTheme.style(TtType.caption, color: TtColors.warningInk))),
                      const SizedBox(height: TtSpace.s2),
                      TratraButton(label: 'Arrêter le partage et effacer mes positions', variant: TratraButtonVariant.outline, size: TratraButtonSize.sm, loading: _busy, onPressed: () => _toggle(c, false)),
                    ] else ...[
                      Text('Aide l’artisan à vous trouver et affine l’heure d’arrivée. Votre position n’est visible que de lui, uniquement avant son arrivée, et vous pouvez l’arrêter à tout moment.',
                          style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _ack,
                        onChanged: (v) => setState(() => _ack = v ?? false),
                        title: Text('J’accepte de partager ma position avec l’artisan jusqu’à son arrivée.', style: TratraTheme.style(TtType.bodySm)),
                      ),
                      TratraButton(label: 'Partager ma position', size: TratraButtonSize.sm, loading: _busy, onPressed: _ack ? () => _toggle(c, true) : null),
                    ],
                  ]),
                ),
              ],
              if (c.error != null && !c.offline) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: c.error!)],
            ]),
          );
        },
      );
}

/// Artisan : « Je suis en route » (consentement explicite), suivi du trajet, « Je suis arrivé ».
class ArtisanLiveCard extends StatefulWidget {
  const ArtisanLiveCard({super.key, required this.bookingId, this.onChanged});
  final int bookingId;
  final VoidCallback? onChanged;
  @override
  State<ArtisanLiveCard> createState() => _ArtisanLiveCardState();
}

class _ArtisanLiveCardState extends State<ArtisanLiveCard> {
  String? _busy;

  Future<void> _run(String key, Future<bool> Function() action) async {
    setState(() => _busy = key);
    await action();
    if (mounted) setState(() => _busy = null);
    widget.onChanged?.call();
  }

  Future<void> _confirmStart(LiveController c) async {
    var ack = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Partager ma position avec le client ?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Le client verra votre position et l’heure d’arrivée estimée pendant votre trajet. Le partage s’arrête automatiquement à votre arrivée, et vous pouvez le suspendre à tout moment. Gardez l’application ouverte pendant le trajet.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: ack,
              onChanged: (v) => setLocal(() => ack = v ?? false),
              title: const Text('J’accepte de partager ma position avec le client jusqu’à mon arrivée.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: ack ? () => Navigator.pop(ctx, true) : null, child: const Text('Accepter et partir')),
          ],
        ),
      ),
    );
    if (ok == true) await _run('start', c.startRoute);
  }

  @override
  Widget build(BuildContext context) => _LiveHost(
        bookingId: widget.bookingId,
        builder: (context, c) {
          final s = c.state;
          if (s == null) return c.error != null ? TratraAlert(tone: TratraAlertTone.danger, message: c.error!) : const SizedBox.shrink();
          if (!const {'confirmed', 'en_route', 'arrived'}.contains(s.phase)) return const SizedBox.shrink();
          final sharing = s.artisanSharing && s.phase == 'en_route';
          return TratraCard(
            padding: TratraCard.compact,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trajet vers le client', style: TratraTheme.style(TtType.h3)),
              Text('Votre position n’est partagée que pendant le trajet, avec votre accord.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
              const SizedBox(height: TtSpace.s3),
              LivePanel(controller: c),
              const SizedBox(height: TtSpace.s3),
              if (s.canStartRoute)
                TratraButton(label: 'Je suis en route', size: TratraButtonSize.lg, block: true, leading: const Icon(Icons.navigation_outlined), loading: _busy == 'start', onPressed: s.windowOpen ? () => _confirmStart(c) : null),
              if (s.phase == 'confirmed' && !s.windowOpen)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Le suivi s’ouvre quelques heures avant l’heure prévue de l’intervention.', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
              if (s.phase == 'en_route') ...[
                if (c.geo == GeoStatus.waiting) Text('En attente du signal GPS…', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                if (c.geo == GeoStatus.denied || c.geo == GeoStatus.unavailable)
                  TratraAlert(tone: TratraAlertTone.warning, title: c.geo == GeoStatus.denied ? 'Position refusée' : 'Signal GPS indisponible', message: '${c.geoNote ?? ''} Vous pouvez tout de même indiquer votre arrivée.'),
                if (c.geoNote != null && c.geo == GeoStatus.sharing) Text(c.geoNote!, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                const SizedBox(height: TtSpace.s2),
                TratraButton(
                  label: sharing ? 'Suspendre le partage de ma position' : 'Reprendre le partage de ma position',
                  variant: TratraButtonVariant.outline,
                  block: true,
                  loading: _busy == 'pause',
                  onPressed: () => _run('pause', () => c.setConsent(!sharing)),
                ),
              ],
              if (s.canArrive) ...[
                const SizedBox(height: TtSpace.s2),
                TratraButton(
                  label: 'Je suis arrivé',
                  size: TratraButtonSize.lg,
                  block: true,
                  variant: s.phase == 'en_route' ? TratraButtonVariant.primary : TratraButtonVariant.outline,
                  leading: const Icon(Icons.flag_outlined),
                  loading: _busy == 'arrive',
                  onPressed: () => _run('arrive', c.arrive),
                ),
              ],
              if (c.error != null && !c.offline) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: c.error!)],
            ]),
          );
        },
      );
}
