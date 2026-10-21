// lib/flash/flash_offer_screen.dart
//
// Écran Tratra Flash : une nouvelle mission à saisir. Métier, zone, date, montant et délai ; réputation du client (sans son nom) ;
// « Pourquoi vous ? » (détail du classement). Accepter (prix ferme) ou Proposer un devis (sur devis), Refuser sans conséquence.
// La sonnerie s'arrête à la réponse, à l'échéance ou dès que la mission est prise par un autre professionnel.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/screens/worker/mission_detail_screen.dart';

enum _Outcome { none, accepted, quoted, declined, closed, expired }

class FlashOfferScreen extends StatefulWidget {
  const FlashOfferScreen({super.key, required this.offerId, required this.controller, this.ring = false, this.initialAction});

  final int offerId;
  final FlashController controller;
  final bool ring;
  final String? initialAction;

  @override
  State<FlashOfferScreen> createState() => _FlashOfferScreenState();
}

class _FlashOfferScreenState extends State<FlashOfferScreen> {
  FlashOffer? _offer;
  String? _error;
  String? _notice;
  bool _busy = false;
  int _left = 0;
  Timer? _timer;
  _Outcome _outcome = _Outcome.none;
  final _amount = TextEditingController();
  final _message = TextEditingController();

  FlashController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.closedOffers.addListener(_onClosed);
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.closedOffers.removeListener(_onClosed);
    _amount.dispose();
    _message.dispose();
    unawaited(_c.silence(widget.offerId));
    super.dispose();
  }

  void _onClosed() {
    if (!_c.closedOffers.value.contains(widget.offerId) || _outcome != _Outcome.none || !mounted) return;
    _finish(_Outcome.closed, 'Cette mission n’est plus disponible : elle a été attribuée ou retirée.');
  }

  Future<void> _load() async {
    try {
      final offer = await _c.api.offer(widget.offerId);
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _left = offer.secondsLeft;
        if (offer.accepted) _outcome = _Outcome.accepted;
        if (offer.status == 'quoted') _outcome = _Outcome.quoted;
        if (offer.status == 'declined') _outcome = _Outcome.declined;
        if (const {'expired', 'withdrawn'}.contains(offer.status)) {
          _outcome = offer.status == 'expired' ? _Outcome.expired : _Outcome.closed;
          _notice = offer.status == 'expired' ? 'Le délai de réponse est écoulé.' : 'Cette mission n’est plus disponible.';
        }
      });
      if (offer.pending && _left > 0) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
        if (widget.ring) {
          final playback = await _c.ring();
          if (mounted && playback.explanation != null) setState(() => _notice = playback.explanation);
        }
        if (widget.initialAction == 'accept' && !offer.quoteMode) await _accept();
      } else if (offer.pending) {
        _finish(_Outcome.expired, 'Le délai de réponse est écoulé.');
      }
    } on FlashApiError catch (e) {
      if (mounted) setState(() => _error = e.status == 404 ? 'Cette proposition n’existe pas sur ce compte.' : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Connexion impossible. Vérifiez votre réseau.');
    }
  }

  void _tick() {
    if (!mounted) return;
    if (_left <= 1) {
      _finish(_Outcome.expired, 'Le délai de réponse est écoulé : la mission est proposée à un autre professionnel.');
      return;
    }
    setState(() => _left--);
  }

  void _finish(_Outcome outcome, [String? notice]) {
    _timer?.cancel();
    unawaited(_c.silence(widget.offerId));
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _notice = notice;
      _busy = false;
    });
  }

  Future<void> _run(Future<FlashOffer> Function() call, _Outcome success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _c.native.stop();
    try {
      final offer = await call();
      if (!mounted) return;
      setState(() => _offer = offer);
      _finish(success);
    } on FlashApiError catch (e) {
      if (const {'already_assigned', 'request_closed', 'offer_expired', 'offer_closed'}.contains(e.code)) {
        _finish(e.code == 'offer_expired' ? _Outcome.expired : _Outcome.closed, e.message);
      } else if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Connexion impossible : réessayez.';
        });
      }
    }
  }

  Future<void> _accept() => _run(() => _c.api.accept(widget.offerId), _Outcome.accepted);

  Future<void> _decline() async {
    final offer = _offer;
    if (offer == null) return;
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s2),
            child: Text('Refuser cette mission ?', style: TratraTheme.style(TtType.h3)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
            child: Text('Un refus n’a aucune conséquence sur votre réputation. Le motif est facultatif.',
                style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          ),
          const SizedBox(height: TtSpace.s2),
          for (final r in offer.declineReasons)
            ListTile(key: ValueKey('decline-${r['code']}'), title: Text(r['label']!), onTap: () => Navigator.pop(ctx, r['code'])),
          ListTile(key: const ValueKey('decline-none'), title: const Text('Refuser sans motif'), onTap: () => Navigator.pop(ctx, '')),
        ]),
      ),
    );
    if (reason == null) return;
    await _run(() => _c.api.decline(widget.offerId, reason: reason), _Outcome.declined);
  }

  Future<void> _sendQuote() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Indiquez le montant de votre devis.');
      return;
    }
    await _run(() => _c.api.quote(widget.offerId, amount, _message.text.trim()), _Outcome.quoted);
  }

  String get _countdown {
    final m = _left ~/ 60, s = _left % 60;
    return m > 0 ? '$m min ${s.toString().padLeft(2, '0')}' : '$s s';
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: AppBar(
        backgroundColor: TtColors.night,
        foregroundColor: Colors.white,
        title: Text('Tratra Flash', style: TratraTheme.style(TtType.title, color: Colors.white)),
        leading: IconButton(
            key: const ValueKey('flash-close'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop()),
      ),
      body: offer == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(TtSpace.s6), child: TratraAlert(tone: TratraAlertTone.danger, message: _error!)),
            )
          : _body(offer),
    );
  }

  Widget _body(FlashOffer o) {
    final pad = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s8 + pad),
      children: [
        _header(o),
        const SizedBox(height: TtSpace.s4),
        if (_notice != null) ...[
          TratraAlert(key: const ValueKey('flash-notice'), tone: _outcome == _Outcome.none ? TratraAlertTone.info : TratraAlertTone.warning, message: _notice!),
          const SizedBox(height: TtSpace.s3),
        ],
        if (_error != null) ...[
          TratraAlert(key: const ValueKey('flash-error'), tone: TratraAlertTone.danger, message: _error!),
          const SizedBox(height: TtSpace.s3),
        ],
        ..._outcomeOrActions(o),
        const SizedBox(height: TtSpace.s4),
        if (o.description.isNotEmpty)
          TratraCard(
            padding: TratraCard.compact,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Besoin du client', style: TratraTheme.style(TtType.title)),
              const SizedBox(height: TtSpace.s1),
              Text(o.description, style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)),
            ]),
          ),
        const SizedBox(height: TtSpace.s3),
        _clientReputation(o),
        const SizedBox(height: TtSpace.s3),
        if (o.why.isNotEmpty) _why(o),
      ],
    );
  }

  Widget _header(FlashOffer o) {
    final pending = _outcome == _Outcome.none && o.pending;
    return Container(
      key: const ValueKey('flash-header'),
      margin: const EdgeInsets.only(top: TtSpace.s4),
      padding: const EdgeInsets.all(TtSpace.s5),
      decoration: BoxDecoration(gradient: TtGradients.brand, borderRadius: BorderRadius.circular(TtRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(o.direct ? 'UN CLIENT VOUS A CHOISI' : 'NOUVELLE MISSION', key: const ValueKey('flash-eyebrow'),
              style: TratraTheme.style(TtType.eyebrow, color: TtColors.accent)),
          const Spacer(),
          if (pending)
            Container(
              key: const ValueKey('flash-countdown'),
              padding: const EdgeInsets.symmetric(horizontal: TtSpace.s3, vertical: TtSpace.s1),
              decoration: BoxDecoration(color: TtColors.accent, borderRadius: BorderRadius.circular(TtRadius.pill)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.timer_outlined, size: 16, color: TtColors.night),
                const SizedBox(width: 4),
                Text(_countdown, style: TratraTheme.style(TtType.caption, color: TtColors.night).copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
        ]),
        const SizedBox(height: TtSpace.s2),
        Text(o.category, style: TratraTheme.style(TtType.h1, color: Colors.white)),
        const SizedBox(height: TtSpace.s3),
        Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
          _chip(Icons.place_outlined, o.zone),
          _chip(o.immediate ? Icons.bolt : Icons.event_outlined, o.whenLabel),
          if (o.distanceKm != null) _chip(Icons.near_me_outlined, '${o.distanceKm!.toStringAsFixed(1).replaceAll('.', ',')} km'),
        ]),
        const SizedBox(height: TtSpace.s4),
        Text(o.quoteMode ? 'Sur devis' : o.amountLabel,
            key: const ValueKey('flash-amount'), style: TratraTheme.style(TtType.displayLg, color: Colors.white)),
        if (!o.quoteMode)
          Text('Montant proposé par le client, déplacement compris', style: TratraTheme.style(TtType.caption, color: Colors.white70)),
      ]),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s3, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(TtRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: TratraTheme.style(TtType.bodySm, color: Colors.white)),
        ]),
      );

  List<Widget> _outcomeOrActions(FlashOffer o) {
    switch (_outcome) {
      case _Outcome.accepted:
        return [
          TratraCard(
            key: const ValueKey('flash-accepted'),
            padding: TratraCard.compact,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.check_circle, color: TtColors.success),
                const SizedBox(width: TtSpace.s2),
                Expanded(child: Text('Mission confirmée !', style: TratraTheme.style(TtType.h3))),
              ]),
              const SizedBox(height: TtSpace.s2),
              if (o.clientName.isNotEmpty) Text('Client : ${o.clientName}', style: TratraTheme.style(TtType.body)),
              if (o.address.isNotEmpty) Text('Adresse : ${o.address}', style: TratraTheme.style(TtType.body)),
              const SizedBox(height: TtSpace.s3),
              if (o.bookingId != null)
                TratraButton(
                  key: const ValueKey('flash-open-mission'),
                  label: 'Ouvrir la mission',
                  block: true,
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => MissionDetailScreen(bookingId: '${o.bookingId}'))),
                ),
            ]),
          ),
        ];
      case _Outcome.quoted:
        return [
          TratraAlert(
            key: const ValueKey('flash-quoted'),
            tone: TratraAlertTone.success,
            message: 'Devis envoyé${o.quoteAmount != null ? ' (${_money(o.quoteAmount!)})' : ''}. Le client choisit : vous serez prévenu.',
          ),
        ];
      case _Outcome.declined:
        return [
          const TratraAlert(
              key: ValueKey('flash-declined'), tone: TratraAlertTone.info, message: 'Refus enregistré. Aucune conséquence sur votre réputation.'),
          const SizedBox(height: TtSpace.s3),
          TratraButton(label: 'Fermer', variant: TratraButtonVariant.outline, block: true, onPressed: () => Navigator.of(context).maybePop()),
        ];
      case _Outcome.closed || _Outcome.expired:
        return [
          TratraButton(
              key: const ValueKey('flash-done'),
              label: 'Fermer',
              variant: TratraButtonVariant.outline,
              block: true,
              onPressed: () => Navigator.of(context).maybePop()),
        ];
      case _Outcome.none:
        if (o.quoteMode) {
          return [
            TextField(
              key: const ValueKey('flash-quote-amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Votre prix (FCFA, déplacement compris)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: TtSpace.s2),
            TextField(
              key: const ValueKey('flash-quote-message'),
              controller: _message,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Message au client (facultatif)', border: OutlineInputBorder()),
            ),
            TratraButton(key: const ValueKey('flash-quote'), label: 'Envoyer le devis', size: TratraButtonSize.lg, block: true,
                loading: _busy, onPressed: _busy ? null : _sendQuote),
            const SizedBox(height: TtSpace.s2),
            TratraButton(key: const ValueKey('flash-decline'), label: 'Refuser', variant: TratraButtonVariant.outline, block: true,
                onPressed: _busy ? null : _decline),
          ];
        }
        return [
          TratraButton(key: const ValueKey('flash-accept'), label: 'Accepter la mission', size: TratraButtonSize.lg, block: true,
              loading: _busy, onPressed: _busy ? null : _accept),
          const SizedBox(height: TtSpace.s2),
          TratraButton(key: const ValueKey('flash-decline'), label: 'Refuser', variant: TratraButtonVariant.outline, block: true,
              onPressed: _busy ? null : _decline),
          const SizedBox(height: TtSpace.s2),
          Text('En acceptant, vous vous engagez à intervenir au montant indiqué. Le premier professionnel qui accepte obtient la mission.',
              textAlign: TextAlign.center, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ];
    }
  }

  Widget _clientReputation(FlashOffer o) {
    final rep = o.clientReputation;
    final avg = rep['average'];
    final count = int.tryParse('${rep['count'] ?? 0}') ?? 0;
    final text = avg is num ? '${avg.toStringAsFixed(1).replaceAll('.', ',')}/5 sur $count évaluation${count > 1 ? 's' : ''} de professionnels'
        : count == 0 ? 'Nouveau client : pas encore évalué' : 'Pas encore assez d’évaluations pour une moyenne';
    return TratraCard(
      padding: TratraCard.compact,
      child: Row(children: [
        const Icon(Icons.person_outline, color: TtColors.primary),
        const SizedBox(width: TtSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Réputation du client', style: TratraTheme.style(TtType.title)),
            Text(text, style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          ]),
        ),
      ]),
    );
  }

  Widget _why(FlashOffer o) => TratraCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: const ValueKey('flash-why'),
          title: Text('Pourquoi cette proposition ?', style: TratraTheme.style(TtType.title)),
          childrenPadding: const EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s3),
          children: [
            for (final c in o.why)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text('${c['label']}', style: TratraTheme.style(TtType.bodySm))),
                  Expanded(child: Text('${c['detail']}', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
                ]),
              ),
          ],
        ),
      );
}

String _money(int amount) {
  final s = amount.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}
