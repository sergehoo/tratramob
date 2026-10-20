// lib/onboarding/guided_onboarding_screen.dart
//
// « Inscription accompagnée » : pour proposer ses services sans être à l'aise avec un smartphone.
//   • une question par écran, réponses en GROS boutons illustrés, langage simple, progression visible, retour arrière ;
//   • la voix du téléphone lit chaque écran (« Réécouter »), sans fournisseur en ligne ;
//   • d'abord le métier, la zone et quelques questions → aperçu de l'annonce rédigée automatiquement → ensuite seulement le compte
//     (prénom, nom, téléphone, mot de passe) et le code SMS → photo → vérification d'identité simplifiée ;
//   • tout est sauvegardé à chaque réponse : sur le téléphone avant le compte, puis sur le serveur ; reprise à l'écran atteint ;
//   • à tout moment : « Formulaire classique » (les réponses sont gardées).
// Mêmes données et mêmes règles que l'inscription classique (compte unique, rien n'est publié avant la vérification de l'équipe).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/phone/phone_value.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/onboarding/onboarding_api.dart';
import 'package:flutter_tratra/onboarding/voice_guide.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/otp_screen.dart';
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart' show authErrorMessage;
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart' show ProProfileScreen;
import 'package:flutter_tratra/screens/home/home_icons.dart' show categoryIconFor;
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';
import 'package:flutter_tratra/services/storage_service.dart';

/// Création du compte (remplaçable dans les tests) : renvoie vrai si le compte est créé ET connecté.
typedef OnbSignUp = Future<bool> Function(BuildContext context,
    {required String first, required String last, required PhoneValue phone, required String password});

/// Photo de profil (remplaçable dans les tests) : chemin du fichier pris, ou null.
typedef OnbPhotoPicker = Future<String?> Function();

class GuidedOnboardingScreen extends StatefulWidget {
  const GuidedOnboardingScreen({super.key, this.startAt, this.api, this.voice, this.signUp, this.photoPicker});

  /// Étape à rouvrir (`trade`, `zone`, `questions`, `phone`, `offer`, `photo`, `identity`), sinon l'écran enregistré.
  final String? startAt;
  final OnboardingApi? api;
  final VoiceGuide? voice;
  final OnbSignUp? signUp;
  final OnbPhotoPicker? photoPicker;

  @override
  State<GuidedOnboardingScreen> createState() => _GuidedOnboardingScreenState();
}

class _GuidedOnboardingScreenState extends State<GuidedOnboardingScreen> {
  late final BaseApi _base = context.read<BaseApi>();
  late final OnboardingApi _api = widget.api ?? OnboardingApi(_base);
  late final VoiceGuide _voice = widget.voice ?? VoiceGuide();
  OnbDraft _draft = OnbDraft();
  OnbConfig? _config;
  Catalog? _catalog;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _step = 'intro';
  bool _otherTrades = false;
  bool _otherCity = false;
  Timer? _saveTimer;
  OnbState? _final; // état serveur à la fin du parcours : ce qui reste vraiment à faire

  /// Compte auquel appartient ce parcours (null : commencé sans compte). Si la session change ou expire, plus rien n'est envoyé au
  /// serveur : les réponses restent sur le téléphone, rattachées à CE compte, et ne sont jamais montrées ni envoyées à un autre.
  String? _owner;
  late final Session _session = context.read<Session>();
  bool _sessionChanged = false;

  /// Dernier enregistrement impossible (réseau coupé, session expirée) : les réponses sont gardées sur le téléphone.
  String? _keptLocally;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _quartier = TextEditingController();
  final _city = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  PhoneValue _phone = PhoneValue.empty;
  String? _phoneError;
  bool _showPassword = true;

  bool get _signedIn => context.read<Session>().isAuthenticated;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _start();
  }

  void _onSession() {
    final id = _session.user?.id;
    if (_owner == null) {
      _owner = id; // compte créé (ou connexion) pendant le parcours : il devient le propriétaire
      return;
    }
    if (id == _owner || _sessionChanged) return;
    // Autre compte ou déconnexion : on garde les réponses pour LEUR compte, sur le téléphone, et on arrête d'envoyer quoi que ce soit.
    _saveTimer?.cancel();
    unawaited(_api.saveLocal(_draft..owner = _owner));
    unawaited(_voice.stop());
    if (mounted) setState(() => _sessionChanged = true);
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _saveTimer?.cancel();
    _voice.stop();
    for (final c in [_first, _last, _quartier, _city, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------ chargement et reprise

  Future<void> _start() async {
    unawaited(_voice.init().then((_) => _speak()));
    try {
      _catalog = await CatalogRepository.shared(_base).load();
    } catch (_) {}
    OnbDraft draft = await _api.loadLocal() ?? OnbDraft();
    if (!_signedIn && draft.owner != null) draft = OnbDraft(); // brouillon d'un compte (session terminée) : jamais montré sans lui
    if (_signedIn && mounted) {
      // Téléphone vérifié entre-temps (autre appareil, inscription classique) : jamais de code SMS demandé pour rien.
      final session = context.read<Session>();
      if (!(session.user?.isVerified ?? false)) await session.refreshProfile();
      if (!mounted) return;
      final me = session.user?.id;
      _owner = me;
      // Brouillon d'un autre compte, ou commencé sans compte avant la création de CE compte (téléphone partagé) : jamais montré.
      if (!draft.belongsTo(me, session.user?.dateJoined)) draft = OnbDraft();
      try {
        final server = await _api.sync(userId: me, joinedAt: session.user?.dateJoined);
        if (server.draft.started) draft = server.draft;
      } catch (_) {
        // hors ligne : le brouillon du téléphone suffit, il rejoindra le serveur plus tard
      }
    }
    final user = mounted ? context.read<Session>().user : null;
    _first.text = draft.firstName.isNotEmpty ? draft.firstName : (user?.firstName ?? '');
    _last.text = draft.lastName.isNotEmpty ? draft.lastName : (user?.lastName ?? '');
    _quartier.text = draft.quartier;
    if (draft.tradeId != null) {
      try {
        _config = await _api.config(draft.tradeId!);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _loading = false;
      _step = _resumeStep(widget.startAt ?? draft.step);
    });
    _speak();
  }

  String _resumeStep(String? wanted) {
    final steps = _steps;
    if (wanted == null || wanted.isEmpty) return steps.first;
    final aliases = {'zone': 'commune', 'questions': _firstQuestionStep, 'phone': 'verify', 'offer': 'preview', 'account': 'names'};
    final target = aliases[wanted] ?? wanted;
    // Écran déjà fait entre-temps (code SMS validé ailleurs…) : le suivant encore à faire.
    final all = _stepsFor(account: true, verify: true);
    return all.contains(target) ? all.skip(all.indexOf(target)).firstWhere(steps.contains, orElse: () => steps.first) : steps.first;
  }

  String get _firstQuestionStep => _config == null || _config!.questions.isEmpty ? 'preview' : 'q:${_config!.questions.first.key}';

  // ------------------------------------------------------------------ étapes

  bool get _phoneVerified => context.read<Session>().user?.isVerified ?? false;

  List<String> get _steps => _stepsFor(account: !_signedIn, verify: !_phoneVerified);

  /// Ordre complet du parcours ; les écrans de compte et de code SMS n'y figurent que s'ils restent à faire.
  List<String> _stepsFor({required bool account, required bool verify}) {
    return [
      'intro',
      'trade',
      if (_config != null && _config!.prestations.isNotEmpty) 'prestations',
      'commune',
      'quartier',
      for (final q in _config?.questions ?? const <OnbQuestion>[]) 'q:${q.key}',
      'preview',
      if (account) ...['names', 'phone', 'password'],
      if (verify) 'verify',
      'photo',
      'identity',
      'done',
    ];
  }

  OnbQuestion? _question(String step) {
    if (!step.startsWith('q:')) return null;
    final key = step.substring(2);
    for (final q in _config?.questions ?? const <OnbQuestion>[]) {
      if (q.key == key) return q;
    }
    return null;
  }

  // ------------------------------------------------------------------ voix

  String _speech(String step) {
    final q = _question(step);
    if (q != null) {
      final options = q.options.length <= 7 ? ' Les réponses possibles : ${q.options.map((o) => o.label).join(', ')}.' : '';
      return '${q.text} ${q.help}$options';
    }
    return switch (step) {
      'intro' => 'Bienvenue ! Nous allons créer votre annonce ensemble, pas à pas. Touchez les gros boutons pour répondre. '
          'Vous pouvez réécouter chaque question avec le bouton haut-parleur.',
      'trade' => 'Quel est votre métier ? Touchez la carte de votre métier.',
      'prestations' => 'Que proposez-vous exactement ? Touchez une ou plusieurs réponses.',
      'commune' => 'Dans quelle commune travaillez-vous ?',
      'quartier' => 'Dans quel quartier ? Vous pouvez aussi passer cette question.',
      'preview' => 'Voici votre annonce, écrite à partir de vos réponses. ${_offer.$1}. ${_offer.$2.join(' ')} '
          'Si elle vous convient, touchez « Mon annonce me convient ». Sinon, touchez « Changer mes réponses ».',
      'names' => 'Écrivez votre prénom et votre nom.',
      'phone' => 'Écrivez votre numéro de téléphone. Vous recevrez un code par SMS.',
      'password' => 'Choisissez un mot de passe. Il doit avoir au moins 8 caractères, avec une majuscule, une minuscule et un chiffre. Gardez-le bien.',
      'verify' => 'Nous allons vous envoyer un code par SMS pour confirmer votre numéro.',
      'photo' => 'Prenez une photo de votre visage, bien éclairé. Les clients aiment voir à qui ils confient leur maison.',
      'identity' => 'Dernière étape : photographiez votre carte d’identité ou votre passeport. L’équipe Tratra la vérifie.',
      'done' => '${_doneTexts.$1} ${_doneTexts.$2}',
      _ => '',
    };
  }

  void _speak() {
    if (!mounted || _loading) return;
    unawaited(_voice.auto(_speech(_step)));
  }

  // ------------------------------------------------------------------ sauvegarde

  /// Sans compte : sur le téléphone seulement. Avec un compte : sur le serveur ; hors ligne, sur le téléphone RATTACHÉ à ce compte
  /// (renvoyé au serveur à la prochaine ouverture, jamais à un autre compte).
  void _persist() {
    _draft
      ..step = _step
      ..firstName = _first.text.trim()
      ..lastName = _last.text.trim()
      ..quartier = _quartier.text.trim();
    if (_sessionChanged) return;
    if (!_signedIn) {
      unawaited(_api.saveLocal(_draft));
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      if (_sessionChanged) return;
      try {
        await _api.save(_draft);
        if (mounted && _keptLocally != null) setState(() => _keptLocally = null);
      } catch (e) {
        await _keepLocally(e);
      }
    });
  }

  /// Envoi impossible : les réponses restent sur le téléphone, rattachées au compte, et partiront au prochain enregistrement réussi.
  Future<void> _keepLocally(Object error) async {
    await _api.saveLocal(_draft..owner = _owner);
    if (!mounted) return;
    final expired = error is ApiException && error.statusCode == 401;
    setState(() => _keptLocally = expired
        ? 'Votre session a expiré : vos réponses sont gardées sur ce téléphone. Reconnectez-vous pour continuer.'
        : 'Pas de connexion pour l’instant : vos réponses sont gardées sur ce téléphone et seront envoyées dès le retour du réseau.');
  }

  // ------------------------------------------------------------------ navigation

  void _go(String step) {
    unawaited(_voice.stop());
    setState(() {
      _step = step;
      _error = null;
    });
    _persist();
    if (step == 'done' && _signedIn) {
      // Fin honnête : ce qui reste (photo, pièce d'identité) vient du serveur, jamais « c'est fini » si rien n'a été envoyé.
      _api.state().then((s) {
        if (mounted) setState(() => _final = s);
      }).catchError((_) {}).whenComplete(_speak);
      return;
    }
    _speak();
  }

  /// Titre et texte de la fin du parcours selon l'état serveur.
  (String, String) get _doneTexts {
    const todo = {'photo': 'ajouter votre photo', 'identity': 'faire vérifier votre pièce d’identité'};
    final remaining = [for (final s in _final?.steps ?? const <OnbStep>[]) if (s.state == 'todo' && todo.containsKey(s.key)) todo[s.key]!];
    if (remaining.isEmpty && _final?.experienceOk == false) {
      return ('Votre annonce est enregistrée', 'Elle ne pourra pas être publiée tant que votre expérience n’atteint pas le minimum demandé '
          'pour ce métier. Votre réponse est gardée telle quelle ; le détail est dans votre espace.');
    }
    if (remaining.isEmpty) {
      return ('Bravo, c’est presque fini !', 'Votre annonce est prête. Elle sera visible dès que l’équipe Tratra aura vérifié votre dossier. '
          'Vous recevrez une notification.');
    }
    return ('Votre annonce est enregistrée', 'Il vous reste à ${remaining.join(' et ')}. Votre annonce ne sera visible qu’après la '
        'vérification de votre identité. Vous pourrez continuer depuis votre espace avec le bouton « Continuer ».');
  }

  void _back() {
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    _go(steps[i - 1]);
  }

  bool get _canContinue {
    final q = _question(_step);
    if (q != null) {
      final a = _draft.answers[q.key];
      return !q.required || (q.multi ? (a is List && a.isNotEmpty) : a != null);
    }
    return switch (_step) {
      'trade' => _draft.tradeId != null,
      'prestations' => _draft.prestations.isNotEmpty,
      'commune' => _draft.commune.isNotEmpty,
      'names' => _first.text.trim().length >= 2 && _last.text.trim().length >= 2,
      'password' => _passwordRules.every((r) => r.$2) && _password.text == _confirm.text,
      _ => true,
    };
  }

  Future<void> _next() async {
    if (_busy || _sessionChanged) return;
    setState(() => _error = null);
    try {
      setState(() => _busy = true);
      switch (_step) {
        case 'trade':
          _config = await _api.config(_draft.tradeId!);
        case 'phone':
          final problem = _phone.error();
          if (problem != null) {
            setState(() => _phoneError = problem);
            return;
          }
        case 'password':
          final ok =
              await (widget.signUp ?? _defaultSignUp)(context, first: _first.text.trim(), last: _last.text.trim(), phone: _phone, password: _password.text);
          if (!ok || !mounted) return;
          await _api.save(_draft);
          await _api.clearLocal();
        case 'preview':
          if (_signedIn) {
            await _api.save(_draft);
          }
        case 'verify':
          // Vérifié = d'après le compte, quelle que soit la façon de quitter l'écran du code (bouton, retour du téléphone).
          if (!_phoneVerified) {
            await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => OtpScreen(autoSend: true, onDone: () => Navigator.of(ctx).pop())));
            if (!mounted || !_phoneVerified) return; // pas de code validé : on reste ici (« Plus tard » reste possible)
          }
          await _applyAnswers();
        case 'photo':
          break;
        default:
          break;
      }
      if (!mounted) return;
      // Étape suivante = la première, dans l'ordre complet du parcours, encore à faire (le métier choisi ajoute ses prestations et ses
      // questions ; les écrans de compte et de code SMS disparaissent une fois faits).
      final now = _steps;
      final all = _stepsFor(account: true, verify: true);
      final target = all.skip(all.indexOf(_step) + 1).firstWhere(now.contains, orElse: () => now.last);
      // Compte connecté et téléphone vérifié : l'annonce et le profil sont créés dès la fin des réponses.
      if (target == 'photo' && _step != 'verify') await _applyAnswers();
      _go(target);
    } catch (e) {
      if (_signedIn && _draft.started) await _keepLocally(e);
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failure(Object e) => e is ApiException && e.statusCode == 401
      ? 'Votre session a expiré. Vos réponses sont gardées sur ce téléphone : reconnectez-vous pour continuer.'
      : authErrorMessage(e);

  /// Code SMS remis à plus tard : l'annonce est quand même créée ; le tableau de bord proposera de confirmer le numéro.
  Future<void> _verifyLater() async {
    if (_busy || _sessionChanged) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _applyAnswers();
      if (mounted) _go('photo');
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAnswers() async {
    await _api.save(_draft);
    await _api.apply();
    await _api.clearLocal();
    if (mounted) unawaited(context.read<DashboardController>().load());
  }

  Future<bool> _defaultSignUp(BuildContext context, {required String first, required String last, required PhoneValue phone, required String password}) async {
    final apiService = context.read<ApiService>();
    final storage = context.read<StorageService>();
    final session = context.read<Session>();
    final user = await apiService.register(firstName: first, lastName: last, phone: phone.e164!, phoneCountry: phone.iso.name, password: password);
    final token = apiService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _error = 'Compte créé. Connectez-vous avec votre numéro et votre mot de passe pour continuer.');
      return false;
    }
    await storage.saveAuthToken(token);
    await storage.saveUserData(user);
    await session.setUser(user);
    return true;
  }

  Future<void> _takePhoto() async {
    if (_busy || _sessionChanged) return;
    setState(() => _error = null);
    String? path;
    try {
      path = await (widget.photoPicker ??
          () async =>
              (await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, imageQuality: 85, maxWidth: 1200))?.path)();
    } catch (_) {
      setState(() => _error = 'La caméra n’a pas pu s’ouvrir. Autorisez-la dans les réglages du téléphone.');
      return;
    }
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final dash = context.read<DashboardController>();
      final dashApi = context.read<DashboardApi>();
      await dash.load();
      final id = dash.data?.provider?.profileId;
      if (id == null) throw StateError('profil absent');
      await dashApi.patchFile('/handymen/$id/', 'photo', path);
      await dash.load();
      if (mounted) _go('identity');
    } catch (e) {
      if (mounted) setState(() => _error = 'La photo n’a pas pu être envoyée. Vérifiez votre connexion puis réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openIdentity() async {
    await _voice.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IdentityFlowScreen(simplified: true)));
    if (mounted) _go('done');
  }

  Future<void> _toClassic() async {
    await _voice.stop();
    _persist();
    if (!mounted) return;
    if (!_signedIn) {
      Navigator.of(context).pushReplacementNamed(RouteNames.register);
      return;
    }
    try {
      if (_draft.started) await _applyAnswers();
    } catch (_) {}
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProProfileScreen()));
  }

  // ------------------------------------------------------------------ affichage

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: TtColors.canvas, body: SafeArea(child: TratraSkeletonList(count: 4)));
    if (_sessionChanged) return _sessionChangedView();
    // Progression : les 9 étapes communes à l'application, au site et à Django ; à l'intérieur d'une étape, l'avancement des écrans.
    final steps = _steps;
    final milestone = journeyOf(_step);
    final mi = kJourney.indexWhere((j) => j.$1 == milestone);
    final group = [for (final st in steps) if (journeyOf(st) == milestone) st];
    final within = group.isEmpty ? 1.0 : (group.indexOf(_step) + 1).clamp(1, group.length) / group.length;
    final questions = [for (final st in steps) if (st.startsWith('q:')) st];
    final title = 'Étape ${mi + 1} sur ${kJourney.length} · ${kJourney[mi].$2}'
        '${_step.startsWith('q:') ? ' (${questions.indexOf(_step) + 1}/${questions.length})' : ''}';
    return ChangeNotifierProvider<VoiceGuide>.value(
      value: _voice,
      child: Scaffold(
        backgroundColor: TtColors.canvas,
        body: SafeArea(
          child: Column(children: [
            _TopBar(
              title: title,
              progress: ((mi + within) / kJourney.length).clamp(0.0, 1.0),
              onBack: _busy ? null : _back,
              onReplay: () => _voice.say(_speech(_step)),
              onClassic: _step == 'done' ? null : _toClassic,
            ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey('onb-step-$_step'),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_keptLocally != null) ...[
                    TratraAlert(key: const ValueKey('onb-kept-locally'), tone: TratraAlertTone.warning, message: _keptLocally!),
                    const SizedBox(height: TtSpace.s3),
                  ],
                  ..._content(_step),
                  if (_error != null) ...[
                    const SizedBox(height: TtSpace.s3),
                    TratraAlert(key: const ValueKey('onb-error'), tone: TratraAlertTone.danger, message: _error!)
                  ],
                ]),
              ),
            ),
            _BottomBar(
              label: switch (_step) {
                'intro' => 'Commencer',
                'password' => 'Créer mon compte',
                'verify' => 'Recevoir le code',
                'photo' => 'Prendre ma photo',
                'identity' => 'Photographier ma pièce',
                'done' => 'Aller à mon espace',
                'preview' => 'Mon annonce me convient',
                _ => 'Continuer',
              },
              busy: _busy,
              onPressed: !_canContinue
                  ? null
                  : switch (_step) {
                      'photo' => _takePhoto,
                      'identity' => _openIdentity,
                      'done' => () => Navigator.of(context).pushNamedAndRemoveUntil(RouteNames.home, (r) => false),
                      _ => _next,
                    },
              secondary: switch (_step) {
                'quartier' => ('Passer', _next),
                'verify' => ('Plus tard', _verifyLater),
                'photo' => ('Plus tard', () => _go('identity')),
                'identity' => ('Plus tard', () => _go('done')),
                _ => null,
              },
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _content(String step) {
    final q = _question(step);
    if (q != null) return _questionView(q);
    return switch (step) {
      'intro' => _intro(),
      'trade' => _trades(),
      'prestations' => _prestations(),
      'commune' => _communes(),
      'quartier' => [
          _Title('Dans quel quartier ?', help: 'Facultatif : cela aide les clients proches à vous trouver.'),
          TratraInput(
              key: const ValueKey('onb-quartier'),
              controller: _quartier,
              label: 'Quartier',
              hint: 'Ex. Riviera 2',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => _persist()),
        ],
      'preview' => _preview(),
      'names' => [
          _Title('Comment vous appelez-vous ?', help: 'Écrivez comme sur votre pièce d’identité.'),
          TratraInput(
              key: const ValueKey('onb-first'),
              controller: _first,
              label: 'Prénom',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(_persist)),
          const SizedBox(height: TtSpace.s3),
          TratraInput(
              key: const ValueKey('onb-last'),
              controller: _last,
              label: 'Nom',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(_persist)),
        ],
      'phone' => [
          _Title('Votre numéro de téléphone', help: 'Un code vous sera envoyé par SMS. Il servira aussi à vous connecter.'),
          TratraPhoneField(
              value: _phone,
              errorText: _phoneError,
              onChanged: (v) => setState(() {
                    _phone = v;
                    _phoneError = null;
                  })),
        ],
      'password' => _passwordView(),
      'verify' => [
          _Title('Confirmez votre numéro', help: 'Nous envoyons un code par SMS. Écrivez-le sur l’écran suivant.'),
          const _Illustration(icon: Icons.sms_outlined),
        ],
      'photo' => [
          _Title('Votre photo', help: 'Visage bien éclairé, sans lunettes de soleil. Les clients aiment savoir à qui ils ouvrent leur porte.'),
          const _Illustration(icon: Icons.face_retouching_natural_rounded),
        ],
      'identity' => [
          _Title('Vérifier votre identité',
              help: 'Photographiez votre carte d’identité (recto et verso) ou votre passeport. '
                  'L’équipe Tratra la vérifie : votre annonce devient visible après sa validation.'),
          const _Illustration(icon: Icons.badge_outlined),
          const SizedBox(height: TtSpace.s3),
          const _Reassurance('Vos papiers restent privés : seuls vous et l’équipe Tratra les voyez.'),
        ],
      'done' => [
          _Title(_doneTexts.$1, help: _doneTexts.$2),
          _Illustration(
            icon: _doneTexts.$1.startsWith('Bravo') ? Icons.celebration_rounded : Icons.bookmark_added_rounded,
            color: _doneTexts.$1.startsWith('Bravo') ? TtColors.accentDark : TtColors.primary,
          ),
        ],
      _ => const [],
    };
  }

  List<Widget> _intro() => [
        _Title('Proposez vos services, pas à pas',
            help: 'Quelques questions simples, une à la fois. Il suffit de toucher les gros boutons. '
                'Votre progression est sauvegardée : vous pourrez continuer plus tard.'),
        const _Illustration(icon: Icons.volunteer_activism_rounded),
        const SizedBox(height: TtSpace.s3),
        const _Reassurance('La voix lit chaque question. Touchez le haut-parleur pour réécouter.'),
        const SizedBox(height: TtSpace.s2),
        const _Reassurance('Rien n’est publié avant que l’équipe Tratra ait vérifié votre identité.'),
      ];

  List<Widget> _trades() {
    final catalog = _catalog;
    if (catalog == null) {
      return [
        const _Title('Quel est votre métier ?'),
        const TratraAlert(tone: TratraAlertTone.warning, message: 'Le catalogue des métiers n’a pas pu être chargé. Vérifiez votre connexion.')
      ];
    }
    final featured = catalog.homeTrades(fallbackLimit: 8);
    final shown = _otherTrades ? catalog.trades : featured;
    return [
      const _Title('Quel est votre métier ?', help: 'Touchez la carte de votre métier.'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: TtSpace.s2,
        crossAxisSpacing: TtSpace.s2,
        childAspectRatio: 1.25,
        children: [for (final t in shown) _TradeCard(trade: t, selected: _draft.tradeId?.toString() == t.id, onTap: () => _pickTrade(t))],
      ),
      if (!_otherTrades && catalog.trades.length > featured.length)
        TextButton(
            key: const ValueKey('onb-more-trades'),
            onPressed: () => setState(() => _otherTrades = true),
            child: const Text('Mon métier n’est pas dans la liste')),
    ];
  }

  void _pickTrade(Category t) {
    final id = int.parse(t.id);
    setState(() {
      if (_draft.tradeId != id) {
        _draft
          ..prestations = []
          ..answers = {};
      }
      _draft
        ..tradeId = id
        ..tradeName = t.name;
    });
    _persist();
  }

  List<Widget> _prestations() {
    final c = _config!;
    return [
      _Title('Que proposez-vous exactement ?', help: 'Touchez une ou plusieurs réponses.'),
      for (final p in c.prestations)
        _Choice(
          key: ValueKey('onb-prest-${p.id}'),
          label: p.name,
          selected: _draft.prestations.contains(p.id),
          multi: true,
          onTap: () {
            setState(() => _draft.prestations.contains(p.id) ? _draft.prestations.remove(p.id) : _draft.prestations.add(p.id));
            _persist();
          },
        ),
    ];
  }

  List<Widget> _communes() {
    final communes = _config?.communes ?? const <String>[];
    return [
      const _Title('Dans quelle commune travaillez-vous ?'),
      Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
        for (final c in communes)
          _Pill(
              key: ValueKey('onb-commune-$c'),
              label: c,
              selected: _draft.commune == c && !_otherCity,
              onTap: () {
                setState(() {
                  _otherCity = false;
                  _draft.commune = c;
                });
                _persist();
              }),
        _Pill(
            key: const ValueKey('onb-commune-other'),
            label: 'Autre ville',
            selected: _otherCity,
            onTap: () => setState(() {
                  _otherCity = true;
                  _draft.commune = _city.text.trim();
                })),
      ]),
      if (_otherCity) ...[
        const SizedBox(height: TtSpace.s3),
        TratraInput(
            key: const ValueKey('onb-city'),
            controller: _city,
            label: 'Ville ou commune',
            textCapitalization: TextCapitalization.words,
            onChanged: (v) {
              setState(() => _draft.commune = v.trim());
              _persist();
            }),
      ],
    ];
  }

  /// Expérience : la réponse est enregistrée telle quelle (jamais arrondie) ; le minimum du métier est annoncé AVANT de répondre.
  Widget _experienceNote() {
    final (min, what) = _config?.minimumFor(_draft.prestations) ?? (0, '');
    return Padding(
      padding: const EdgeInsets.only(bottom: TtSpace.s3),
      child: TratraAlert(
        key: const ValueKey('onb-experience-note'),
        tone: TratraAlertTone.info,
        message: min > 0
            ? 'Pour $what, Tratra demande au moins $min an${min > 1 ? 's' : ''} d’expérience pour publier une offre. '
                'Répondez selon la vérité : votre réponse est enregistrée telle quelle.'
            : 'Vous débutez ? C’est accepté pour ce métier. Répondez selon la vérité : votre réponse est enregistrée telle quelle.',
      ),
    );
  }

  List<Widget> _questionView(OnbQuestion q) => [
        _Title(q.text, help: q.help.isEmpty ? (q.multi ? 'Vous pouvez en choisir plusieurs.' : null) : q.help),
        if (q.target == 'experience') _experienceNote(),
        for (final o in q.options)
          _Choice(
            key: ValueKey('onb-opt-${q.key}-${o.value}'),
            label: o.label,
            emoji: o.emoji,
            multi: q.multi,
            selected: q.multi ? ((_draft.answers[q.key] as List?)?.contains(o.value) ?? false) : _draft.answers[q.key] == o.value,
            onTap: () {
              setState(() {
                if (q.multi) {
                  final list = List<String>.from((_draft.answers[q.key] as List?) ?? const []);
                  list.contains(o.value) ? list.remove(o.value) : list.add(o.value);
                  _draft.answers[q.key] = list;
                } else {
                  _draft.answers[q.key] = o.value;
                }
              });
              _persist();
            },
          ),
      ];

  (String, List<String>, String?) get _offer => offerPreview(_config, _draft..quartier = _quartier.text.trim());

  List<Widget> _preview() {
    final (title, lines, price) = _offer;
    return [
      const _Title('Votre annonce', help: 'Écrite à partir de vos réponses. Vous pourrez la modifier plus tard.'),
      TratraCard(
        key: const ValueKey('onb-offer'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TratraTheme.style(TtType.h3)),
          if (price != null) ...[const SizedBox(height: TtSpace.s2), TratraBadge(price, tone: TratraTone.primary)],
          const SizedBox(height: TtSpace.s2),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(l, style: TratraTheme.style(TtType.body, color: TtColors.inkSoft).copyWith(height: 1.4)),
            ),
        ]),
      ),
      const SizedBox(height: TtSpace.s3),
      if (_belowMinimum != null) ...[
        TratraAlert(key: const ValueKey('onb-experience-warning'), tone: TratraAlertTone.warning, message: _belowMinimum!),
        const SizedBox(height: TtSpace.s3),
      ],
      const _Reassurance('Elle sera visible des clients après la vérification de votre identité par l’équipe Tratra.'),
      TextButton(onPressed: () => _go(_firstQuestionStep), child: const Text('Changer mes réponses')),
    ];
  }

  /// Expérience déclarée sous le minimum du métier : dit AVANT de valider, sans jamais modifier la réponse.
  String? get _belowMinimum {
    final declared = declaredExperience(_config, _draft);
    final (min, what) = _config?.minimumFor(_draft.prestations) ?? (0, '');
    if (declared == null || declared.years >= min) return null;
    return 'Avec « ${declared.label} », votre annonce ne pourra pas être publiée : $what demande au moins $min an${min > 1 ? 's' : ''} '
        'd’expérience. Vos réponses sont gardées telles quelles ; vous pourrez la publier quand vous aurez l’expérience requise.';
  }

  Widget _sessionChangedView() {
    final signedIn = _signedIn;
    return Scaffold(
      backgroundColor: TtColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TtSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const _Illustration(icon: Icons.lock_person_outlined),
            const _Title('Votre session a changé',
                help: 'Vos réponses sont gardées sur ce téléphone pour le compte avec lequel vous aviez commencé. Elles ne sont ni montrées '
                    'ni envoyées à un autre compte. Reconnectez-vous avec ce compte pour continuer.'),
            const Spacer(),
            TratraButton(
              key: const ValueKey('onb-session-close'),
              label: signedIn ? 'Aller à mon espace' : 'Me reconnecter',
              size: TratraButtonSize.lg,
              block: true,
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(signedIn ? RouteNames.home : RouteNames.login, (r) => false),
            ),
          ]),
        ),
      ),
    );
  }

  static final _rules = <(String, bool Function(String))>[
    ('Au moins 8 caractères', (v) => v.length >= 8),
    ('Une majuscule (A, B, C…)', (v) => v.contains(RegExp(r'[A-Z]'))),
    ('Une minuscule (a, b, c…)', (v) => v.contains(RegExp(r'[a-z]'))),
    ('Un chiffre (1, 2, 3…)', (v) => v.contains(RegExp(r'[0-9]'))),
  ];

  List<(String, bool)> get _passwordRules => [for (final r in _rules) (r.$1, r.$2(_password.text))];

  List<Widget> _passwordView() => [
        const _Title('Choisissez votre mot de passe', help: 'Il vous servira à vous connecter avec votre numéro. Notez-le dans un endroit sûr.'),
        TratraInput(
            key: const ValueKey('onb-password'), controller: _password, label: 'Mot de passe', obscureText: !_showPassword, onChanged: (_) => setState(() {})),
        const SizedBox(height: TtSpace.s2),
        for (final (label, ok) in _passwordRules)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: ok ? TtColors.success : TtColors.fog),
              const SizedBox(width: TtSpace.s2),
              Text(label, style: TratraTheme.style(TtType.bodySm, color: ok ? TtColors.successInk : TtColors.inkSoft)),
            ]),
          ),
        const SizedBox(height: TtSpace.s3),
        TratraInput(
            key: const ValueKey('onb-confirm'),
            controller: _confirm,
            label: 'Écrivez-le une deuxième fois',
            obscureText: !_showPassword,
            errorText: _confirm.text.isNotEmpty && _confirm.text != _password.text ? 'Les deux mots de passe ne sont pas pareils.' : null,
            onChanged: (_) => setState(() {})),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _showPassword,
          onChanged: (v) => setState(() => _showPassword = v ?? true),
          title: const Text('Afficher le mot de passe'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ];
}

// ------------------------------------------------------------------ éléments visuels

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.progress, required this.onBack, required this.onReplay, required this.onClassic});
  final String title;
  final double progress;
  final VoidCallback? onBack;
  final VoidCallback onReplay;
  final VoidCallback? onClassic;

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceGuide>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(TtSpace.s1, TtSpace.s1, TtSpace.s2, 0),
      child: Column(children: [
        Row(children: [
          IconButton(tooltip: 'Retour', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(
            child: Text(title,
                key: const ValueKey('onb-progress'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w600)),
          ),
          if (voice.available) ...[
            IconButton(
              key: const ValueKey('onb-replay'),
              tooltip: 'Réécouter',
              onPressed: onReplay,
              icon: Icon(voice.speaking ? Icons.volume_up_rounded : Icons.replay_rounded, color: TtColors.primary),
            ),
            IconButton(
              key: const ValueKey('onb-voice-toggle'),
              tooltip: voice.autoplay ? 'Couper la voix' : 'Activer la voix',
              onPressed: () => voice.setAutoplay(!voice.autoplay),
              icon: Icon(voice.autoplay ? Icons.record_voice_over_rounded : Icons.voice_over_off_rounded, color: TtColors.ash),
            ),
          ],
          PopupMenuButton<String>(
            tooltip: 'Plus d’options',
            onSelected: (_) => onClassic?.call(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'classic', enabled: onClassic != null, child: const Text('Passer au formulaire classique')),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TtSpace.s3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(TtRadius.pill),
            child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: TtColors.lineSoft, color: TtColors.primary),
          ),
        ),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.label, required this.busy, required this.onPressed, this.secondary});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s3),
        decoration: const BoxDecoration(color: TtColors.surface, border: Border(top: BorderSide(color: TtColors.lineSoft))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TratraButton(key: const ValueKey('onb-continue'), label: label, size: TratraButtonSize.lg, block: true, loading: busy, onPressed: onPressed),
          if (secondary != null) TextButton(key: const ValueKey('onb-secondary'), onPressed: busy ? null : secondary!.$2, child: Text(secondary!.$1)),
        ]),
      );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.help});
  final String text;
  final String? help;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: TtSpace.s4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(text, style: TratraTheme.style(TtType.h2).copyWith(fontSize: 24, height: 1.25))),
          if (help != null && help!.isNotEmpty) ...[
            const SizedBox(height: TtSpace.s2),
            Text(help!, style: TratraTheme.style(TtType.body, color: TtColors.inkSoft).copyWith(fontSize: 17, height: 1.4)),
          ],
        ]),
      );
}

/// Réponse en GROS bouton (64 px minimum), avec illustration et coche.
class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.selected, required this.onTap, this.emoji = '', this.multi = false});
  final String label;
  final String emoji;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: TtSpace.s2),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: selected ? TtColors.primarySoft : TtColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TtRadius.panel),
              side: BorderSide(color: selected ? TtColors.primary : TtColors.line, width: selected ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(TtRadius.panel),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: TtSpace.s3, vertical: TtSpace.s2),
                  child: Row(children: [
                    if (emoji.isNotEmpty) ...[Text(emoji, style: const TextStyle(fontSize: 28)), const SizedBox(width: TtSpace.s3)],
                    Expanded(child: Text(label, style: TratraTheme.style(TtType.body).copyWith(fontSize: 18, fontWeight: FontWeight.w600))),
                    Icon(
                      selected ? Icons.check_circle_rounded : (multi ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded),
                      color: selected ? TtColors.primary : TtColors.fog,
                      size: 28,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _TradeCard extends StatelessWidget {
  const _TradeCard({required this.trade, required this.selected, required this.onTap});
  final Category trade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: trade.name,
        excludeSemantics: true,
        child: Material(
          key: ValueKey('onb-trade-${trade.id}'),
          color: selected ? TtColors.primarySoft : TtColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TtRadius.panel),
            side: BorderSide(color: selected ? TtColors.primary : TtColors.line, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(TtRadius.panel),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(TtSpace.s2),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                FaIcon(categoryIconFor(trade.iconKey), size: 32, color: TtColors.primary),
                const SizedBox(height: TtSpace.s2),
                Text(trade.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.body).copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? TtColors.primarySoft : TtColors.surface,
          shape: StadiumBorder(side: BorderSide(color: selected ? TtColors.primary : TtColors.line, width: selected ? 2 : 1)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52, minWidth: 96),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4, vertical: TtSpace.s2),
                child: Center(widthFactor: 1, child: Text(label, style: TratraTheme.style(TtType.body).copyWith(fontSize: 17, fontWeight: FontWeight.w600))),
              ),
            ),
          ),
        ),
      );
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.icon, this.color = TtColors.primary});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 120,
          height: 120,
          margin: const EdgeInsets.symmetric(vertical: TtSpace.s3),
          decoration: const BoxDecoration(color: TtColors.primarySoft, shape: BoxShape.circle),
          child: Icon(icon, size: 60, color: color),
        ),
      );
}

class _Reassurance extends StatelessWidget {
  const _Reassurance(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.verified_user_outlined, size: 20, color: TtColors.primary)),
        const SizedBox(width: TtSpace.s2),
        Expanded(child: Text(text, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft).copyWith(fontSize: 15))),
      ]);
}
