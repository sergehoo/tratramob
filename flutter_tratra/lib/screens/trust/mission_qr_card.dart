// lib/screens/trust/mission_qr_card.dart
//
// Artisan : QR de mission TEMPORAIRE (15 min, usage unique) à montrer au client à l'arrivée, avec suivi en direct
// de la confirmation. Client : bouton « Vérifier l'artisan » qui ouvre le scanner.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart' show friendlyError;
import 'package:flutter_tratra/screens/trust/identity_api.dart';
import 'package:flutter_tratra/screens/trust/scan_screen.dart';

String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String _when(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Carte « Identité à l'arrivée » de l'artisan (mission confirmée ou en cours).
class MissionQrCard extends StatefulWidget {
  const MissionQrCard({super.key, required this.bookingId});
  final int bookingId;
  @override
  State<MissionQrCard> createState() => _MissionQrCardState();
}

class _MissionQrCardState extends State<MissionQrCard> {
  late final IdentityApi _api = IdentityApi(context.read<BaseApi>());
  Map<String, dynamic>? _pass;
  Map<String, dynamic>? _identity;
  int _left = 0;
  int _ticks = 0;
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshIdentity();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshIdentity() async {
    try {
      final d = await _api.bookingIdentity(widget.bookingId);
      if (mounted) setState(() => _identity = d);
    } catch (_) {/* l'état est simplement rafraîchi au prochain passage */}
  }

  void _startTimer() {
    _timer?.cancel();
    _ticks = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = DateTime.tryParse('${_pass?['expires_at']}');
      if (end == null || !mounted) return;
      setState(() => _left = end.difference(DateTime.now()).inSeconds.clamp(0, 86400));
      if (++_ticks % 3 == 0) _refreshIdentity();
      if (_left == 0 || _identity?['verified'] == true) _timer?.cancel();
    });
  }

  Future<void> _show() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pass = await _api.issuePass(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _pass = pass;
        _left = (pass['ttl_seconds'] as num?)?.toInt() ?? 900;
        _busy = false;
      });
      _startTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'Le QR de mission n’a pas pu être généré. Réessayez dans un instant.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _identity?['verified'] == true;
    final expired = _pass != null && _left == 0;
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Identité à l’arrivée', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: 2),
        Text('Montrez ce QR au client : il confirme que vous êtes bien l’artisan attendu pour cette mission.',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s3),
        if (verified)
          TratraAlert(tone: TratraAlertTone.success, title: 'Identité confirmée par le client', message: _when(_identity?['verified_at']))
        else if (_pass != null && !expired) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(TtRadius.panel), border: Border.all(color: TtColors.lineSoft)),
              child: Image.memory(dataUrlBytes('${_pass!['qr']}'), width: 220, height: 220, filterQuality: FilterQuality.none, semanticLabel: 'QR de mission Tratra'),
            ),
          ),
          const SizedBox(height: TtSpace.s2),
          Center(child: Text('Valable encore ${_clock(_left)} · à usage unique', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
          const SizedBox(height: TtSpace.s2),
          TratraButton(label: 'Générer un nouveau QR', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, block: true, loading: _busy, onPressed: _show),
        ] else ...[
          if (expired) ...[const TratraAlert(tone: TratraAlertTone.warning, message: 'Ce QR a expiré. Générez-en un nouveau.'), const SizedBox(height: TtSpace.s2)],
          TratraButton(label: 'Afficher mon QR de mission', block: true, loading: _busy, leading: const Icon(Icons.qr_code_2_rounded), onPressed: _show),
        ],
        if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
      ]),
    );
  }
}

/// Carte « Vérifier l'artisan » du client : état de la vérification + accès au scanner.
class IdentityVerifyCard extends StatefulWidget {
  const IdentityVerifyCard({super.key, required this.bookingId, required this.active});
  final int bookingId;

  /// Réservation confirmée ou en cours (la vérification n'a de sens qu'alors).
  final bool active;
  @override
  State<IdentityVerifyCard> createState() => _IdentityVerifyCardState();
}

class _IdentityVerifyCardState extends State<IdentityVerifyCard> {
  late final IdentityApi _api = IdentityApi(context.read<BaseApi>());
  Map<String, dynamic>? _identity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.bookingIdentity(widget.bookingId);
      if (mounted) setState(() => _identity = d);
    } catch (_) {/* carte simplement sans état */}
  }

  @override
  Widget build(BuildContext context) {
    final verified = _identity?['verified'] == true;
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vérifier l’artisan à son arrivée', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: 2),
        Text('Confirmez que la personne présente est bien l’artisan de cette réservation.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s3),
        if (verified)
          TratraAlert(tone: TratraAlertTone.success, title: 'Identité déjà confirmée', message: _when(_identity?['verified_at']))
        else if (!widget.active)
          Text('La vérification est disponible lorsque la réservation est confirmée ou en cours.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))
        else ...[
          Text('Demandez à l’artisan d’afficher son QR de mission, puis scannez-le.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
          const SizedBox(height: TtSpace.s3),
          TratraButton(
            label: 'Scanner le QR de l’artisan',
            block: true,
            leading: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScanScreen()));
              _load();
            },
          ),
        ],
      ]),
    );
  }
}
