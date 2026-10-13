// lib/messaging/media_widgets.dart
//
// Affichage des médias de la messagerie et des statuts : URL résolue contre l'origine de l'API quand elle est relative (stockage local de
// développement), lecteur vidéo plein écran, identifiant d'envoi idempotent.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';

String resolveMediaUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return '${Uri.parse(AppConstants.baseUrl).origin}${url.startsWith('/') ? '' : '/'}$url';
}

/// UUID v4 (identifiant d'envoi) : un renvoi après coupure réseau réutilise le même, le serveur ne crée jamais de doublon.
String newClientId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

/// Lecteur vidéo simple (lecture/pause, barre de progression) pour une vidéo de message.
class ChatVideoScreen extends StatefulWidget {
  const ChatVideoScreen({super.key, required this.url});
  final String url;
  @override
  State<ChatVideoScreen> createState() => _ChatVideoScreenState();
}

class _ChatVideoScreenState extends State<ChatVideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(resolveMediaUrl(widget.url)));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _c.play();
      }
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: _failed
            ? Text('Cette vidéo n’a pas pu être lue.', style: TratraTheme.style(TtType.body, color: Colors.white))
            : !_c.value.isInitialized
                ? const CircularProgressIndicator(color: TtColors.accent)
                : GestureDetector(
                    onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
                    child: AspectRatio(
                      aspectRatio: _c.value.aspectRatio,
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        VideoPlayer(_c),
                        VideoProgressIndicator(_c, allowScrubbing: true, colors: const VideoProgressColors(playedColor: TtColors.accent)),
                      ]),
                    ),
                  ),
      ),
    );
  }
}
