// lib/onboarding/voice_guide.dart
//
// Guide vocal de l'inscription accompagnée : lit chaque écran en français avec la synthèse vocale DU TÉLÉPHONE (aucun fournisseur en
// ligne, aucune IA, fonctionne sans réseau si la voix française est installée). Lecture automatique désactivable (préférence gardée),
// bouton « Réécouter » sur chaque écran. Sans voix française : le guide le dit simplement et l'écran reste utilisable.
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceGuide extends ChangeNotifier {
  VoiceGuide({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  static const _prefKey = 'tratra.voice.autoplay';

  bool _ready = false;
  bool available = false;
  bool autoplay = true;
  bool speaking = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      autoplay = (await SharedPreferences.getInstance()).getBool(_prefKey) ?? true;
    } catch (_) {}
    try {
      final fr = await _tts.isLanguageAvailable('fr-FR');
      available = fr == true || fr == 1;
      if (available) {
        await _tts.setLanguage('fr-FR');
        await _tts.setSpeechRate(0.45); // débit posé, plus facile à suivre
        await _tts.awaitSpeakCompletion(true);
      }
    } catch (_) {
      available = false;
    }
    notifyListeners();
  }

  Future<void> say(String text) async {
    if (!available || text.trim().isEmpty) return;
    try {
      await _tts.stop();
      speaking = true;
      notifyListeners();
      await _tts.speak(text);
    } catch (_) {
      // voix indisponible à l'instant : l'écran reste lisible
    } finally {
      speaking = false;
      notifyListeners();
    }
  }

  /// Lecture automatique d'un nouvel écran (si l'utilisateur ne l'a pas coupée).
  Future<void> auto(String text) async {
    if (autoplay) await say(text);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking = false;
    notifyListeners();
  }

  Future<void> setAutoplay(bool value) async {
    autoplay = value;
    notifyListeners();
    if (!value) await stop();
    try {
      (await SharedPreferences.getInstance()).setBool(_prefKey, value);
    } catch (_) {}
  }
}
