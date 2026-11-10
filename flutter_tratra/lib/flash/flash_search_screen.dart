// lib/flash/flash_search_screen.dart
//
// « Ma demande Tratra Flash » : recherche géographique en direct, façon VTC. Carte centrée sur le lieu de l'intervention, cercles de
// recherche animés et rayon courant ; panneau d'état : métier, phase (recherche, extension, propositions, sélection, confirmé,
// indisponible, annulé), rayon, éligibles / contactés / réponses / propositions, offres de prix et contre-offres. Annulation toujours
// accessible tant que la demande est ouverte. Aucune position de professionnel n'est affichée (le serveur n'en transmet aucune).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_hybrid.dart';
import 'package:flutter_tratra/flash/flash_search.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/screens/live/live_map.dart' show kMapTiles;
import 'package:flutter_tratra/screens/tracking_screen.dart';

String _relaunchKey() => 'flash-relaunch-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';

String _fcfa(int v) => '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ')} FCFA';

class FlashRequestScreen extends StatefulWidget {
  const FlashRequestScreen({super.key, required this.requestId});
  final int requestId;
  @override
  State<FlashRequestScreen> createState() => _FlashRequestScreenState();
}

class _FlashRequestScreenState extends State<FlashRequestScreen> {
  late final FlashRequestLive _live;
  bool _busy = false;

  FlashApi get _api => context.read<FlashController>().api;

  @override
  void initState() {
    super.initState();
    InboxController? inbox;
    try {
      inbox = context.read<InboxController>();
    } catch (_) {
      inbox = null;   // écran ouvert hors de l'application complète (tests) : lecture périodique seulement
    }
    _live = FlashRequestLive(api: context.read<FlashController>().api, requestId: widget.requestId, events: inbox?.events,
        socketLive: inbox == null ? null : () => inbox!.isLive)
      ..addListener(_changed);
    unawaited(_live.start());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _live
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() call, {String? done}) async {
    setState(() => _busy = true);
    try {
      final d = await call();
      if (!mounted) return;
      if (d['id'] != null && '${d['id']}' != '${widget.requestId}') {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => FlashRequestScreen(requestId: int.parse('${d['id']}'))));
        return;
      }
      _live.apply(d);
      if (done != null) _snack(done);
    } on FlashApiError catch (e) {
      _snack(e.message);
      await _live.refresh();
    } catch (_) {
      _snack('Connexion impossible : rien n’a été envoyé. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _cancel() async {
    if (!await showTratraConfirm(context, title: 'Annuler la demande ?',
        message: 'La recherche s’arrête et les professionnels sollicités sont prévenus. Aucun frais.',
        confirmLabel: 'Annuler la demande', cancelLabel: 'Continuer la recherche', danger: true)) {
      return;
    }
    await _act(() => _api.cancelRequest(widget.requestId), done: 'Demande annulée.');
  }

  Future<void> _switchToAuto(Map<String, dynamic> d, Map<String, dynamic>? target) async {
    if (!await confirmSwitch(context, to: kAuto, currentPro: d['status'] == 'searching' ? '${target?['name'] ?? ''}'.trim() : null)) return;
    await _act(() => _api.switchMode(widget.requestId, kAuto, version: int.tryParse('${d['version']}')));
  }

  Future<void> _switchToDirect(Map<String, dynamic> d) async {
    final category = (d['category'] as Map?) ?? const {};
    final contacted = <int>{if ((d['target'] as Map?)?['id'] != null) int.parse('${(d['target'] as Map)['id']}')};
    final chosen = await Navigator.of(context).push<ChosenPro>(MaterialPageRoute(
        builder: (_) => FlashProsScreen(categoryId: int.parse('${category['id']}'), categoryName: '${category['name']}',
            when: DateTime.tryParse('${d['scheduled_for']}'), commune: '${d['commune'] ?? ''}', excludeIds: contacted)));
    if (chosen == null || !mounted) return;
    if (!await confirmSwitch(context, to: kDirect, newPro: chosen.name)) return;
    await _act(() => _api.switchMode(widget.requestId, kDirect, target: chosen.id, version: int.tryParse('${d['version']}')));
  }

  Future<void> _choose(Map<String, dynamic> q) async {
    final pro = (q['pro'] as Map?) ?? const {};
    if (!await showTratraConfirm(context, title: 'Choisir ${pro['name'] ?? 'ce professionnel'} ?',
        message: 'La mission lui est confirmée à ${q['amount_label']} et la réservation est créée. Les autres propositions sont retirées.',
        confirmLabel: 'Confirmer ce choix')) {
      return;
    }
    await _act(() => _api.chooseQuote(widget.requestId, int.parse('${q['offer']}')), done: 'Professionnel confirmé.');
  }

  Future<void> _counter(Map<String, dynamic> q) async {
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CounterSheet(proposal: (q['amount'] as num?)?.toInt() ?? 0, proName: '${(q['pro'] as Map?)?['name'] ?? 'Le professionnel'}'),
    );
    if (amount == null || !mounted) return;
    await _act(() => _api.counter(widget.requestId, int.parse('${q['offer']}'), amount),
        done: 'Contre-offre envoyée : le professionnel l’accepte ou garde sa proposition.');
  }

  @override
  Widget build(BuildContext context) {
    final d = _live.data;
    final canCancel = d?['can_cancel'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma demande Tratra Flash')),
      body: d == null
          ? _LoadingOrError(error: _live.error, loading: _live.loading, onRetry: _live.refresh)
          : RefreshIndicator(
              onRefresh: _live.refresh,
              child: ListView(
                padding: EdgeInsets.only(bottom: TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
                children: [
                  FlashSearchMap(
                    key: const ValueKey('flash-map'),
                    center: _center(d),
                    radiusM: _live.search.radiusM,
                    stepsM: _live.search.stepsM,
                    searching: d['status'] == 'searching',
                    label: _live.search.radiusLabel,
                  ),
                  if (_live.offline)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, 0),
                      child: TratraAlert(key: ValueKey('flash-offline'), tone: TratraAlertTone.warning,
                          message: 'Connexion perdue : l’état affiché peut dater. Nouvelle tentative automatique…'),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _content(d)),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: canCancel
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s2, TtSpace.s4, TtSpace.s3),
              child: TratraButton(key: const ValueKey('flash-request-cancel'), label: 'Annuler ma demande', variant: TratraButtonVariant.outline,
                  block: true, leading: const Icon(Icons.close_rounded, size: 18), onPressed: _busy ? null : _cancel),
            )
          : null,
    );
  }

  LatLng? _center(Map<String, dynamic> d) {
    final c = d['center'];
    if (c is! Map) return null;
    final lat = (c['lat'] as num?)?.toDouble();
    final lng = (c['lng'] as num?)?.toDouble();
    return lat == null || lng == null ? null : LatLng(lat, lng);
  }

  List<Widget> _content(Map<String, dynamic> d) {
    final status = '${d['status'] ?? ''}';
    final s = _live.search;
    final quotes = ((d['quotes'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final pro = (d['assigned_to'] as Map?)?.cast<String, dynamic>();
    final target = (d['target'] as Map?)?.cast<String, dynamic>();
    final direct = d['matching'] == kDirect;
    final quoteMode = d['mode'] == 'quote';
    return [
      _PhaseHeader(status: status, search: s, quoteMode: quoteMode, direct: direct),
      const SizedBox(height: TtSpace.s3),
      TratraCard(
        key: const ValueKey('flash-request-summary'),
        padding: TratraCard.compact,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${(d['category'] as Map?)?['name'] ?? ''}', style: TratraTheme.style(TtType.h2)),
          Text([d['commune'], d['when_label'], d['amount_label']].where((e) => '${e ?? ''}'.isNotEmpty).join(' · '),
              style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: TtSpace.s3),
          Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
            TratraBadge('${d['status_label'] ?? ''}', key: const ValueKey('flash-request-status'),
                tone: switch (status) { 'assigned' => TratraTone.success, 'searching' || 'quoting' => TratraTone.accent, 'awaiting' => TratraTone.warning, _ => TratraTone.gray },
                pulse: status == 'searching'),
            TratraBadge(direct ? 'Choisir mon professionnel' : 'Trouvez-moi un professionnel', key: const ValueKey('flash-request-matching'),
                tone: TratraTone.night),
            if (!direct) TratraBadge(quoteMode ? 'Propositions' : 'Immédiat', tone: TratraTone.gray),
          ]),
          if (direct && target != null && status != 'assigned')
            Padding(
              padding: const EdgeInsets.only(top: TtSpace.s2),
              child: Text('Professionnel choisi : ${target['name']}', style: TratraTheme.style(TtType.bodySm)),
            ),
        ]),
      ),
      if (!direct && (status == 'searching' || status == 'quoting' || s.count('contacted') > 0)) ...[
        const SizedBox(height: TtSpace.s3),
        _Counters(search: s, quoteMode: quoteMode),
      ],
      if (s.needsConsent && d['can_extend'] == true) ...[
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          key: const ValueKey('flash-extend-card'),
          variant: TratraCardVariant.accent,
          padding: TratraCard.compact,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Élargir au-delà de ${s.farKm.round()} km ?', style: TratraTheme.style(TtType.h3)),
            const SizedBox(height: TtSpace.s1),
            Text('Personne n’est disponible à moins de ${s.farKm.round()} km. '
                '${s.availableBeyond} professionnel${s.availableBeyond > 1 ? 's' : ''} disponible${s.availableBeyond > 1 ? 's' : ''} plus loin '
                '(déplacement plus long). Rien n’est envoyé sans votre accord.',
                style: TratraTheme.style(TtType.bodySm)),
            const SizedBox(height: TtSpace.s3),
            TratraButton(key: const ValueKey('flash-extend'), label: 'Élargir la recherche', block: true, variant: TratraButtonVariant.night,
                leading: const Icon(Icons.radar_rounded, size: 18),
                onPressed: _busy ? null : () => _act(() => _api.extend(widget.requestId), done: 'Recherche élargie.')),
          ]),
        ),
      ],
      if (status == 'awaiting') ...[
        const SizedBox(height: TtSpace.s3),
        TratraAlert(key: const ValueKey('flash-awaiting'), tone: TratraAlertTone.warning,
            message: '${target?['name'] ?? 'Le professionnel choisi'} ${d['awaiting_reason'] ?? 'n’est pas disponible'}. '
                'Votre demande est conservée : choisissez la suite.'),
      ],
      if (d['can_switch'] == true) ...[
        const SizedBox(height: TtSpace.s3),
        if (direct || status == 'awaiting')
          TratraButton(key: const ValueKey('flash-switch-auto'), label: 'Trouvez-moi un professionnel', block: true,
              leading: const Icon(Icons.bolt_rounded, size: 18),
              variant: status == 'awaiting' ? TratraButtonVariant.primary : TratraButtonVariant.outline,
              onPressed: _busy ? null : () => _switchToAuto(d, target)),
        if (direct || status == 'awaiting') const SizedBox(height: TtSpace.s2),
        TratraButton(key: const ValueKey('flash-switch-direct'), label: direct ? 'Choisir un autre professionnel' : 'Choisir mon professionnel',
            block: true, variant: TratraButtonVariant.outline, leading: const Icon(Icons.person_search_rounded, size: 18),
            onPressed: _busy ? null : () => _switchToDirect(d)),
      ],
      if (pro != null) ...[
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          key: const ValueKey('flash-request-pro'),
          padding: TratraCard.compact,
          variant: TratraCardVariant.soft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.verified_rounded, color: TtColors.primary),
              const SizedBox(width: TtSpace.s2),
              Expanded(child: Text('${pro['name']} est confirmé pour votre mission', style: TratraTheme.style(TtType.h3))),
            ]),
            if (pro['trust_score'] != null) Text('Score Tratra Trust : ${pro['trust_score']}/100', style: TratraTheme.style(TtType.bodySm)),
            const SizedBox(height: TtSpace.s3),
            if (d['booking'] != null)
              TratraButton(
                key: const ValueKey('flash-request-booking'),
                label: 'Suivre la réservation',
                block: true,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TrackingScreen(bookingId: '${d['booking']}'))),
              ),
          ]),
        ),
      ],
      if (quotes.isNotEmpty) ...[
        const SizedBox(height: TtSpace.s4),
        Text(status == 'quoting' ? 'Choisissez une proposition' : 'Propositions reçues', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s2),
        for (final q in quotes) ...[
          _quoteTile(q),
          const SizedBox(height: TtSpace.s2),
        ],
      ],
      if (status == 'unfulfilled') ...[
        const SizedBox(height: TtSpace.s3),
        TratraAlert(tone: TratraAlertTone.warning, message: '${d['close_reason'] ?? 'Aucun professionnel disponible.'} '
            'Vous pouvez relancer, par exemple avec un autre horaire ou un autre montant.'),
      ],
      if (d['can_relaunch'] == true) ...[
        const SizedBox(height: TtSpace.s3),
        TratraButton(key: const ValueKey('flash-request-relaunch'), label: 'Relancer la recherche', block: true,
            onPressed: _busy ? null : () => _act(() => _api.relaunch(widget.requestId, _relaunchKey()))),
      ],
    ];
  }

  Widget _quoteTile(Map<String, dynamic> q) {
    final pro = (q['pro'] as Map?)?.cast<String, dynamic>() ?? const {};
    final status = '${q['status']}';
    final countered = status == 'countered';
    final live = status == 'quoted' || countered;
    return Opacity(
      opacity: live || status == 'accepted' ? 1 : 0.55,
      child: TratraCard(
        key: ValueKey('flash-quote-${q['offer']}'),
        padding: TratraCard.compact,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${pro['name'] ?? 'Professionnel'}', style: TratraTheme.style(TtType.title))),
            Text('${q['amount_label']}', style: TratraTheme.style(TtType.title, color: TtColors.primary)),
          ]),
          Text([
            if (pro['rating'] != null) '${pro['rating']}/5 (${pro['reviews']} avis)',
            if (pro['trust_score'] != null) 'Trust ${pro['trust_score']}/100',
            if (q['distance_km'] != null) '${'${q['distance_km']}'.replaceAll('.', ',')} km',
          ].join(' · '), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          if ('${q['message'] ?? ''}'.isNotEmpty) Text('« ${q['message']} »', style: TratraTheme.style(TtType.bodySm)),
          if (countered)
            Padding(
              padding: const EdgeInsets.only(top: TtSpace.s2),
              child: TratraBadge('Votre contre-offre : ${q['counter_label']} — réponse attendue', key: ValueKey('flash-countered-${q['offer']}'),
                  tone: TratraTone.warning),
            )
          else if (!live)
            Padding(
              padding: const EdgeInsets.only(top: TtSpace.s2),
              child: TratraBadge('${q['status_label'] ?? status}', tone: TratraTone.gray),
            ),
          if (q['can_choose'] == true || q['can_counter'] == true) ...[
            const SizedBox(height: TtSpace.s2),
            Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
              if (q['can_choose'] == true)
                TratraButton(key: ValueKey('flash-choose-${q['offer']}'), label: 'Choisir', size: TratraButtonSize.sm,
                    onPressed: _busy ? null : () => _choose(q)),
              if (q['can_counter'] == true)
                TratraButton(key: ValueKey('flash-counter-${q['offer']}'), label: 'Contre-offre', size: TratraButtonSize.sm,
                    variant: TratraButtonVariant.outline, onPressed: _busy ? null : () => _counter(q)),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _LoadingOrError extends StatelessWidget {
  const _LoadingOrError({required this.error, required this.loading, required this.onRetry});
  final String? error;
  final bool loading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: TtSpace.s3),
          Text('Chargement de votre demande…', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
        ]),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(TtSpace.s6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, size: 40, color: TtColors.fog),
          const SizedBox(height: TtSpace.s3),
          Text(error!, key: const ValueKey('flash-load-error'), textAlign: TextAlign.center, style: TratraTheme.style(TtType.body)),
          const SizedBox(height: TtSpace.s4),
          TratraButton(key: const ValueKey('flash-retry'), label: 'Réessayer', loading: loading, onPressed: loading ? null : onRetry),
        ]),
      ),
    );
  }
}

/// Phase de la demande, en clair, avec le rayon et l'échéance du palier suivant.
class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.status, required this.search, required this.quoteMode, required this.direct});
  final String status;
  final FlashSearch search;
  final bool quoteMode;
  final bool direct;

  @override
  Widget build(BuildContext context) {
    final phase = search.raw.isEmpty ? _fallbackPhase(status) : search.phase;
    final (IconData icon, Color color, String subtitle) = switch (phase) {
      'search' => (Icons.radar_rounded, TtColors.primary, direct
          ? 'Le professionnel choisi a reçu votre demande.'
          : search.progressive
              ? 'Rayon actuel : ${search.radiusLabel}. ${search.nextStepIn != null && search.count('pending') > 0 ? 'Sans réponse, la recherche s’élargit automatiquement.' : 'Les professionnels sollicités répondent.'}'
              : 'Les professionnels vérifiés et disponibles de votre zone sont sollicités.'),
      'extension' => (Icons.zoom_out_map_rounded, TtColors.warning, 'Votre accord est nécessaire pour chercher plus loin.'),
      'proposals' => (Icons.local_offer_rounded, TtColors.primary, 'D’autres propositions peuvent encore arriver. Vous choisissez.'),
      'selection' => (Icons.how_to_reg_rounded, TtColors.primary, 'La recherche est terminée : choisissez une proposition.'),
      'confirmed' => (Icons.check_circle_rounded, TtColors.success, 'La réservation est créée.'),
      'unavailable' => (Icons.do_not_disturb_on_rounded, TtColors.ash, 'Aucun professionnel n’a pu prendre la mission.'),
      'cancelled' => (Icons.cancel_rounded, TtColors.ash, 'La recherche est arrêtée.'),
      'awaiting' => (Icons.pending_actions_rounded, TtColors.warning, 'Le professionnel choisi n’a pas accepté.'),
      _ => (Icons.radar_rounded, TtColors.primary, ''),
    };
    final steps = quoteMode ? const ['Recherche', 'Propositions', 'Sélection', 'Confirmé'] : const ['Recherche', 'Confirmé'];
    final reached = switch (phase) {
      'proposals' => 1,
      'selection' => 2,
      'confirmed' => steps.length - 1,
      _ => 0,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: TtSpace.s2),
        Expanded(
          child: Text(search.phaseLabel.isNotEmpty ? search.phaseLabel : _label(phase), key: const ValueKey('flash-phase'),
              style: TratraTheme.style(TtType.h3)),
        ),
      ]),
      if (subtitle.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: TtSpace.s1),
          child: Text(subtitle, key: const ValueKey('flash-phase-detail'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        ),
      if (!direct && !const {'unavailable', 'cancelled', 'awaiting'}.contains(phase)) ...[
        const SizedBox(height: TtSpace.s3),
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) Expanded(child: Container(height: 2, color: i <= reached ? TtColors.primary : TtColors.line)),
            _StepDot(label: steps[i], done: i < reached || phase == 'confirmed', current: i == reached && phase != 'confirmed'),
          ],
        ]),
      ],
    ]);
  }

  static String _fallbackPhase(String status) => switch (status) {
        'assigned' => 'confirmed',
        'unfulfilled' => 'unavailable',
        'cancelled' => 'cancelled',
        'quoting' => 'selection',
        'awaiting' => 'awaiting',
        _ => 'search',
      };

  static String _label(String phase) => switch (phase) {
        'confirmed' => 'Confirmé',
        'unavailable' => 'Aucun professionnel disponible',
        'cancelled' => 'Annulée',
        'selection' => 'Choisissez une proposition',
        'awaiting' => 'Votre choix est attendu',
        _ => 'Recherche en cours',
      };
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.label, required this.done, required this.current});
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? TtColors.primary : current ? TtColors.accent : TtColors.surface,
            border: Border.all(color: done || current ? TtColors.primary : TtColors.line, width: 2),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TratraTheme.style(TtType.caption, color: current || done ? TtColors.ink : TtColors.fog)),
      ]);
}

/// Compteurs exacts du serveur : éligibles trouvés, contactés, réponses, propositions de prix.
class _Counters extends StatelessWidget {
  const _Counters({required this.search, required this.quoteMode});
  final FlashSearch search;
  final bool quoteMode;

  @override
  Widget build(BuildContext context) {
    Widget cell(String key, String label, int value) => Expanded(
          child: Column(children: [
            Text('$value', key: ValueKey('flash-count-$key'), style: TratraTheme.style(TtType.h2)),
            Text(label, textAlign: TextAlign.center, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ]),
        );
    return TratraCard(
      key: const ValueKey('flash-request-progress'),
      padding: TratraCard.compact,
      child: Row(children: [
        cell('eligible', 'Éligibles', search.count('eligible')),
        cell('contacted', 'Contactés', search.count('contacted')),
        cell('responses', 'Réponses', search.count('responses')),
        if (quoteMode) cell('proposals', 'Propositions', search.count('proposals')),
      ]),
    );
  }
}

/// Contre-offre : montant plus bas que la proposition (sinon, le client la choisit directement).
class _CounterSheet extends StatefulWidget {
  const _CounterSheet({required this.proposal, required this.proName});
  final int proposal;
  final String proName;
  @override
  State<_CounterSheet> createState() => _CounterSheetState();
}

class _CounterSheetState extends State<_CounterSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _send() {
    final v = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (v == null || v <= 0) return setState(() => _error = 'Indiquez un montant.');
    if (v >= widget.proposal) return setState(() => _error = 'Proposez moins de ${_fcfa(widget.proposal)} — sinon, choisissez la proposition.');
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s4 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Contre-offre à ${widget.proName}', style: TratraTheme.style(TtType.h3)),
          const SizedBox(height: TtSpace.s1),
          Text('Sa proposition : ${_fcfa(widget.proposal)}. S’il accepte votre montant, la mission lui est confirmée ; sinon sa proposition '
              'reste valable.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
          const SizedBox(height: TtSpace.s3),
          TratraInput(key: const ValueKey('flash-counter-amount'), label: 'Votre montant (FCFA)', controller: _amount,
              keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], errorText: _error,
              onSubmitted: (_) => _send()),
          const SizedBox(height: TtSpace.s3),
          TratraButton(key: const ValueKey('flash-counter-send'), label: 'Envoyer la contre-offre', block: true, onPressed: _send),
        ]),
      );
}

/// Carte de recherche : lieu de l'intervention, paliers de rayon, cercle courant et ondes animées pendant la recherche. Sans position
/// (demande par commune), un radar sans fond de carte. Aucun repère de professionnel.
class FlashSearchMap extends StatefulWidget {
  const FlashSearchMap({super.key, required this.center, required this.radiusM, required this.stepsM, required this.searching,
      required this.label, this.height = 260});
  final LatLng? center;
  final int radiusM;
  final List<int> stepsM;
  final bool searching;
  final String label;
  final double height;

  /// Fond de carte (tuiles réseau) : désactivé dans les tests.
  static bool tiles = true;

  @override
  State<FlashSearchMap> createState() => _FlashSearchMapState();
}

class _FlashSearchMapState extends State<FlashSearchMap> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _zoom = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final MapController _map = MapController();
  bool _ready = false;
  double _width = 360;
  double _fromZoom = 14, _toZoom = 14;
  String? _banner;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      if (!_ready || widget.center == null) return;
      final z = _fromZoom + (_toZoom - _fromZoom) * Curves.easeInOutCubic.transform(_zoom.value);
      _map.move(widget.center!, z);
    });
    _syncPulse();
  }

  @override
  void didUpdateWidget(FlashSearchMap old) {
    super.didUpdateWidget(old);
    _syncPulse();
    if (widget.radiusM != old.radiusM) {
      if (old.radiusM > 0 && widget.radiusM > old.radiusM) {
        _bannerTimer?.cancel();
        setState(() => _banner = 'Rayon élargi à ${widget.label}');
        _bannerTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _banner = null);
        });
      }
      _animateTo(_fitZoom());
    }
  }

  void _syncPulse() {
    if (widget.searching && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.searching && _pulse.isAnimating) _pulse.stop();
  }

  double _fitZoom() {
    final c = widget.center;
    final r = math.max(widget.radiusM, 150);
    if (c == null) return 14;
    final side = math.min(_width, widget.height) * 0.8;
    final z = math.log(156543.03392 * math.cos(c.latitude * math.pi / 180) * side / (2 * r)) / math.ln2;
    return z.clamp(4.0, 18.0);
  }

  void _animateTo(double z) {
    if (!_ready) return;
    _fromZoom = _map.camera.zoom;
    _toZoom = z;
    _zoom.forward(from: 0);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pulse.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.center;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, box) {
        _width = box.maxWidth;
        return Stack(fit: StackFit.expand, children: [
          if (c != null)
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: c,
                initialZoom: _fitZoom(),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
                onMapReady: () => _ready = true,
              ),
              children: [
                if (FlashSearchMap.tiles) TileLayer(urlTemplate: kMapTiles, userAgentPackageName: 'net.tratra.app'),
                CircleLayer(circles: [
                  for (final m in widget.stepsM.where((m) => m < widget.radiusM))
                    CircleMarker(point: c, radius: m.toDouble(), useRadiusInMeter: true, color: Colors.transparent,
                        borderColor: TtColors.primary.withValues(alpha: 0.25), borderStrokeWidth: 1),
                  if (widget.radiusM > 0)
                    CircleMarker(point: c, radius: widget.radiusM.toDouble(), useRadiusInMeter: true,
                        color: TtColors.primary.withValues(alpha: 0.10), borderColor: TtColors.primary, borderStrokeWidth: 2),
                ]),
                MarkerLayer(markers: [
                  Marker(point: c, width: 36, height: 36,
                      child: const Icon(Icons.location_on_rounded, color: TtColors.night, size: 36)),
                ]),
              ],
            )
          else
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [TtColors.primarySoft, TtColors.canvas]))),
          if (widget.searching)
            IgnorePointer(child: AnimatedBuilder(animation: _pulse, builder: (_, __) => CustomPaint(painter: _PulsePainter(_pulse.value)))),
          if (c == null)
            const Center(child: Icon(Icons.home_work_rounded, size: 34, color: TtColors.primary)),
          Positioned(
            left: TtSpace.s3,
            bottom: TtSpace.s3,
            child: _Chip(key: const ValueKey('flash-radius-label'), icon: Icons.radar_rounded,
                text: widget.radiusM > 0 ? 'Rayon ${widget.label}' : widget.label.isEmpty ? 'Votre zone' : widget.label),
          ),
          if (_banner != null)
            Positioned(
              top: TtSpace.s3,
              left: 0,
              right: 0,
              child: Center(child: _Chip(key: const ValueKey('flash-extension-banner'), icon: Icons.zoom_out_map_rounded, text: _banner!, dark: true)),
            ),
        ]);
      }),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.text, this.dark = false});
  final IconData icon;
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? TtColors.night : TtColors.surface,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: dark ? TtColors.accent : TtColors.primary),
          const SizedBox(width: 6),
          Text(text, style: TratraTheme.style(TtType.caption, color: dark ? TtColors.surface : TtColors.ink)),
        ]),
      );
}

/// Ondes de recherche : trois cercles qui s'éloignent du lieu de l'intervention et s'estompent.
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = math.min(size.width, size.height) * 0.42;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = TtColors.primary.withValues(alpha: (1 - p) * 0.55);
      canvas.drawCircle(center, 12 + p * maxR, paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}
