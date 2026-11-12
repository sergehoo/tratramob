// lib/onboarding/guided_onboarding_screen.dart
//
// « Inscription accompagnée » : publier son premier service en TROIS écrans, sans être à l'aise avec un smartphone.
//   • d'abord le compte (prénom, nom, téléphone, mot de passe, code SMS) — sauté s'il existe déjà : l'identité n'est saisie qu'une fois ;
//   • puis trois écrans : métier et prestations → zone → confirmation. Le service est publié tout de suite avec la mention
//     « Non vérifié » ; aucune commande n'est possible avant la vérification de la pièce d'identité ;
//   • ensuite, sur l'écran « Votre service » ou depuis l'espace : « Activer mes commandes » (pièce d'identité) puis « Obtenir le badge
//     Vérifié » (vérification faciale). Les questions de détail et la photo sont facultatives, complétables plus tard ;
//   • gros boutons, langage simple, voix du téléphone (« Réécouter »), sauvegarde à chaque réponse, reprise à l'écran atteint ;
//   • à tout moment : « Formulaire classique » (les réponses sont gardées).
// Les statuts affichés (publié, commandes, badge) viennent du serveur : jamais « Vérifié » sans vérification faciale validée.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/legal.dart';
import 'package:flutter_tratra/core/phone/phone_value.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/models/user.dart';
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

  /// Étape à rouvrir (`trade`, `zone`, `offer`, `phone`, `questions`, `photo`, `identity`, `face`), sinon l'écran enregistré.
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
  String _step = 'service';
  bool _otherCity = false;
  bool _configLoading = false;
  int _configRequest = 0;
  Timer? _saveTimer;

  /// État dit par le serveur (publié, commandes, badge, prochaine action) : seule source de l'écran « Votre service ».
  OnbState? _final;

  /// Compte auquel appartient ce parcours (null : pas encore de compte). Si la session change ou expire, plus rien n'est envoyé au
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
  final _search = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  PhoneValue _phone = PhoneValue.empty;
  String? _phoneError;
  bool _showPassword = true;
  bool _acceptTerms = false; // case « J'accepte les Conditions d'utilisation » : jamais précochée, exigée avant la création du compte
  String _termsVersion = LegalLinks.termsVersion;

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
    for (final c in [_first, _last, _quartier, _city, _search, _password, _confirm]) {
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
    OnbState? server;
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
        server = await _api.sync(userId: me, joinedAt: session.user?.dateJoined);
        if (server.draft.started) draft = server.draft;
      } catch (_) {
        // hors ligne : le brouillon du téléphone suffit, il rejoindra le serveur plus tard
      }
    }
    // Identité saisie une seule fois : celle du compte, jamais redemandée.
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
    final communes = _config?.communes ?? const <String>[];
    setState(() {
      _draft = draft;
      _final = server;
      _otherCity = draft.commune.isNotEmpty && communes.isNotEmpty && !communes.contains(draft.commune);
      if (_otherCity) _city.text = draft.commune;
      _loading = false;
      // Service déjà créé : on rouvre son état (statuts et prochaine action), pas les trois écrans de publication.
      _step = _resumeStep(widget.startAt ?? ((server?.applied ?? false) ? 'published' : draft.step));
    });
    _speak();
  }

  String _resumeStep(String? wanted) {
    final steps = _steps;
    if (!_signedIn) return 'names'; // le compte d'abord (le numéro et le mot de passe ne sont jamais gardés dans un brouillon)
    if (wanted == null || wanted.isEmpty) return steps.first;
    final aliases = {
      'account': 'names', 'phone': 'verify', 'trade': 'service', 'offer': 'confirm', 'questions': _firstQuestionStep,
      'identity': 'published', 'face': 'published',
      // Écrans du parcours précédent (brouillons enregistrés avant les trois écrans).
      'intro': 'service', 'prestations': 'service', 'commune': 'zone', 'quartier': 'zone', 'preview': 'confirm', 'done': 'published',
    };
    var target = aliases[wanted] ?? wanted;
    // Questions de détail et photo : facultatives, proposées une fois le service créé.
    if ((target.startsWith('q:') || target == 'photo') && !(_final?.applied ?? false) && widget.startAt == null) target = 'service';
    // Écran déjà fait entre-temps (code SMS validé ailleurs…) : le suivant encore à faire.
    final all = _stepsFor(account: true, verify: true);
    return all.contains(target) ? all.skip(all.indexOf(target)).firstWhere(steps.contains, orElse: () => steps.first) : steps.first;
  }

  String get _firstQuestionStep => _config == null || _config!.questions.isEmpty ? 'photo' : 'q:${_config!.questions.first.key}';

  // ------------------------------------------------------------------ étapes

  bool get _phoneVerified => context.read<Session>().user?.isVerified ?? false;

  List<String> get _steps => _stepsFor(account: !_signedIn, verify: !_phoneVerified);

  /// Ordre du parcours : compte et code SMS (seulement s'ils restent à faire), les TROIS écrans de publication, l'état du service,
  /// puis la suite facultative (questions de détail, photo).
  List<String> _stepsFor({required bool account, required bool verify}) {
    return [
      if (account) ...['names', 'phone', 'password'],
      if (verify) 'verify',
      'service',
      'zone',
      'confirm',
      'published',
      for (final q in _config?.questions ?? const <OnbQuestion>[]) 'q:${q.key}',
      'photo',
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

  /// Question d'expérience du métier : posée à la confirmation UNIQUEMENT si le métier exige un minimum pour publier.
  OnbQuestion? get _experienceQuestion {
    if ((_config?.minimumFor(_draft.prestations).$1 ?? 0) <= 0) return null;
    for (final q in _config?.questions ?? const <OnbQuestion>[]) {
      if (q.target == 'experience') return q;
    }
    return null;
  }

  // ------------------------------------------------------------------ voix

  String _speech(String step) {
    final q = _question(step);
    if (q != null) {
      final options = q.options.length <= 7 ? ' Les réponses possibles : ${q.options.map((o) => o.label).join(', ')}.' : '';
      return '${q.text} ${q.help}$options Cette question est facultative.';
    }
    return switch (step) {
      'names' => 'Écrivez votre prénom et votre nom, comme sur votre pièce d’identité. Vous ne les écrirez qu’une seule fois.',
      'phone' => 'Écrivez votre numéro de téléphone. Vous recevrez un code par SMS.',
      'password' => 'Choisissez un mot de passe. Il doit avoir au moins 8 caractères, avec une majuscule, une minuscule et un chiffre. Gardez-le bien. '
          'Puis lisez les conditions d’utilisation et cochez la case si vous les acceptez.',
      'verify' => 'Nous allons vous envoyer un code par SMS pour confirmer votre numéro.',
      'service' => _draft.tradeId == null
          ? 'Première étape sur trois. Quel est votre métier ? Touchez la carte de votre métier, ou écrivez-le dans la recherche.'
          : 'Vous avez choisi ${_draft.tradeName}. Si vous le souhaitez, touchez ce que vous proposez exactement. Puis touchez « Continuer ».',
      'zone' => 'Deuxième étape sur trois. Dans quelle commune travaillez-vous ? Vous pouvez aussi écrire votre quartier.',
      'confirm' => 'Dernière étape. Voici votre service. ${_offer.$1}. ${_offer.$2.join(' ')} '
          '${_experienceQuestion == null ? '' : '${_experienceQuestion!.text} '}'
          'Touchez « Publier mon service ». Les clients le verront tout de suite, avec la mention « Non vérifié ». '
          'Vous recevrez des commandes après la vérification de votre pièce d’identité.',
      'published' => '${_publishedTexts.$1}. ${_publishedTexts.$2}',
      'photo' => 'Prenez une photo de votre visage, bien éclairé. Les clients aiment voir à qui ils confient leur maison. C’est facultatif.',
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
    if (!_draft.started) return; // rien à enregistrer tant qu'aucun métier n'est choisi
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

  /// Refus du serveur (règle métier) : ce n'est pas une panne de réseau, rien à « garder pour plus tard ».
  static bool _refused(Object e) => e is ApiException && e.statusCode >= 400 && e.statusCode < 500 && e.statusCode != 401 && e.statusCode != 408;

  /// Envoi impossible : les réponses restent sur le téléphone, rattachées au compte, et partiront au prochain enregistrement réussi.
  Future<void> _keepLocally(Object error) async {
    if (_refused(error)) return;
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
    if (step == 'published' && _signedIn) {
      // Statuts honnêtes : publié, commandes, badge viennent du serveur — jamais « c'est fait » si rien n'a été envoyé.
      unawaited(_refreshState().whenComplete(_speak));
      return;
    }
    _speak();
  }

  Future<void> _refreshState() async {
    try {
      final s = await _api.state();
      if (mounted) setState(() => _final = s);
    } catch (_) {
      // hors ligne : l'écran ne dit que ce qui est sûr
    }
  }

  void _home() => Navigator.of(context).pushNamedAndRemoveUntil(RouteNames.home, (r) => false);

  /// Titre et texte de l'écran « Votre service » selon l'état serveur : publié / commandes / badge, sans jamais en promettre plus.
  (String, String) get _publishedTexts {
    final s = _final;
    if (s == null) {
      return ('Votre service est enregistré', 'Son état s’affichera dès le retour de la connexion. Vous le retrouverez dans votre espace.');
    }
    if (!s.published) {
      if (s.nextCode == 'verify_phone') {
        return ('Votre service est enregistré', 'Confirmez votre numéro de téléphone pour le rendre visible des clients.');
      }
      if (!s.experienceOk) {
        return ('Votre service n’est pas encore publié', s.experienceWarning!);
      }
      final why = [s.blocked?.label ?? '', s.blocked?.hint ?? ''].where((t) => t.isNotEmpty).join('. ');
      return ('Votre service n’est pas encore publié', why.isEmpty ? '${s.nextLabel}.' : '$why.');
    }
    if (s.verified) {
      return ('Votre profil est vérifié', 'Votre service est en ligne avec le badge « Vérifié » et vous pouvez recevoir des commandes.');
    }
    if (s.ordersEnabled) {
      return ('Vos commandes sont activées', 'Votre service est en ligne avec la mention « ${s.verificationLabel} ». '
          'Vous pouvez recevoir des réservations et des missions.');
    }
    return (
      'Votre service est en ligne',
      'Les clients le voient avec la mention « ${s.verificationLabel} ». '
          '${s.nextCode == 'wait' ? '${s.nextLabel}.' : 'Aucune commande pour l’instant : touchez « ${s.nextLabel} ».'}'
    );
  }

  /// Bouton principal de l'écran « Votre service » : la prochaine action dite par le serveur.
  (String, VoidCallback) get _publishedAction {
    final s = _final;
    if (s == null) return ('Aller à mon espace', _home);
    return switch (s.nextCode) {
      'verify_identity' => (s.nextLabel, _openIdentity),
      'verify_phone' => (s.nextLabel, _confirmPhone),
      'resume' || 'apply' => (s.nextLabel, () => _go(_resumeStep(s.nextStep))),
      _ => ('Aller à mon espace', _home),
    };
  }

  void _back() {
    final steps = _steps;
    final i = steps.indexOf(_step);
    // Service créé : le retour ne rouvre pas les écrans de publication.
    if (i <= 0 || _step == 'published') {
      Navigator.of(context).maybePop();
      return;
    }
    _go(steps[i - 1]);
  }

  bool get _canContinue {
    final q = _question(_step);
    if (q != null) {
      final a = _draft.answers[q.key];
      return q.multi ? (a is List && a.isNotEmpty) : a != null;
    }
    return switch (_step) {
      'names' => _first.text.trim().length >= 2 && _last.text.trim().length >= 2,
      'password' => _passwordRules.every((r) => r.$2) && _password.text == _confirm.text && _acceptTerms,
      'service' => _draft.tradeId != null,
      'zone' => _draft.commune.isNotEmpty,
      'confirm' => _experienceQuestion == null || _draft.answers[_experienceQuestion!.key] != null,
      _ => true,
    };
  }

  Future<void> _next({bool skip = false}) async {
    if (_busy || _sessionChanged) return;
    setState(() => _error = null);
    try {
      setState(() => _busy = true);
      switch (_step) {
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
          if (_draft.started) await _api.save(_draft);
          await _api.clearLocal();
        case 'verify':
          // Vérifié = d'après le compte, quelle que soit la façon de quitter l'écran du code (bouton, retour du téléphone).
          if (!skip && !_phoneVerified) {
            await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => OtpScreen(autoSend: true, onDone: () => Navigator.of(ctx).pop())));
            if (!mounted || !_phoneVerified) return; // pas de code validé : on reste ici (« Plus tard » reste possible)
          }
        case 'service':
          if (_config?.tradeId != _draft.tradeId) _config = await _api.config(_draft.tradeId!);
        case 'confirm':
          // Publication : le service est créé et visible tout de suite ; les commandes attendent la pièce d'identité.
          await _applyAnswers();
        default:
          break;
      }
      if (!mounted) return;
      if (_step == 'confirm' || (_step == 'verify' && (_final?.applied ?? false))) {
        _go('published');                                   // service déjà créé : le code confirmé, on revient à son état
        return;
      }
      final now = _steps;
      if (_step.startsWith('q:')) {
        // Suite facultative : après la dernière question, l'annonce est complétée (jamais écrasée si elle a été modifiée à la main).
        final next = now.skip(now.indexOf(_step) + 1).first;
        if (!next.startsWith('q:')) {
          await _applyAnswers();
          if (!mounted) return;
          _go((_final?.photoDone ?? false) ? 'published' : 'photo');
          return;
        }
        _go(next);
        return;
      }
      // Étape suivante = la première, dans l'ordre complet du parcours, encore à faire (les écrans de compte et de code SMS
      // disparaissent une fois faits).
      final all = _stepsFor(account: true, verify: true);
      _go(all.skip(all.indexOf(_step) + 1).firstWhere(now.contains, orElse: () => 'published'));
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

  Future<void> _applyAnswers() async {
    await _api.save(_draft);
    final s = await _api.apply();
    await _api.clearLocal();
    if (!mounted) return;
    setState(() => _final = s);
    unawaited(context.read<DashboardController>().load());
  }

  Future<bool> _defaultSignUp(BuildContext context, {required String first, required String last, required PhoneValue phone, required String password}) async {
    final apiService = context.read<ApiService>();
    final storage = context.read<StorageService>();
    final session = context.read<Session>();
    final User user;
    try {
      user = await apiService.register(
          firstName: first, lastName: last, phone: phone.e164!, phoneCountry: phone.iso.name, password: password,
          acceptTerms: _acceptTerms, termsVersion: _termsVersion);
    } catch (e) {
      final current = outdatedTermsVersion(e);
      if (current == null) rethrow;
      // Conditions modifiées depuis ce build : la personne relit la nouvelle version et recoche elle-même la case.
      if (mounted) {
        setState(() {
          _termsVersion = current;
          _acceptTerms = false;
          _error = 'Les conditions d’utilisation ont été mises à jour. Relisez-les, puis cochez à nouveau la case.';
        });
      }
      return false;
    }
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
      if (mounted) _go('published');
    } catch (e) {
      if (mounted) setState(() => _error = 'La photo n’a pas pu être envoyée. Vérifiez votre connexion puis réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// « Activer mes commandes » (pièce d'identité) ou « Obtenir le badge Vérifié » (vérification faciale) : le parcours d'identité
  /// reprend à l'étape utile ; au retour, les statuts sont relus sur le serveur.
  Future<void> _openIdentity() async {
    await _voice.stop();
    if (!mounted) return;
    final face = _final?.nextStep == 'face';
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => IdentityFlowScreen(simplified: true, initialStep: face ? 'face' : null)));
    if (!mounted) return;
    unawaited(context.read<DashboardController>().load());
    await _refreshState();
    _speak();
  }

  /// Code SMS remis à plus tard puis repris depuis « Votre service » : la publication suit la confirmation du numéro.
  Future<void> _confirmPhone() async {
    await _voice.stop();
    if (!mounted) return;
    if (!_phoneVerified) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => OtpScreen(autoSend: true, onDone: () => Navigator.of(ctx).pop())));
    }
    if (!mounted) return;
    unawaited(context.read<DashboardController>().load());
    await _refreshState();
    _speak();
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
      if (_draft.started && _draft.commune.isNotEmpty && _experienceQuestionAnswered) await _applyAnswers();
    } catch (_) {}
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProProfileScreen()));
  }

  bool get _experienceQuestionAnswered => _experienceQuestion == null || _draft.answers[_experienceQuestion!.key] != null;

  // ------------------------------------------------------------------ affichage

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: TtColors.canvas, body: SafeArea(child: TratraSkeletonList(count: 4)));
    if (_sessionChanged) return _sessionChangedView();
    // Progression : « Étape x sur 3 » pour les trois écrans de publication ; le compte avant, la suite facultative après.
    final milestone = journeyOf(_step);
    final mi = kJourney.indexWhere((j) => j.$1 == milestone);
    final questions = [for (final q in _config?.questions ?? const <OnbQuestion>[]) 'q:${q.key}'];
    final account = const ['names', 'phone', 'password', 'verify'];
    final (String title, double progress) = switch (_step) {
      _ when mi >= 0 => ('Étape ${mi + 1} sur ${kJourney.length} · ${kJourney[mi].$2}', (mi + 1) / (kJourney.length + 1)),
      'published' => ('Votre service', 1.0),
      'photo' => ('Facultatif · Votre photo', 1.0),
      _ when _step.startsWith('q:') => (
          'Facultatif · Vos réponses (${questions.indexOf(_step) + 1}/${questions.length})',
          (questions.indexOf(_step) + 1) / (questions.length + 1)
        ),
      _ => ('Votre compte', (account.indexOf(_step) + 1) / (account.length + 1)),
    };
    final (String actionLabel, VoidCallback action) = _step == 'published' ? _publishedAction : ('', _home);
    final later = _step == 'published' && action != _home;
    return ChangeNotifierProvider<VoiceGuide>.value(
      value: _voice,
      child: Scaffold(
        backgroundColor: TtColors.canvas,
        body: SafeArea(
          child: Column(children: [
            _TopBar(
              title: title,
              progress: progress.clamp(0.0, 1.0),
              onBack: _busy ? null : _back,
              onReplay: () => _voice.say(_speech(_step)),
              onClassic: _step == 'published' ? null : _toClassic,
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
                'password' => 'Créer mon compte',
                'verify' => 'Recevoir le code',
                'confirm' => 'Publier mon service',
                'photo' => 'Prendre ma photo',
                'published' => actionLabel,
                _ => 'Continuer',
              },
              busy: _busy,
              onPressed: !_canContinue
                  ? null
                  : switch (_step) {
                      'photo' => _takePhoto,
                      'published' => action,
                      _ => _next,
                    },
              secondary: switch (_step) {
                'verify' => ('Plus tard', () => _next(skip: true)),
                'photo' => ('Plus tard', () => _go('published')),
                'published' when later => ('Plus tard', _home),
                _ when _step.startsWith('q:') => ('Passer', () => _next(skip: true)),
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
      'service' => _service(),
      'zone' => _zone(),
      'confirm' => _confirmView(),
      'published' => _published(),
      'names' => [
          _Title('Comment vous appelez-vous ?', help: 'Écrivez comme sur votre pièce d’identité. Vous ne le saisirez qu’une seule fois.'),
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
          const SizedBox(height: TtSpace.s3),
          const _Reassurance('Sans numéro confirmé, votre service est enregistré mais reste invisible des clients.'),
        ],
      'photo' => [
          _Title('Votre photo', help: 'Visage bien éclairé, sans lunettes de soleil. Les clients aiment savoir à qui ils ouvrent leur porte.'),
          const _Illustration(icon: Icons.face_retouching_natural_rounded),
        ],
      _ => const [],
    };
  }

  // ------------------------------------------------------------------ écran 1 : métier et prestations

  List<Widget> _service() {
    final catalog = _catalog;
    if (catalog == null) {
      return [
        const _Title('Quel est votre métier ?'),
        const TratraAlert(tone: TratraAlertTone.warning, message: 'Le catalogue des métiers n’a pas pu être chargé. Vérifiez votre connexion.')
      ];
    }
    if (_draft.tradeId != null) return _prestations();
    final query = _search.text.trim();
    // Recherche sans accents ni majuscules, synonymes compris (« clim » → Climatisation) ; une prestation trouvée mène à son métier.
    final found = <Category>[];
    if (query.isNotEmpty) {
      for (final c in catalog.search(query)) {
        final trade = c.isTrade ? c : catalog.trades.where((t) => t.id == c.trade).firstOrNull;
        if (trade != null && !found.any((t) => t.id == trade.id)) found.add(trade);
      }
    }
    final shown = query.isEmpty ? catalog.homeTrades(fallbackLimit: 8) : found;
    final more = query.isEmpty && catalog.trades.length > shown.length;
    return [
      const _Title('Quel est votre métier ?', help: 'Touchez la carte de votre métier, ou écrivez-le.'),
      TratraInput(
          key: const ValueKey('onb-trade-search'),
          controller: _search,
          hint: 'Chercher un métier (ex. plombier, ménage)',
          leadingIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {})),
      const SizedBox(height: TtSpace.s3),
      if (shown.isEmpty)
        const TratraAlert(
            key: ValueKey('onb-trade-none'),
            tone: TratraAlertTone.info,
            message: 'Aucun métier ne correspond. Essayez un autre mot, ou effacez la recherche pour voir la liste.')
      else
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: TtSpace.s2,
          crossAxisSpacing: TtSpace.s2,
          childAspectRatio: 1.25,
          children: [for (final t in shown) _TradeCard(trade: t, selected: false, onTap: () => _pickTrade(t))],
        ),
      if (more) ...[
        const SizedBox(height: TtSpace.s2),
        _AllTrades(trades: catalog.trades, onPick: _pickTrade),
      ],
    ];
  }

  void _pickTrade(Category t) {
    final id = int.parse(t.id);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (_draft.tradeId != id) {
        _config = null;
        _draft
          ..prestations = []
          ..answers = {};
      }
      _draft
        ..tradeId = id
        ..tradeName = t.name;
      _search.clear();
    });
    _persist();
    if (_config == null) unawaited(_loadConfig(id));
    _speak();
  }

  void _changeTrade() {
    _configRequest++;
    setState(() {
      _config = null;
      _configLoading = false;
      _draft
        ..tradeId = null
        ..tradeName = ''
        ..prestations = []
        ..answers = {};
    });
    _speak();
  }

  /// Prestations du métier, chargées dès le choix (même écran). La dernière demande gagne si l'on change vite de métier.
  Future<void> _loadConfig(int tradeId) async {
    final request = ++_configRequest;
    setState(() => _configLoading = true);
    try {
      final c = await _api.config(tradeId);
      if (mounted && request == _configRequest) setState(() => _config = c);
    } catch (_) {
      // réseau : la configuration est redemandée au « Continuer »
    } finally {
      if (mounted && request == _configRequest) setState(() => _configLoading = false);
    }
  }

  List<Widget> _prestations() {
    final prestations = _config?.prestations ?? const <({int id, String name, int minExperience})>[];
    final all = prestations.isNotEmpty && prestations.every((p) => _draft.prestations.contains(p.id));
    return [
      TratraCard(
        key: const ValueKey('onb-trade-chosen'),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: TtColors.primary),
          const SizedBox(width: TtSpace.s2),
          Expanded(child: Text(_draft.tradeName, style: TratraTheme.style(TtType.h3))),
          TextButton(key: const ValueKey('onb-trade-change'), onPressed: _busy ? null : _changeTrade, child: const Text('Changer')),
        ]),
      ),
      const SizedBox(height: TtSpace.s4),
      if (_configLoading && _config == null)
        const TratraSkeletonList(count: 3)
      else if (prestations.isEmpty)
        const _Reassurance('Touchez « Continuer » pour choisir votre zone.')
      else ...[
        _Title('Que proposez-vous exactement ?', help: 'Facultatif : touchez une ou plusieurs réponses. Vous pourrez en ajouter plus tard.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('onb-prest-all'),
            onPressed: () {
              setState(() => _draft.prestations = all ? [] : [for (final p in prestations) p.id]);
              _persist();
            },
            icon: Icon(all ? Icons.remove_done_rounded : Icons.done_all_rounded),
            label: Text(all ? 'Tout retirer' : 'Tout choisir'),
          ),
        ),
        for (final p in prestations)
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
      ],
    ];
  }

  // ------------------------------------------------------------------ écran 2 : zone

  List<Widget> _zone() {
    final communes = _config?.communes ?? const <String>[];
    return [
      const _Title('Où travaillez-vous ?', help: 'Touchez votre commune.'),
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
      const SizedBox(height: TtSpace.s4),
      TratraInput(
          key: const ValueKey('onb-quartier'),
          controller: _quartier,
          label: 'Quartier',
          optional: true,
          hint: 'Ex. Riviera 2',
          helper: 'Aide les clients proches à vous trouver.',
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _persist()),
    ];
  }

  // ------------------------------------------------------------------ écran 3 : confirmation et publication

  (String, List<String>, String?) get _offer => offerPreview(_config, _draft..quartier = _quartier.text.trim());

  List<Widget> _confirmView() {
    final (title, lines, price) = _offer;
    final experience = _experienceQuestion;
    return [
      const _Title('Votre service', help: 'Écrit à partir de vos réponses. Vous pourrez le modifier et le compléter plus tard.'),
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
      if (experience != null) ...[
        // Métier à expérience minimale : la seule question indispensable avant de publier, posée ici (réponse gardée telle quelle).
        Text(experience.text, style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s2),
        _experienceNote(),
        ..._options(experience),
      ],
      if (_belowMinimum != null) ...[
        TratraAlert(key: const ValueKey('onb-experience-warning'), tone: TratraAlertTone.warning, message: _belowMinimum!),
        const SizedBox(height: TtSpace.s3),
      ],
      const _Reassurance('Visible des clients dès la publication, avec la mention « Non vérifié ».'),
      const SizedBox(height: TtSpace.s2),
      const _Reassurance('Aucune commande avant la vérification de votre pièce d’identité : vous l’activerez juste après.'),
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

  /// Expérience déclarée sous le minimum du métier : dit AVANT de valider, sans jamais modifier la réponse.
  String? get _belowMinimum {
    final declared = declaredExperience(_config, _draft);
    final (min, what) = _config?.minimumFor(_draft.prestations) ?? (0, '');
    if (declared == null || declared.years >= min) return null;
    return 'Avec « ${declared.label} », votre service sera enregistré mais pas publié : $what demande au moins $min an${min > 1 ? 's' : ''} '
        'd’expérience. Vos réponses sont gardées telles quelles ; vous pourrez le publier quand vous aurez l’expérience requise.';
  }

  // ------------------------------------------------------------------ état du service : publié / commandes / badge

  List<Widget> _published() {
    final s = _final;
    final (title, help) = _publishedTexts;
    final stages = [for (final st in s?.steps ?? const <OnbStep>[]) if (const {'offer', 'identity', 'face'}.contains(st.key)) st];
    final questions = _config?.questions.isNotEmpty ?? false;
    return [
      _Title(title, help: help),
      if (s != null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TratraBadge(
            s.published ? s.verificationLabel : 'Non publié',
            key: const ValueKey('onb-status'),
            icon: s.verified ? Icons.verified_rounded : null,
            tone: s.verified ? TratraTone.success : (s.published && s.ordersEnabled ? TratraTone.primary : TratraTone.gray),
          ),
        ),
        const SizedBox(height: TtSpace.s3),
        TratraCard(
          key: const ValueKey('onb-stages'),
          child: Column(children: [
            for (final (i, st) in stages.indexed) ...[if (i > 0) const Divider(height: TtSpace.s5), _StageRow(step: st)],
          ]),
        ),
        if (s.applied && ((questions && !s.questionsDone) || !s.photoDone)) ...[
          const SizedBox(height: TtSpace.s4),
          Text('Facultatif, quand vous voulez', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          if (questions && !s.questionsDone)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  key: const ValueKey('onb-more-questions'), onPressed: () => _go(_firstQuestionStep), child: const Text('Compléter mon annonce (jours, tarif…)')),
            ),
          if (!s.photoDone)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(key: const ValueKey('onb-more-photo'), onPressed: () => _go('photo'), child: const Text('Ajouter ma photo')),
            ),
        ],
      ],
    ];
  }

  // ------------------------------------------------------------------ suite facultative : questions de détail

  List<Widget> _options(OnbQuestion q) => [
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

  List<Widget> _questionView(OnbQuestion q) {
    final answer = _draft.answers[q.key];
    final chosen = answer is List ? answer : const [];   // choix unique : une chaîne, jamais une liste
    final all = q.multi && q.options.every((o) => chosen.contains(o.value));
    return [
      _Title(q.text, help: q.help.isEmpty ? (q.multi ? 'Vous pouvez en choisir plusieurs.' : null) : q.help),
      if (q.target == 'experience') _experienceNote(),
      // Longue liste à choix multiples (jours de la semaine…) : tout choisir d'un geste.
      if (q.multi && q.options.length >= 4)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('onb-all-${q.key}'),
            onPressed: () {
              setState(() => _draft.answers[q.key] = all ? <String>[] : [for (final o in q.options) o.value]);
              _persist();
            },
            icon: Icon(all ? Icons.remove_done_rounded : Icons.done_all_rounded),
            label: Text(all ? 'Tout retirer' : 'Tout choisir'),
          ),
        ),
      ..._options(q),
    ];
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
        const Divider(height: TtSpace.s5),
        TermsConsent(
          key: const ValueKey('onb-terms'),
          value: _acceptTerms,
          onChanged: (v) => setState(() {
            _acceptTerms = v;
            if (v) _error = null;
          }),
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
                    maxLines: 3,
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
  const _Illustration({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 120,
          height: 120,
          margin: const EdgeInsets.symmetric(vertical: TtSpace.s3),
          decoration: const BoxDecoration(color: TtColors.primarySoft, shape: BoxShape.circle),
          child: Icon(icon, size: 60, color: TtColors.primary),
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

/// Une étape de confiance (service publié, pièce d'identité, vérification faciale) : état réel et ce qu'elle apporte.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.step});
  final OnbStep step;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.state) {
      'done' => (Icons.check_circle_rounded, TtColors.success),
      'waiting' => (Icons.hourglass_top_rounded, TtColors.accentDark),
      _ => (Icons.radio_button_unchecked_rounded, TtColors.fog),
    };
    return Row(
      key: ValueKey('onb-stage-${step.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: TtSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.label, style: TratraTheme.style(TtType.body).copyWith(fontWeight: FontWeight.w700)),
            if (step.status.isNotEmpty) Text(step.status, style: TratraTheme.style(TtType.bodySm, color: color == TtColors.fog ? TtColors.inkSoft : color)),
            if (step.benefit.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(step.benefit, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft).copyWith(height: 1.35)),
            ],
          ]),
        ),
      ],
    );
  }
}

/// « Mon métier n'est pas dans la liste » : tous les métiers du catalogue, dans une feuille qui défile.
class _AllTrades extends StatelessWidget {
  const _AllTrades({required this.trades, required this.onPick});
  final List<Category> trades;
  final ValueChanged<Category> onPick;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: const ValueKey('onb-more-trades'),
      onPressed: () async {
        final picked = await showModalBottomSheet<Category>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            maxChildSize: 0.95,
            builder: (_, controller) => ListView.builder(
              controller: controller,
              itemCount: trades.length,
              itemBuilder: (_, i) => ListTile(
                key: ValueKey('onb-all-trade-${trades[i].id}'),
                leading: FaIcon(categoryIconFor(trades[i].iconKey), color: TtColors.primary, size: 20),
                title: Text(trades[i].name),
                onTap: () => Navigator.of(ctx).pop(trades[i]),
              ),
            ),
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: const Text('Mon métier n’est pas dans la liste'),
    );
  }
}
