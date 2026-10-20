import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/core/phone/phone_value.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/onboarding/onboarding_entry.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart';
import 'package:flutter_tratra/screens/auth/widgets/login_lock_notice.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fin du blocage connue (le serveur reste l'autorité) : revenir sur l'écran de connexion garde le décompte, sans nouvel essai.
DateTime? _rememberedLockEnd;
String _rememberedSupport = defaultSupportEmail;

/// Tests : oublie le blocage mémorisé entre deux scénarios.
@visibleForTesting
void resetRememberedLoginLock() {
  _rememberedLockEnd = null;
  _rememberedSupport = defaultSupportEmail;
}

class LoginScreen extends StatefulWidget {
  /// [now] : horloge injectable (tests) ; par défaut l'heure réelle.
  const LoginScreen({super.key, this.now});

  final DateTime Function()? now;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  // Connexion par téléphone (pays + numéro national) ; « identifiant ou e-mail » reste possible pour les anciens comptes.
  bool _byPhone = true;
  PhoneValue _phone = PhoneValue.empty;
  String? _phoneError;
  final _passwordController = TextEditingController();

  late final ApiService _apiService;
  late final StorageService _storageService;

  bool _isLoading = false;
  String? _error;
  final FocusNode _passwordFocusNode = FocusNode();

  // Blocage après trop de tentatives : fin du blocage + minuteur d'affichage (1 s).
  DateTime? _lockedUntil;
  int _secondsLeft = 0;
  Timer? _lockTimer;
  String _supportEmail = defaultSupportEmail;

  bool get _locked => _secondsLeft > 0;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _apiService = context.read<ApiService>();
    _storageService = context.read<StorageService>();
    final remembered = _rememberedLockEnd;
    if (remembered != null && remembered.isAfter(_now())) {
      _supportEmail = _rememberedSupport;
      _startLock(remembered, announce: false);
    }
  }

  /// Démarre (ou met à jour) le compte à rebours jusqu'à [until].
  void _startLock(DateTime until, {bool announce = true}) {
    _lockTimer?.cancel();
    _lockedUntil = until;
    _error = null;
    _tick();
    if (!_locked) return;
    if (announce) {
      SemanticsService.sendAnnouncement(View.of(context), 'Connexion bloquée après trop de tentatives. Consultez le support ou patientez ${formatCountdown(_secondsLeft)}.', TextDirection.ltr);
    }
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_tick);
      if (!_locked) _lockTimer?.cancel();
    });
  }

  void _tick() {
    final until = _lockedUntil;
    final left = until == null ? 0 : (until.difference(_now()).inMilliseconds / 1000).ceil();
    _secondsLeft = left > 0 ? left : 0;
    if (_secondsLeft == 0) {
      _lockedUntil = null;
      _rememberedLockEnd = null;
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri(scheme: 'mailto', path: _supportEmail, queryParameters: {'subject': 'Connexion bloquée'});
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* aucune application de messagerie */}
    if (!mounted) return;
    setState(() => _error = 'Écrivez-nous à $_supportEmail.');
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading || _locked) return;
    if (!_formKey.currentState!.validate()) return;
    // Numéro à rechercher : tolérant, un ancien numéro hors norme est retrouvé par le serveur.
    final identifier = _byPhone ? _phone.lookupE164 : _usernameController.text.trim();
    if (identifier == null) {
      setState(() => _phoneError = _phone.error() ?? 'Saisissez votre numéro de téléphone.');
      return;
    }
    setState(() {
      _phoneError = null;
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await _apiService.loginWithUsername(
        identifier,
        _passwordController.text,
      );

      final token = _apiService.authToken;
      if (token == null || token.isEmpty) {
        throw Exception("Jeton d'authentification manquant");
      }
      await _storageService.saveAuthToken(token);
      await _storageService.saveUserData(user);

      // Hydrate la session (rôle) et route selon le persona.
      if (!mounted) return;
      await context.read<Session>().setUser(user);

      if (!mounted) return;
      final route = context.read<Session>().homeRoute();
      Navigator.pushReplacementNamed(context, route);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.isLoginLocked) {
        // Bloqué : jamais « mot de passe incorrect » ; temps restant donné par le serveur.
        final until = _now().add(Duration(seconds: e.retryAfterSeconds!));
        _rememberedLockEnd = until;
        _rememberedSupport = e.supportEmail ?? defaultSupportEmail;
        setState(() {
          _supportEmail = _rememberedSupport;
          _startLock(until);
        });
        return;
      }
      setState(() {
        _error = (e is ApiException && (e.statusCode == 400 || e.statusCode == 401))
            ? 'Téléphone ou mot de passe incorrect.' // même message que le web
            : authErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      eyebrow: 'Mon espace',
      title: 'Connexion',
      subtitle: 'Accédez à votre espace Tratra.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Pas encore de compte ?',
            style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, RouteNames.register),
            child: const Text('Créer un compte'),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nounou, ménagère, jardinier… : inscription pas à pas, guidée à la voix (le formulaire classique reste disponible).
              Material(
                key: const ValueKey('login-guided'),
                color: TtColors.primarySoft,
                borderRadius: BorderRadius.circular(TtRadius.panel),
                child: InkWell(
                  borderRadius: BorderRadius.circular(TtRadius.panel),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingChoiceScreen())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: TtSpace.s3, vertical: TtSpace.s3),
                    child: Row(children: [
                      const Icon(Icons.record_voice_over_rounded, color: TtColors.primary),
                      const SizedBox(width: TtSpace.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Je veux proposer mes services', style: TratraTheme.style(TtType.body).copyWith(fontWeight: FontWeight.w700)),
                          Text('Inscription guidée, pas à pas', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: TtColors.primary),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: TtSpace.s5),
              if (_byPhone)
                TratraPhoneField(
                  key: const ValueKey('login-phone'),
                  value: _phone,
                  onChanged: (v) => setState(() {
                    _phone = v;
                    _phoneError = null;
                  }),
                  errorText: _phoneError,
                  autofillHints: const [AutofillHints.username, AutofillHints.telephoneNumberNational],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                )
              else
                TratraInput(
                  key: const ValueKey('login-identifier'),
                  label: 'Identifiant ou e-mail',
                  controller: _usernameController,
                  leadingIcon: Icons.person_outline,
                  autofillHints: const [AutofillHints.username],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Identifiant requis' : null,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('login-mode'),
                  onPressed: () => setState(() {
                    _byPhone = !_byPhone;
                    _phoneError = null;
                    _error = null;
                  }),
                  child: Text(_byPhone ? 'Ancien compte : identifiant ou e-mail' : 'Se connecter avec mon numéro de téléphone'),
                ),
              ),
              const SizedBox(height: TtSpace.s5),
              TratraInput(
                label: 'Mot de passe',
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                leadingIcon: Icons.lock_outline,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, RouteNames.forgotPassword),
                  child: const Text('Mot de passe oublié ?'),
                ),
              ),
              if (_locked)
                Padding(
                  padding: const EdgeInsets.only(top: TtSpace.s4),
                  child: LoginLockNotice(secondsLeft: _secondsLeft, onContactSupport: _contactSupport),
                ),
              AuthNotice(
                title: 'Erreur de connexion',
                message: _error,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: TtSpace.s6),
              TratraButton(
                label: _locked ? 'Réessayer dans ${formatCountdown(_secondsLeft)}' : (_isLoading ? 'Connexion…' : 'Se connecter'),
                size: TratraButtonSize.lg,
                block: true,
                loading: _isLoading,
                trailing: Icon(_locked ? Icons.lock_clock_outlined : Icons.arrow_forward_rounded),
                onPressed: _locked ? null : _login,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
