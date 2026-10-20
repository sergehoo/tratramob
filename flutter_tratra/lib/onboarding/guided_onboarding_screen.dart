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
    _start();
  }

  @override
  void dispose() {
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
    if (_signedIn) {
      final me = mounted ? context.read<Session>().user?.id : null;
      if (draft.owner != null && draft.owner != me) draft = OnbDraft(); // brouillon d'un autre compte : jamais montré
      try {
        final server = await _api.sync(userId: me);
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
    return steps.contains(target) ? target : steps.first;
  }

  String get _firstQuestionStep => _config == null || _config!.questions.isEmpty ? 'preview' : 'q:${_config!.questions.first.key}';

  // ------------------------------------------------------------------ étapes

  List<String> get _steps {
    final session = context.read<Session>();
    final user = session.user;
    return [
      'intro',
      'trade',
      if (_config != null && _config!.prestations.isNotEmpty) 'prestations',
      'commune',
      'quartier',
      for (final q in _config?.questions ?? const <OnbQuestion>[]) 'q:${q.key}',
      'preview',
      if (!session.isAuthenticated) ...['names', 'phone', 'password'],
      if (user == null || !user.isVerified) 'verify',
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
      'preview' => 'Voici votre annonce, écrite à partir de vos réponses. Si elle vous convient, touchez Continuer.',
      'names' => 'Écrivez votre prénom et votre nom.',
      'phone' => 'Écrivez votre numéro de téléphone. Vous recevrez un code par SMS.',
      'password' => 'Choisissez un mot de passe. Il doit avoir au moins 8 caractères, avec une majuscule, une minuscule et un chiffre. Gardez-le bien.',
      'verify' => 'Nous allons vous envoyer un code par SMS pour confirmer votre numéro.',
      'photo' => 'Prenez une photo de votre visage, bien éclairé. Les clients aiment voir à qui ils confient leur maison.',
      'identity' => 'Dernière étape : photographiez votre carte d’identité ou votre passeport. L’équipe Tratra la vérifie.',
      'done' => 'Bravo ! Votre annonce est prête. Elle sera visible dès que l’équipe Tratra aura vérifié votre dossier.',
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
    if (!_signedIn) {
      unawaited(_api.saveLocal(_draft));
      return;
    }
    final me = context.read<Session>().user?.id;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      _api.save(_draft).then((_) => _api.clearLocal(), onError: (_) => _api.saveLocal(_draft..owner = me));
    });
  }

  // ------------------------------------------------------------------ navigation

  void _go(String step) {
    unawaited(_voice.stop());
    setState(() {
      _step = step;
      _error = null;
    });
    _persist();
    _speak();
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
    if (_busy) return;
    final steps = _steps;
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
          final verified =
              await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (ctx) => OtpScreen(autoSend: true, onDone: () => Navigator.of(ctx).pop(true))));
          if (!mounted) return;
          if (verified != true) return;
          await _applyAnswers();
        case 'photo':
          break;
        default:
          break;
      }
      if (!mounted) return;
      // Étape suivante dans la NOUVELLE liste (le métier choisi ajoute ses prestations et ses questions) ; si l'écran courant en a
      // disparu (écrans de compte une fois connecté, code SMS une fois vérifié), la suivante de l'ancienne liste encore présente.
      final now = _steps;
      final j = now.indexOf(_step);
      final i = steps.indexOf(_step);
      final target = j >= 0 && j + 1 < now.length ? now[j + 1] : steps.skip(i + 1).firstWhere(now.contains, orElse: () => now.last);
      // Compte connecté et téléphone vérifié : l'annonce et le profil sont créés dès la fin des réponses.
      if (target == 'photo' && _step != 'verify') await _applyAnswers();
      _go(target);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
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
    final steps = _steps;
    final index = steps.indexOf(_step).clamp(0, steps.length - 1);
    return ChangeNotifierProvider<VoiceGuide>.value(
      value: _voice,
      child: Scaffold(
        backgroundColor: TtColors.canvas,
        body: SafeArea(
          child: Column(children: [
            _TopBar(
              index: index,
              total: steps.length,
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
          _Title('Bravo, c’est presque fini !',
              help: 'Votre annonce est prête. Elle sera visible dès que l’équipe Tratra aura vérifié votre dossier. '
                  'Vous recevrez une notification.'),
          const _Illustration(icon: Icons.celebration_rounded, color: TtColors.accentDark),
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

  List<Widget> _questionView(OnbQuestion q) => [
        _Title(q.text, help: q.help.isEmpty ? (q.multi ? 'Vous pouvez en choisir plusieurs.' : null) : q.help),
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

  List<Widget> _preview() {
    final offer = _localOffer();
    return [
      const _Title('Votre annonce', help: 'Écrite à partir de vos réponses. Vous pourrez la modifier plus tard.'),
      TratraCard(
        key: const ValueKey('onb-offer'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(offer.$1, style: TratraTheme.style(TtType.h3)),
          const SizedBox(height: TtSpace.s2),
          Text(offer.$2, style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)),
        ]),
      ),
      const SizedBox(height: TtSpace.s3),
      const _Reassurance('Elle sera visible des clients après la vérification de votre identité par l’équipe Tratra.'),
      TextButton(onPressed: () => _go(_firstQuestionStep), child: const Text('Changer mes réponses')),
    ];
  }

  /// Aperçu immédiat (même sans connexion) ; le serveur rédige la version définitive avec les mêmes réponses.
  (String, String) _localOffer() {
    final c = _config;
    final prest = c == null
        ? <String>[]
        : [
            for (final p in c.prestations)
              if (_draft.prestations.contains(p.id)) p.name
          ];
    final label = prest.length == 1 ? prest.first : _draft.tradeName;
    final place = _draft.commune.isEmpty ? '' : ' à ${_draft.commune}';
    final lines = <String>[
      'Je propose mes services de ${_draft.tradeName.toLowerCase()}$place${_quartier.text.trim().isEmpty ? '' : ' (${_quartier.text.trim()})'}.'
    ];
    for (final q in c?.questions ?? const <OnbQuestion>[]) {
      final a = _draft.answers[q.key];
      final labels = [
        for (final o in q.options)
          if (q.multi ? ((a as List?)?.contains(o.value) ?? false) : a == o.value) o.label
      ];
      if (labels.isNotEmpty) lines.add('${q.text.replaceAll('?', '').trim()} : ${labels.join(', ').toLowerCase()}.');
    }
    return ('$label$place', lines.join('\n'));
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
  const _TopBar({required this.index, required this.total, required this.onBack, required this.onReplay, required this.onClassic});
  final int index;
  final int total;
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
            child: Text('Étape ${index + 1} sur $total',
                key: const ValueKey('onb-progress'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w600)),
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
            child: LinearProgressIndicator(value: (index + 1) / total, minHeight: 8, backgroundColor: TtColors.lineSoft, color: TtColors.primary),
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
