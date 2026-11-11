// lib/onboarding/onboarding_api.dart
//
// Inscription accompagnée : configuration publique du métier (questions, prestations, communes), brouillon et progression.
// Le compte est créé en premier ; les réponses sont ensuite synchronisées avec Django (/me/onboarding/) pour reprendre sur n'importe quel
// appareil. Hors ligne, elles restent sur le téléphone, rattachées au compte. Jamais de mot de passe dans le brouillon.
// L'état renvoyé par le serveur sépare trois niveaux : service publié, commandes activées, badge « Vérifié ».
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

class OnbOption {
  OnbOption(Map<String, dynamic> j)
      : value = '${j['value'] ?? ''}',
        label = '${j['label'] ?? ''}',
        emoji = '${j['emoji'] ?? ''}',
        phrase = '${j['phrase'] ?? ''}',
        years = (j['years'] as num?)?.toInt(),
        amount = (j['amount'] as num?)?.toInt(),
        unit = j['unit']?.toString();
  final String value;
  final String label;
  final String emoji;

  /// Formulation dans l'annonce (« soins des bébés »), années d'expérience, tarif proposé (montant + unité).
  final String phrase;
  final int? years;
  final int? amount;
  final String? unit;
}

class OnbQuestion {
  OnbQuestion(Map<String, dynamic> j)
      : key = '${j['key'] ?? ''}',
        text = '${j['text'] ?? ''}',
        help = '${j['help'] ?? ''}',
        target = '${j['target'] ?? ''}',
        multi = j['kind'] == 'multi',
        required = j['required'] != false,
        options = [
          for (final o in (j['options'] as List? ?? const []))
            if (o is Map) OnbOption(o.cast<String, dynamic>())
        ];
  final String key;
  final String text;
  final String help;

  /// experience | days | slots | strengths | price | info (handy/models.py OnboardingQuestion.target)
  final String target;
  final bool multi;
  final bool required;
  final List<OnbOption> options;
}

class OnbConfig {
  OnbConfig(Map<String, dynamic> j)
      : tradeId = (j['trade'] as Map?)?['id'] as int?,
        tradeName = '${(j['trade'] as Map?)?['name'] ?? ''}',
        minExperience = ((j['trade'] as Map?)?['min_experience_years'] as num?)?.toInt() ?? 0,
        prestations = [
          for (final p in (j['prestations'] as List? ?? const []))
            if (p is Map) (id: (p['id'] as num).toInt(), name: '${p['name']}', minExperience: (p['min_experience_years'] as num?)?.toInt() ?? 0),
        ],
        questions = [
          for (final q in (j['questions'] as List? ?? const []))
            if (q is Map) OnbQuestion(q.cast<String, dynamic>())
        ],
        communes = [for (final c in (j['communes'] as List? ?? const [])) '$c'];
  final int? tradeId;
  final String tradeName;

  /// Expérience exigée par le métier pour publier (0 = débutants acceptés) : réglée dans l'administration Django.
  final int minExperience;
  final List<({int id, String name, int minExperience})> prestations;
  final List<OnbQuestion> questions;
  final List<String> communes;

  /// Minimum du métier et des prestations choisies (même règle que handy/eligibility.py) : (années, nom du métier ou de la prestation).
  (int, String) minimumFor(List<int> chosen) {
    var best = (minExperience, minExperience > 0 ? tradeName : '');
    for (final p in prestations) {
      if (chosen.contains(p.id) && p.minExperience > best.$1) best = (p.minExperience, p.name);
    }
    return best;
  }
}

/// Expérience déclarée : libellé EXACT choisi (« Moins d’un an ») et années = borne basse de la tranche (handy/onboarding.py).
({int years, String label})? declaredExperience(OnbConfig? config, OnbDraft draft) {
  for (final q in config?.questions ?? const <OnbQuestion>[]) {
    if (q.target != 'experience') continue;
    for (final o in q.options) {
      if (draft.answers[q.key] == o.value) return (years: o.years ?? int.tryParse(o.value) ?? 0, label: o.label);
    }
  }
  return null;
}

/// Les 3 écrans de publication du premier service, après la création du compte (handy/onboarding.py PUBLISH_STEPS) : mêmes étapes
/// dans l'application, sur le site et dans Django.
const kJourney = [
  ('trade', 'Votre métier'),
  ('zone', 'Votre zone'),
  ('offer', 'Publication'),
];

/// Étape de publication d'un écran du parcours, ou null hors des trois écrans (compte, suite facultative, état du service).
String? journeyOf(String screen) => switch (screen) {
      'service' => 'trade',
      'zone' => 'zone',
      'confirm' => 'offer',
      _ => null,
    };

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
    this.startedAt,
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

  /// Début du brouillon sur ce téléphone : un brouillon commencé SANS compte ne rejoint qu'un compte créé APRÈS (même personne qui
  /// passe à l'inscription classique), jamais le compte existant d'une autre personne qui se connecte sur un téléphone partagé.
  DateTime? startedAt;

  bool get started => tradeId != null;

  /// Ce brouillon peut-il être montré au compte `userId` (créé le `joinedAt`) et envoyé à son nom ?
  bool belongsTo(String? userId, DateTime? joinedAt) {
    if (owner != null) return owner == userId;
    if (userId == null || joinedAt == null || startedAt == null) return false;
    return !joinedAt.isBefore(startedAt!.subtract(const Duration(minutes: 5))); // marge : horloges du téléphone et du serveur
  }

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
        if (startedAt != null) 'started_at': startedAt!.toUtc().toIso8601String(),
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
        startedAt: DateTime.tryParse('${j['started_at'] ?? ''}'),
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

// ------------------------------------------------------------------ aperçu de l'annonce (miroir de handy/onboarding.py offer_draft)

const _dayLabels = {'monday': 'lundi', 'tuesday': 'mardi', 'wednesday': 'mercredi', 'thursday': 'jeudi', 'friday': 'vendredi',
  'saturday': 'samedi', 'sunday': 'dimanche'};
const _slotLabels = {'morning': 'le matin', 'afternoon': 'l’après-midi', 'evening': 'le soir'};
const _unitLabels = {'hour': 'de l’heure', 'day': 'par jour', 'month': 'par mois', 'job': 'par intervention'};

String _join(List<String> items) {
  final l = items.where((i) => i.isNotEmpty).toList();
  if (l.isEmpty) return '';
  return l.length == 1 ? l.first : '${l.sublist(0, l.length - 1).join(', ')} et ${l.last}';
}

String _days(List<String> days) {
  final order = _dayLabels.keys.toList();
  final sorted = [...days]..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
  if (sorted.length == 7) return 'tous les jours';
  if (sorted.join(',') == order.take(5).join(',')) return 'du lundi au vendredi';
  if (sorted.join(',') == order.take(6).join(',')) return 'du lundi au samedi';
  return _join([for (final d in sorted) _dayLabels[d]!]);
}

String _amount(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Annonce rédigée à partir des réponses, SANS IA et sans réseau (aperçu avant le compte) : mêmes phrases que le serveur, qui rédige la
/// version enregistrée. Renvoie (titre, phrases, tarif à l'heure ou à l'intervention : affiché à part, comme sur l'offre).
(String, List<String>, String?) offerPreview(OnbConfig? config, OnbDraft draft) {
  final trade = draft.tradeName.isEmpty ? 'Services' : draft.tradeName;
  final prestations = [for (final p in config?.prestations ?? const <({int id, String name, int minExperience})>[]) if (draft.prestations.contains(p.id)) p.name];
  final label = prestations.length == 1 ? prestations.first : trade;
  final place = '${draft.commune}${draft.quartier.isEmpty ? '' : ' (${draft.quartier})'}';
  final lines = [draft.commune.isEmpty ? 'Je propose mes services de ${trade.toLowerCase()}.' : 'Je propose mes services de ${trade.toLowerCase()} à $place.'];
  if (prestations.length > 1) lines.add('Prestations : ${_join([for (final p in prestations) p.toLowerCase()])}.');
  final experience = declaredExperience(config, draft);
  final days = <String>[], slots = <String>[], strengths = <String>[], infos = <String>[];
  OnbOption? price;
  for (final q in config?.questions ?? const <OnbQuestion>[]) {
    final a = draft.answers[q.key];
    final values = a is List ? a.map((e) => '$e').toList() : (a == null ? const <String>[] : ['$a']);
    final chosen = [for (final o in q.options) if (values.contains(o.value)) o];
    if (chosen.isEmpty) continue;
    switch (q.target) {
      case 'days':
        days.addAll([for (final o in chosen) if (_dayLabels.containsKey(o.value)) o.value]);
      case 'slots':
        slots.addAll([for (final o in chosen) if (_slotLabels.containsKey(o.value)) o.value]);
      case 'strengths':
        strengths.addAll([for (final o in chosen) o.phrase.isNotEmpty ? o.phrase : o.label.toLowerCase()]);
      case 'info':
        infos.addAll([for (final o in chosen) o.phrase.isNotEmpty ? o.phrase : o.label]);
      case 'price':
        price = chosen.first;
    }
  }
  if (strengths.isNotEmpty) lines.add('Ce que je fais : ${_join(strengths)}.');
  if (infos.isNotEmpty) lines.add('${_capitalize(_join(infos))}.');
  if (days.isNotEmpty || slots.isNotEmpty) {
    final when = [if (days.isNotEmpty) _days(days), _join([for (final s in slots) _slotLabels[s]!])].where((x) => x.isNotEmpty).join(' ');
    lines.add('Disponible $when.');
  }
  if (experience != null && experience.label.isNotEmpty) {
    lines.add('Expérience : ${experience.label[0].toLowerCase()}${experience.label.substring(1)}.'); // déclaration exacte, jamais arrondie
  }
  final unit = price?.unit, amount = price?.amount;
  if ((unit == 'day' || unit == 'month') && amount != null && amount > 0) lines.add('Tarif souhaité : ${_amount(amount)} FCFA ${_unitLabels[unit]} (à discuter).');
  if (unit == 'quote') lines.add('Prix à discuter ensemble.');
  final fixed = (unit == 'hour' || unit == 'job') && amount != null && amount > 0 ? '${_amount(amount)} FCFA ${_unitLabels[unit]}' : null;
  return (draft.commune.isEmpty ? label : '$label à ${draft.commune}', lines, fixed);
}

class OnbStep {
  OnbStep(Map<String, dynamic> j)
      : key = '${j['key']}',
        label = '${j['label']}',
        state = '${j['state']}',
        status = '${j['status'] ?? ''}',
        benefit = '${j['benefit'] ?? ''}';
  final String key;
  final String label;

  /// done | waiting | todo
  final String state;

  /// État réel dit par le serveur (« Publié », « En cours de revue »…) et ce que l'étape apporte (publication, commandes, badge).
  final String status;
  final String benefit;
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
        applied = j['service_id'] != null,
        ordersEnabled = j['orders_enabled'] == true,
        verificationLevel = '${(j['verification'] as Map?)?['level'] ?? 'NON_VERIFIE'}',
        verificationLabel = '${(j['verification'] as Map?)?['label'] ?? 'Non vérifié'}',
        blocked = j['blocked'] is Map
            ? (code: '${(j['blocked'] as Map)['code'] ?? ''}', label: '${(j['blocked'] as Map)['label'] ?? ''}', hint: '${(j['blocked'] as Map)['hint'] ?? ''}')
            : null,
        publishDone = ((j['publish'] as Map?)?['done'] as num?)?.toInt() ?? 0,
        publishTotal = ((j['publish'] as Map?)?['total'] as num?)?.toInt() ?? kJourney.length,
        questionsDone = (j['optional'] as Map?)?['questions'] == true,
        photoDone = (j['optional'] as Map?)?['photo'] == true,
        offerTitle = (j['offer'] as Map?)?['title']?.toString(),
        offerDescription = (j['offer'] as Map?)?['description']?.toString(),
        experienceOk = (j['experience'] as Map?)?['ok'] != false,
        experienceTrade = '${(j['experience'] as Map?)?['trade'] ?? ''}',
        experienceMinimum = ((j['experience'] as Map?)?['minimum'] as num?)?.toInt() ?? 0,
        experienceDeclared = '${(j['experience'] as Map?)?['declared'] ?? ''}',
        draft = OnbDraft.fromServer(j);
  final List<OnbStep> steps;
  final int done;
  final int total;
  final String nextCode;
  final String nextLabel;
  final String? nextStep;
  /// Service visible des clients. Publié ne veut dire ni « commandes activées » ni « Vérifié » : trois niveaux distincts.
  final bool published;

  /// Le premier service a été créé à partir des réponses (publié ou non).
  final bool applied;

  /// Le professionnel peut recevoir des commandes (pièce d'identité approuvée, selon la politique du métier).
  final bool ordersEnabled;

  /// NON_VERIFIE | IDENTITE_VERIFIEE | VERIFIE — « Vérifié » uniquement après la vérification faciale.
  final String verificationLevel;
  final String verificationLabel;
  bool get verified => verificationLevel == 'VERIFIE';

  /// Motif réel d'une publication refusée (expérience minimale, suspension…), sinon null.
  final ({String code, String label, String hint})? blocked;

  /// Avancement des trois écrans de publication.
  final int publishDone;
  final int publishTotal;

  /// Compléments facultatifs : questions de détail répondues, photo de profil ajoutée.
  final bool questionsDone;
  final bool photoDone;
  final String? offerTitle;
  final String? offerDescription;

  /// Expérience déclarée au moins égale au minimum des métiers exercés (sinon publication bloquée : `next_action.code == 'blocked'`).
  final bool experienceOk;
  final String experienceTrade;
  final int experienceMinimum;
  final String experienceDeclared;
  final OnbDraft draft;

  /// Message honnête quand l'expérience déclarée est sous le minimum d'un métier exercé (null sinon).
  String? get experienceWarning => experienceOk
      ? null
      : '$experienceTrade demande au moins $experienceMinimum an${experienceMinimum > 1 ? 's' : ''} d’expérience pour publier. '
          'Votre déclaration${experienceDeclared.isEmpty ? '' : ' (« $experienceDeclared »)'} est gardée telle quelle.';
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
  Future<OnbState>? _saving;

  /// Enregistrements envoyés UN PAR UN, dans l'ordre (réseau lent : une ancienne réponse n'écrase jamais une plus récente). Le corps est
  /// figé à l'appel. Réussi : le serveur a la dernière version, le brouillon gardé sur le téléphone n'a plus lieu d'être.
  Future<OnbState> save(OnbDraft d) {
    final body = d.toServer();
    final previous = _saving;
    final run = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          // l'échec du précédent est traité par son appelant ; celui-ci part quand même
        }
      }
      final s = OnbState(await _dash.put('/me/onboarding/', body));
      await clearLocal();
      return s;
    }();
    _saving = run;
    return run;
  }
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
    d.startedAt ??= DateTime.now();
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
  Future<OnbState> sync({String? userId, DateTime? joinedAt}) async {
    final server = await state();
    final local = await loadLocal();
    if (local == null || !local.started) return server;
    if (!local.belongsTo(userId, joinedAt)) return server;       // autre compte, ou compte existant d'une autre personne : jamais
    // Gardé hors ligne pour CE compte : plus récent que le serveur (il n'existe que si un envoi a échoué). Commencé sans compte : il
    // ne complète qu'un serveur vide.
    if (server.draft.started && local.owner == null) {
      await clearLocal();
      return server;
    }
    return save(local..owner = null);
  }
}
