// lib/screens/booking_flow/transport_estimate.dart
//
// Frais de déplacement avant validation (miroir de frontend/src/components/transport/TransportEstimate.tsx) : montant et créneaux
// calculés par le serveur (tarifs, distance routière, heure d'Abidjan). Rien n'est affiché sans réponse du serveur ; le devis vu par
// le client est renvoyé à la réservation, que le serveur RECALCULE (écart => 409 `transport_changed`, rien n'est réservé).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/booking_flow/booking_format.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class TransportQuoteData {
  TransportQuoteData(this.json);
  final Map<String, dynamic> json;

  int get amount => (json['amount'] as num?)?.toInt() ?? 0;
  bool get applicable => json['applicable'] != false;

  /// Phrase claire décrivant le devis (jamais de montant sans explication).
  String get description {
    if (!applicable) return json['reason'] == 'no_travel' ? 'Cette prestation ne nécessite pas de déplacement.' : 'Aucun frais de déplacement n’est appliqué.';
    if (json['reason'] == 'within_threshold') return 'Lieu proche (moins de ${json['threshold_km']} km) : déplacement offert.';
    if (json['fallback'] == true) {
      return json['fallback_reason'] == 'distance_unavailable'
          ? 'Distance indisponible : forfait de déplacement appliqué.'
          : 'Aucun tarif horaire pour ce créneau : forfait de déplacement appliqué.';
    }
    final band = (json['band'] as Map?) ?? const {};
    return '${json['distance_km']} km${json['multiplier'] == 2 ? ' (aller-retour)' : ''} · tranche « ${band['name']} » ${band['rate_per_km']} FCFA/km';
  }
}

/// Devis recalculé renvoyé par un 409 `transport_changed`, sinon null.
TransportQuoteData? changedTransportQuote(Object error) {
  if (error is! ApiException || error.statusCode != 409) return null;
  try {
    final d = json.decode(error.body);
    if (d is Map && d['code'] == 'transport_changed' && d['quote'] is Map) return TransportQuoteData((d['quote'] as Map).cast<String, dynamic>());
  } catch (_) {}
  return null;
}

class TransportEstimateCard extends StatefulWidget {
  const TransportEstimateCard({super.key, required this.serviceId, required this.lat, required this.lng, required this.city, required this.when, required this.onQuote, this.notice, this.current});
  final String serviceId;
  final double? lat;
  final double? lng;
  final String city;
  final DateTime when;
  final ValueChanged<TransportQuoteData?> onQuote;
  final String? notice;

  /// Devis tenu par l'écran parent : après un 409 `transport_changed`, c'est lui (le nouveau montant) qui est affiché.
  final TransportQuoteData? current;

  @override
  State<TransportEstimateCard> createState() => _TransportEstimateCardState();
}

class _TransportEstimateCardState extends State<TransportEstimateCard> {
  Timer? _debounce;
  int _seq = 0;
  bool _loading = false;
  bool _failed = false;
  TransportQuoteData? _quote;
  List<Map<String, dynamic>> _slots = const [];

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(TransportEstimateCard old) {
    super.didUpdateWidget(old);
    if (old.lat != widget.lat || old.lng != widget.lng || old.when != widget.when || old.serviceId != widget.serviceId || old.city != widget.city) _schedule();
    // Un 409 du serveur impose un nouveau devis : il remplace celui qui est affiché.
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    if (widget.lat == null || widget.lng == null) {
      _quote = null;
      _slots = const [];
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onQuote(null));
      return;
    }
    final mine = ++_seq;
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final r = await context.read<DashboardApi>().post('/transport/quote/', {
          'service': int.tryParse(widget.serviceId) ?? widget.serviceId,
          'lat': widget.lat,
          'lng': widget.lng,
          'city': widget.city,
          'when': widget.when.toUtc().toIso8601String(),
        });
        if (!mounted || mine != _seq) return;
        final q = TransportQuoteData((r['quote'] as Map).cast<String, dynamic>());
        setState(() {
          _quote = q;
          _slots = ((r['suggestions'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          _failed = false;
        });
        widget.onQuote(q);
      } catch (_) {
        if (!mounted || mine != _seq) return;
        setState(() {
          _quote = null;
          _slots = const [];
          _failed = true;
        });
        widget.onQuote(null);
      } finally {
        if (mounted && mine == _seq) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lat == null || widget.lng == null) {
      return Text('Localisez le lieu pour voir les frais de déplacement.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft));
    }
    final shown = widget.notice != null ? (widget.current ?? _quote) : _quote;
    return TratraCard(
      variant: TratraCardVariant.soft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.notice != null) TratraAlert(tone: TratraAlertTone.warning, message: widget.notice!),
        if (_loading && _quote == null) const SizedBox(height: 24, child: LinearProgressIndicator()),
        if (_failed) Text('Les frais de déplacement ne peuvent pas être estimés pour le moment ; ils seront recalculés à la réservation.', style: TratraTheme.style(TtType.bodySm, color: TtColors.danger)),
        if (shown != null) ...[
          Row(children: [
            const Icon(Icons.local_shipping_outlined, size: 18, color: TtColors.primary),
            const SizedBox(width: TtSpace.s2),
            Text('Déplacement : ${formatFcfa(shown.amount.toDouble())}', style: TratraTheme.style(TtType.h3)),
          ]),
          const SizedBox(height: TtSpace.s1),
          Text(shown.description, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
          if (_slots.length > 1) ...[
            const SizedBox(height: TtSpace.s2),
            for (final s in _slots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${s['label']}', style: TratraTheme.style(TtType.bodySm)),
                  Text(formatFcfa(((s['amount'] as num?) ?? 0).toDouble()), style: TratraTheme.style(TtType.bodySm, color: TtColors.ink)),
                ]),
              ),
          ],
        ],
      ]),
    );
  }
}
