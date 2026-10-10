// lib/screens/trust/scan_screen.dart
//
// Scanner de QR Tratra : badge professionnel permanent (vérification publique) ou QR de mission d'une
// réservation (le client confirme l'artisan attendu, usage unique). Saisie manuelle en repli (caméra refusée,
// simulateur). Seul le code ou le jeton extrait est envoyé à l'API : l'URL du QR n'est jamais ouverte.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/trust/identity_api.dart';
import 'package:flutter_tratra/screens/trust/verify_result.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final IdentityApi _api = IdentityApi(context.read<BaseApi>());
  final MobileScannerController _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  final TextEditingController _manual = TextEditingController();
  IdentityOutcome? _outcome;
  String? _unrecognized;
  bool _busy = false;
  bool _manualMode = false;

  @override
  void dispose() {
    _camera.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (_busy || _outcome != null) return;
    final target = parseQr(raw);
    if (target == null) {
      setState(() => _unrecognized = 'Ce QR n’est pas un QR Tratra : ne vous fiez pas à ce badge.');
      return;
    }
    setState(() {
      _busy = true;
      _unrecognized = null;
    });
    await _camera.stop();
    final outcome = switch (target) {
      IdTarget(:final code) => await _api.verifyCode(code),
      PassTarget(:final token) => await _api.consumePass(token),
    };
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _busy = false;
    });
  }

  Future<void> _again() async {
    setState(() {
      _outcome = null;
      _unrecognized = null;
      _manual.clear();
    });
    if (!_manualMode) await _camera.start();
  }

  @override
  Widget build(BuildContext context) {
    return DashPage(
      title: 'Scanner un badge Tratra',
      body: ListView(
        padding: const EdgeInsets.all(TtSpace.s4),
        children: [
          if (_outcome != null) ...[
            VerifyResultView(outcome: _outcome!),
            const SizedBox(height: TtSpace.s3),
            TratraButton(label: 'Scanner un autre QR', variant: TratraButtonVariant.outline, block: true, leading: const Icon(Icons.qr_code_scanner_rounded), onPressed: _again),
          ] else ...[
            Text(
              'Scannez le badge d’un professionnel pour confirmer en direct qu’il est vérifié par Tratra, ou le QR de mission affiché par l’artisan à son arrivée.',
              style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
            ),
            const SizedBox(height: TtSpace.s3),
            if (!_manualMode)
              ClipRRect(
                borderRadius: BorderRadius.circular(TtRadius.card),
                child: SizedBox(
                  height: 340,
                  child: MobileScanner(
                    controller: _camera,
                    onDetect: (capture) {
                      final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                      if (raw != null) _handle(raw);
                    },
                    errorBuilder: (context, error) => Container(
                      color: TtColors.night,
                      padding: const EdgeInsets.all(TtSpace.s5),
                      alignment: Alignment.center,
                      child: Text(
                        'La caméra n’est pas disponible. Autorisez l’accès à la caméra dans les réglages, ou saisissez le code ci-dessous.',
                        textAlign: TextAlign.center,
                        style: TratraTheme.style(TtType.bodySm, color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: TtSpace.s3),
            if (_busy) const Center(child: Padding(padding: EdgeInsets.all(TtSpace.s3), child: CircularProgressIndicator())),
            if (_unrecognized != null) TratraAlert(tone: TratraAlertTone.warning, message: _unrecognized!),
            const SizedBox(height: TtSpace.s3),
            if (_manualMode) ...[
              TratraInput(controller: _manual, label: 'Code Tratra ID ou lien du QR', hint: 'TR-ABCD-EFGH', textInputAction: TextInputAction.done, onSubmitted: _handle),
              const SizedBox(height: TtSpace.s3),
              TratraButton(label: 'Vérifier', block: true, loading: _busy, onPressed: () => _handle(_manual.text)),
            ],
            const SizedBox(height: TtSpace.s2),
            TratraButton(
              label: _manualMode ? 'Utiliser la caméra' : 'Saisir le code à la main',
              variant: TratraButtonVariant.ghost,
              block: true,
              onPressed: () async {
                setState(() => _manualMode = !_manualMode);
                if (_manualMode) {
                  await _camera.stop();
                } else {
                  await _camera.start();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
