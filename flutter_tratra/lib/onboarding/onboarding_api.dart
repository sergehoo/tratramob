// lib/onboarding/onboarding_api.dart
//
// Inscription accompagnée : configuration publique du métier (questions, prestations, communes), brouillon et progression.
// AVANT la création du compte, les réponses sont gardées sur le téléphone (aucune donnée envoyée à un serveur sans compte) ; APRÈS, elles
// sont synchronisées avec Django (/me/onboarding/) pour reprendre sur n'importe quel appareil. Jamais de mot de passe dans le brouillon.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class OnbOption {
  OnbOption(Map<String, dynamic> j)
      : value = '${j['value'] ?? ''}',
        label = '${j['label'] ?? ''}',
        emoji = '${j['emoji'] ?? ''}';
  final String value;
  final String label;
  final String emoji;
}

class OnbQuestion {
  OnbQuestion(Map<String, dynamic> j)
      : key = '${j['key'] ?? ''}',
        text = '${j['text'] ?? ''}',
        help = '${j['help'] ?? ''}',
        multi = j['kind'] == 'multi',
        required = j['required'] != false,
        options = [
          for (final o in (j['options'] as List? ?? const []))
            if (o is Map) OnbOption(o.cast<String, dynamic>())
        ];
  final String key;
  final String text;
  final String help;
  final bool multi;
  final bool required;
  final List<OnbOption> options;
}

class OnbConfig {
  OnbConfig(Map<String, dynamic> j)
      : tradeId = (j['trade'] as Map?)?['id'] as int?,
        tradeName = '${(j['trade'] as Map?)?['name'] ?? ''}',
        prestations = [
          for (final p in (j['prestations'] as List? ?? const []))
            if (p is Map) (id: (p['id'] as num).toInt(), name: '${p['name']}'),
        ],
        questions = [
          for (final q in (j['questions'] as List? ?? const []))
            if (q is Map) OnbQuestion(q.cast<String, dynamic>())
        ],
        communes = [for (final c in (j['communes'] as List? ?? const [])) '$c'];
  final int? tradeId;
  final String tradeName;
  final List<({int id, String name})> prestations;
  final List<OnbQuestion> questions;
  final List<String> communes;
}

/// Brouillon du parcours (téléphone puis serveur) : métier, prestations, quartier, réponses, écran atteint, identité saisie.
class OnbDraft {
  OnbDraft({
    this.tradeId,
    this.tradeName = '',
    List<int>? prestations,
    this.commune = '',
    this.quartier = '',
    Map<String, dynamic>? answers,
    this.step = '',
    this.firstName = '',
    this.lastName = '',
    this.owner,
  })  : prestations = prestations ?? [],
        answers = answers ?? {};

  int? tradeId;
  String tradeName;
  List<int> prestations;
  String commune;
  String quartier;
  Map<String, dynamic> answers;
  String step;
  String firstName;
  String lastName;

  /// Compte auquel appartient un brouillon gardé sur le téléphone APRÈS la connexion (secours hors ligne) ; null = commencé sans compte.
  String? owner;

  bool get started => tradeId != null;

  Map<String, dynamic> toJson() => {
        'trade': tradeId,
        'trade_name': tradeName,
        'prestations': prestations,
        'commune': commune,
        'quartier': quartier,
        'answers': answers,
        'step': step,
        'first_name': firstName,
        'last_name': lastName,
        if (owner != null) 'owner': owner,
      };

  /// Ce que le serveur enregistre (les nom et prénom vont dans le compte, pas dans le brouillon serveur).
  Map<String, dynamic> toServer() =>
      {'trade': tradeId, 'prestations': prestations, 'commune': commune, 'quartier': quartier, 'answers': answers, 'step': step, 'path': 'guided'};

  factory OnbDraft.fromJson(Map<String, dynamic> j) => OnbDraft(
        tradeId: (j['trade'] as num?)?.toInt(),
        tradeName: '${j['trade_name'] ?? ''}',
        prestations: [
          for (final p in (j['prestations'] as List? ?? const []))
            if (p is num) p.toInt()
        ],
        commune: '${j['commune'] ?? ''}',
        quartier: '${j['quartier'] ?? ''}',
        answers: (j['answers'] as Map?)?.cast<String, dynamic>() ?? {},
        step: '${j['step'] ?? ''}',
        firstName: '${j['first_name'] ?? ''}',
        lastName: '${j['last_name'] ?? ''}',
        owner: j['owner']?.toString(),
      );

  /// Progression enregistrée sur le serveur (`GET /me/onboarding/`).
  factory OnbDraft.fromServer(Map<String, dynamic> j) => OnbDraft(
        tradeId: ((j['trade'] as Map?)?['id'] as num?)?.toInt(),
        tradeName: '${(j['trade'] as Map?)?['name'] ?? ''}',
        prestations: [
          for (final p in (j['prestations'] as List? ?? const []))
            if (p is num) p.toInt()
        ],
        commune: '${j['commune'] ?? ''}',
        quartier: '${j['quartier'] ?? ''}',
        answers: (j['answers'] as Map?)?.cast<String, dynamic>() ?? {},
        step: '${j['step'] ?? ''}',
      );
}

class OnbStep {
  OnbStep(Map<String, dynamic> j)
      : key = '${j['key']}',
        label = '${j['label']}',
        state = '${j['state']}';
  final String key;
  final String label;

  /// done | waiting | todo
  final String state;
}

class OnbState {
  OnbState(Map<String, dynamic> j)
      : steps = [
          for (final s in (j['steps'] as List? ?? const []))
            if (s is Map) OnbStep(s.cast<String, dynamic>())
        ],
        done = (j['done'] as num?)?.toInt() ?? 0,
        total = (j['total'] as num?)?.toInt() ?? 0,
        nextCode = '${(j['next_action'] as Map?)?['code'] ?? 'resume'}',
        nextLabel = '${(j['next_action'] as Map?)?['label'] ?? 'Continuer'}',
        nextStep = (j['next_action'] as Map?)?['step']?.toString(),
        published = j['published'] == true,
        offerTitle = (j['offer'] as Map?)?['title']?.toString(),
        offerDescription = (j['offer'] as Map?)?['description']?.toString(),
        draft = OnbDraft.fromServer(j);
  final List<OnbStep> steps;
  final int done;
  final int total;
  final String nextCode;
  final String nextLabel;
  final String? nextStep;
  final bool published;
  final String? offerTitle;
  final String? offerDescription;
  final OnbDraft draft;
}

class OnboardingApi {
  OnboardingApi(this._base) : _dash = DashboardApi(_base);
  final BaseApi _base;
  final DashboardApi _dash;
  static const _prefsKey = 'tratra.onboarding.draft.v1';

  Future<OnbConfig> config(int tradeId) async {
    final r = await _base.client.get(Uri.parse('${_base.baseUrl}/onboarding/config/?trade=$tradeId'), headers: await _base.getHeaders(withAuth: false));
    if (r.statusCode != 200) _base.handleError(r);
    final d = _base.decodeBody(r);
    return OnbConfig(d is Map ? d.cast<String, dynamic>() : <String, dynamic>{});
  }

  Future<OnbState> state() async => OnbState(await _dash.getMap('/me/onboarding/'));
  Future<OnbState> save(OnbDraft d) async => OnbState(await _dash.put('/me/onboarding/', d.toServer()));
  Future<OnbState> apply() async => OnbState(await _dash.post('/me/onboarding/apply/'));

  // --------------------------------------------------------------- brouillon local (avant le compte)

  Future<OnbDraft?> loadLocal() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null) return null;
      final j = jsonDecode(raw);
      return j is Map ? OnbDraft.fromJson(j.cast<String, dynamic>()) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocal(OnbDraft d) async {
    try {
      (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(d.toJson()));
    } catch (_) {}
  }

  Future<void> clearLocal() => clearStored();

  /// Déconnexion volontaire : aucun brouillon d'inscription ne reste sur le téléphone.
  static Future<void> clearStored() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_prefsKey);
    } catch (_) {}
  }

  /// Compte connecté : le brouillon du téléphone (commencé sans compte, ou gardé hors ligne pour CE compte) rejoint le serveur s'il n'y
  /// a rien encore (rien n'est perdu, même après une inscription classique), puis quitte le téléphone. Le brouillon d'un AUTRE compte
  /// n'est jamais envoyé. Renvoie l'état serveur.
  Future<OnbState> sync({String? userId}) async {
    final server = await state();
    final local = await loadLocal();
    if (local == null || !local.started) return server;
    if (local.owner != null && local.owner != userId) return server;
    if (server.draft.started) {
      await clearLocal();
      return server;
    }
    final saved = await save(local);
    await clearLocal();
    return saved;
  }
}
