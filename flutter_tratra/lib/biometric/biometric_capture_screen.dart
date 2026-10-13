// lib/biometric/biometric_capture_screen.dart
//
// Capture guidée en caméra avant : visage de face, rotation gauche/droite, inclinaison haut/bas, sourire — dans un ORDRE ALÉATOIRE choisi par le
// serveur pour chaque session. Chaque étape n'est gardée qu'après des mesures conformes consécutives (ML Kit), puis envoyée aussitôt au serveur
// (qui contrôle éclairage et netteté). Rien n'est enregistré dans la galerie ni conservé sur le téléphone. Le guidage n'est pas une preuve de
// présence réelle : le verdict vient du serveur et de son fournisseur de liveness.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:flutter_tratra/biometric/biometric_api.dart';
import 'package:flutter_tratra/biometric/liveness_guidance.dart';
import 'package:flutter_tratra/design/design.dart';

/// Issue de la capture : `done` (toutes les étapes envoyées), `denied` (caméra refusée), `camera` (caméra indisponible), `session` (session perdue), `cancelled`.
enum CaptureResult { done, denied, camera, session, cancelled }

class BiometricCaptureScreen extends StatefulWidget {
  const BiometricCaptureScreen({super.key, required this.api, required this.session});
  final BiometricApi api;
  final BiometricSessionInfo session;

  @override
  State<BiometricCaptureScreen> createState() => _BiometricCaptureScreenState();
}

class _BiometricCaptureScreenState extends State<BiometricCaptureScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  final FaceDetector _detector = FaceDetector(options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.fast));
  late final Set<int> _done = {...widget.session.captured};
  Guidance _guidance = const Guidance(false, 'Préparation de la caméra…');
  int _stable = 0;
  bool _uploading = false;
  bool _running = false;
  bool _closing = false;
  bool _starting = false;      // un seul démarrage de caméra à la fois (le dialogue de permission fait passer l'appli en pause puis en reprise)
  String? _notice;

  BiometricChallenge? get _current {
    for (final c in widget.session.challenges) {
      if (!_done.contains(c.index)) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _running = false;
    _cam?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _running = false;
      final c = _cam;
      _cam = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _cam == null && !_closing && !_starting) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    if (_starting) return;
    _starting = true;
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final controller = CameraController(front, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      if (!mounted || _closing) {
        await controller.dispose();
        return;
      }
      setState(() => _cam = controller);
      _running = true;
      unawaited(_loop());
    } on CameraException catch (e) {
      debugPrint('Caméra : ${e.code}');
      final denied = e.code.startsWith('CameraAccessDenied') || e.code == 'CameraAccessRestricted';
      _close(denied ? CaptureResult.denied : CaptureResult.camera);
    } catch (e) {
      debugPrint('Caméra : ${e.runtimeType}');
      _close(CaptureResult.camera);
    } finally {
      _starting = false;
    }
  }

  void _close(CaptureResult r) {
    if (_closing || !mounted) return;
    _closing = true;
    _running = false;
    Navigator.of(context).pop(r);
  }

  Future<void> _loop() async {
    while (_running && mounted && _current != null) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!_running || !mounted || _uploading) continue;
      try {
        await _sample();
      } catch (_) {
        // une mesure ratée n'interrompt pas la capture : on réessaie à la prochaine
      }
    }
    if (mounted && _current == null) _close(CaptureResult.done);
  }

  Future<void> _sample() async {
    final cam = _cam;
    final step = _current;
    if (cam == null || !cam.value.isInitialized || cam.value.isTakingPicture || step == null) return;
    final file = await cam.takePicture();
    try {
      final faces = await _detector.processImage(InputImage.fromFilePath(file.path));
      final bytes = await File(file.path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      final shortSide = (image.width < image.height ? image.width : image.height).toDouble();
      FaceMetrics? m;
      if (faces.isNotEmpty) {
        final f = faces.first;
        m = FaceMetrics(
          faces: faces.length,
          yaw: f.headEulerAngleY ?? 0,
          pitch: f.headEulerAngleX ?? 0,
          smile: f.smilingProbability,
          leftEyeOpen: f.leftEyeOpenProbability,
          rightEyeOpen: f.rightEyeOpenProbability,
          widthRatio: f.boundingBox.width / shortSide,
          centerX: f.boundingBox.center.dx / shortSide,
        );
      }
      final g = evaluate(step.kind, m);
      if (!mounted) return;
      setState(() {
        _guidance = g;
        _notice = null;
      });
      _stable = g.ok ? _stable + 1 : 0;
      if (_stable >= stableSamples) {
        _stable = 0;
        await _upload(step, bytes);
      }
    } finally {
      try {
        await File(file.path).delete();      // aucune image ne reste sur le téléphone
      } catch (_) {}
    }
  }

  Future<void> _upload(BiometricChallenge step, Uint8List bytes) async {
    setState(() => _uploading = true);
    try {
      await widget.api.uploadCapture(widget.session, index: step.index, kind: step.kind, bytes: bytes);
      if (!mounted) return;
      setState(() {
        _done.add(step.index);
        _guidance = const Guidance(false, 'Étape enregistrée');
      });
    } on BiometricApiException catch (e) {
      if (e.code == 'replayed') {
        _done.add(step.index);
      } else if (e.sessionLost) {
        _close(CaptureResult.session);
      } else if (mounted) {
        setState(() => _notice = e.detail);      // qualité insuffisante, image identique… : on recommence cette étape
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Connexion indisponible : vérifiez votre réseau, la capture reprend automatiquement.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _current;
    final total = widget.session.challenges.length;
    final cam = _cam;
    final status = _uploading ? 'Envoi sécurisé…' : (_notice ?? _guidance.hint);
    return Scaffold(
      backgroundColor: TtColors.night,
      appBar: AppBar(
        backgroundColor: TtColors.night,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Vérification faciale', style: TextStyle(color: Colors.white)),
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), tooltip: 'Annuler', onPressed: () => _close(CaptureResult.cancelled)),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s2, TtSpace.s4, TtSpace.s2),
            child: Column(children: [
              LinearProgressIndicator(value: total == 0 ? 0 : _done.length / total, color: TtColors.accent, backgroundColor: Colors.white24, minHeight: 6),
              const SizedBox(height: TtSpace.s2),
              Text('Étape ${(_done.length + 1).clamp(1, total)} sur $total', style: TratraTheme.style(TtType.caption, color: Colors.white70)),
            ]),
          ),
          Expanded(
            child: cam == null || !cam.value.isInitialized
                ? const Center(child: CircularProgressIndicator(color: TtColors.accent))
                : Stack(alignment: Alignment.center, children: [
                    Positioned.fill(child: ClipRect(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: cam.value.previewSize?.height ?? 1, height: cam.value.previewSize?.width ?? 1, child: CameraPreview(cam))))),
                    Positioned.fill(child: CustomPaint(painter: _OvalMask(ok: _guidance.ok))),
                  ]),
          ),
          Container(
            width: double.infinity,
            color: TtColors.night,
            padding: const EdgeInsets.all(TtSpace.s4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(step?.instruction ?? 'Capture terminée', textAlign: TextAlign.center, style: TratraTheme.style(TtType.h2, color: Colors.white)),
              const SizedBox(height: TtSpace.s1),
              Semantics(
                liveRegion: true,
                child: Text(status == step?.instruction ? ' ' : status, textAlign: TextAlign.center, style: TratraTheme.style(TtType.bodySm, color: _notice != null ? TtColors.accent : Colors.white70)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Masque sombre avec un ovale central : vert quand la consigne est respectée.
class _OvalMask extends CustomPainter {
  _OvalMask({required this.ok});
  final bool ok;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.46), width: size.width * 0.72, height: size.height * 0.62);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
    canvas.drawOval(oval, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = ok ? const Color(0xFF2E8B57) : Colors.white70);
  }

  @override
  bool shouldRepaint(covariant _OvalMask old) => old.ok != ok;
}
