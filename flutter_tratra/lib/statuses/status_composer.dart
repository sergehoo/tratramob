// lib/statuses/status_composer.dart
//
// Publication rapide d'un statut : texte (couleur de fond), photo ou vidéo (avec légende), aperçu avant publication, compression de la photo
// (taille et qualité réduites par le sélecteur ; le serveur réencode de toute façon et retire les métadonnées), progression d'envoi et
// reprise après erreur réseau : le même `client_id` est renvoyé, le serveur ne publie jamais deux fois.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/network_errors.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/media_widgets.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_models.dart';

enum _Mode { text, photo, video }

class StatusComposerScreen extends StatefulWidget {
  const StatusComposerScreen({super.key, required this.limits});
  final StatusLimits limits;
  @override
  State<StatusComposerScreen> createState() => _StatusComposerScreenState();
}

class _StatusComposerScreenState extends State<StatusComposerScreen> {
  late final StatusApi _api = context.read<StatusApi>();
  final _text = TextEditingController();
  final _picker = ImagePicker();
  _Mode _mode = _Mode.text;
  String _background = 'green';
  XFile? _file;
  VideoPlayerController? _preview;
  String _audience = 'contacts';
  bool _replies = true;
  double _progress = 0;
  bool _busy = false;
  String? _error;
  String _clientId = newClientId();

  StatusLimits get _lim => widget.limits;

  @override
  void initState() {
    super.initState();
    _api.settings().then((s) {
      if (mounted) {
        setState(() {
          _audience = '${s['audience'] ?? 'contacts'}';
          _replies = s['allow_replies'] != false;
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _text.dispose();
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final XFile? f = _mode == _Mode.photo
          ? await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82)
          : await _picker.pickVideo(source: source, maxDuration: Duration(seconds: _lim.videoMaxSeconds));
      if (f == null) return;
      final size = await f.length();
      if (_mode == _Mode.photo && size > _lim.imageMaxBytes) return setState(() => _error = 'Photo trop lourde : ${_lim.imageMaxBytes ~/ 1048576} Mo au maximum.');
      if (_mode == _Mode.video) {
        if (size > _lim.videoMaxBytes) return setState(() => _error = 'Vidéo trop lourde : ${_lim.videoMaxBytes ~/ 1048576} Mo au maximum.');
        final c = VideoPlayerController.file(File(f.path));
        await c.initialize();
        if (c.value.duration.inMilliseconds > (_lim.videoMaxSeconds * 1000) + 500) {
          await c.dispose();
          return setState(() => _error = 'Vidéo trop longue (${c.value.duration.inSeconds} s) : ${_lim.videoMaxSeconds} secondes au maximum.');
        }
        await _preview?.dispose();
        _preview = c;
      }
      if (mounted) {
        setState(() {
          _file = f;
          _clientId = newClientId(); // nouveau contenu = nouvelle publication
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Ce fichier n’a pas pu être lu.');
    }
  }

  bool get _empty => _mode == _Mode.text ? _text.text.trim().isEmpty : _file == null;

  Future<void> _publish() async {
    if (_empty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final item = await _api.publish(
        text: _text.text.trim(),
        filePath: _mode == _Mode.text ? null : _file!.path,
        audience: _audience,
        allowReplies: _replies,
        background: _background,
        clientId: _clientId,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop(item);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e, st) {
      debugPrint('[statuts] publication échouée : ${e.runtimeType} $e\n$st');
      if (mounted) {
        setState(() => _error = transferFailureMessage(e, retryHint: 'Touchez « Réessayer » : votre statut ne sera publié qu’une seule fois.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _previewBox() {
    if (_mode == _Mode.text) {
      final c = statusBackgrounds[_background]!;
      return Container(
        height: 200,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(TtRadius.control)),
        child: Text(_text.text.isEmpty ? 'Votre texte apparaîtra ici' : _text.text, textAlign: TextAlign.center, style: TratraTheme.style(TtType.h3, color: c.fg)),
      );
    }
    if (_file == null) {
      return InkWell(
        onTap: () => _pick(ImageSource.gallery),
        child: Container(
          height: 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: TtColors.surface, border: Border.all(color: TtColors.line), borderRadius: BorderRadius.circular(TtRadius.control)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_mode == _Mode.photo ? Icons.photo_outlined : Icons.videocam_outlined, size: 36, color: TtColors.primary),
            const SizedBox(height: 8),
            Text(_mode == _Mode.photo ? 'Choisir une photo' : 'Choisir une vidéo (${_lim.videoMaxSeconds} s max.)', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          ]),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(TtRadius.control),
      child: SizedBox(
        height: 260,
        child: _mode == _Mode.photo
            ? Image.file(File(_file!.path), fit: BoxFit.contain)
            : (_preview != null && _preview!.value.isInitialized
                ? GestureDetector(onTap: () => setState(() => _preview!.value.isPlaying ? _preview!.pause() : _preview!.play()), child: Stack(alignment: Alignment.center, children: [VideoPlayer(_preview!), if (!_preview!.value.isPlaying) const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48)]))
                : const Center(child: CircularProgressIndicator())),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Nouveau statut'),
      body: ListView(padding: const EdgeInsets.all(TtSpace.s4), children: [
        Text('Visible ${_lim.ttlHours} h, puis supprimé automatiquement.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s3),
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.text, label: Text('Texte'), icon: Icon(Icons.text_fields_rounded)),
            ButtonSegment(value: _Mode.photo, label: Text('Photo'), icon: Icon(Icons.photo_camera_outlined)),
            ButtonSegment(value: _Mode.video, label: Text('Vidéo'), icon: Icon(Icons.videocam_outlined)),
          ],
          selected: {_mode},
          onSelectionChanged: _busy ? null : (s) => setState(() { _mode = s.first; _file = null; _preview?.dispose(); _preview = null; _error = null; }),
        ),
        const SizedBox(height: TtSpace.s3),
        _previewBox(),
        if (_mode != _Mode.text) ...[
          const SizedBox(height: TtSpace.s2),
          Row(children: [
            Expanded(child: TratraButton(label: 'Caméra', variant: TratraButtonVariant.outline, leading: const Icon(Icons.photo_camera_outlined, size: 18), onPressed: _busy ? null : () => _pick(ImageSource.camera))),
            const SizedBox(width: TtSpace.s2),
            Expanded(child: TratraButton(label: 'Galerie', variant: TratraButtonVariant.outline, leading: const Icon(Icons.photo_library_outlined, size: 18), onPressed: _busy ? null : () => _pick(ImageSource.gallery))),
          ]),
        ],
        const SizedBox(height: TtSpace.s3),
        TratraInput(
          controller: _text,
          label: _mode == _Mode.text ? 'Votre texte' : 'Légende (facultative)',
          maxLines: _mode == _Mode.text ? 4 : 2,
          minLines: 2,
          maxLength: _lim.textMax,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
        ),
        if (_mode == _Mode.text) ...[
          Wrap(spacing: 10, children: [
            for (final e in statusBackgrounds.entries)
              Semantics(
                label: e.value.label,
                selected: _background == e.key,
                child: GestureDetector(
                  onTap: _busy ? null : () => setState(() => _background = e.key),
                  child: Container(width: 36, height: 36, decoration: BoxDecoration(color: e.value.bg, shape: BoxShape.circle, border: Border.all(color: _background == e.key ? TtColors.primary : TtColors.line, width: _background == e.key ? 3 : 1))),
                ),
              ),
          ]),
        ],
        const SizedBox(height: TtSpace.s4),
        Text('Qui peut voir ce statut ?', style: TratraTheme.style(TtType.title)),
        RadioGroup<String>(
          groupValue: _audience,
          onChanged: (v) => setState(() => _audience = v ?? _audience),
          child: Column(children: [
            RadioListTile<String>(value: 'contacts', contentPadding: EdgeInsets.zero, title: const Text('Mes contacts Tratra'), subtitle: const Text('Membres avec qui vous avez une réservation, un contrat ou une conversation.')),
            RadioListTile<String>(value: 'extended', contentPadding: EdgeInsets.zero, title: const Text('Tous les membres'), subtitle: const Text('Aussi visible dans « Découvrir les statuts ».')),
          ]),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _replies, onChanged: _busy ? null : (v) => setState(() => _replies = v), title: const Text('Autoriser les réponses par message')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: TtSpace.s2), child: TratraAlert(tone: TratraAlertTone.danger, message: _error!)),
        if (_busy) Padding(padding: const EdgeInsets.only(top: TtSpace.s3), child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, color: TtColors.primary, minHeight: 6)),
        const SizedBox(height: TtSpace.s4),
        TratraButton(label: _error != null && !_busy ? 'Réessayer' : 'Publier', block: true, loading: _busy, onPressed: _empty ? null : _publish),
        const SizedBox(height: TtSpace.s8),
      ]),
    );
  }
}
