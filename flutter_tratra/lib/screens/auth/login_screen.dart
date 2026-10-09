import 'package:flutter/material.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  late final ApiService _apiService;
  late final StorageService _storageService;

  bool _isLoading = false;
  String? _error;
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _apiService = context.read<ApiService>();
    _storageService = context.read<StorageService>();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await _apiService.loginWithUsername(
        _usernameController.text.trim(),
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
      setState(() => _error = authErrorMessage(e));
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
              TratraInput(
                label: 'Email ou nom d’utilisateur',
                controller: _usernameController,
                leadingIcon: Icons.person_outline,
                autofillHints: const [AutofillHints.username],
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? "Nom d'utilisateur requis"
                    : null,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocusNode.requestFocus(),
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
              AuthNotice(
                title: 'Erreur de connexion',
                message: _error,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: TtSpace.s6),
              TratraButton(
                label: _isLoading ? 'Connexion…' : 'Se connecter',
                size: TratraButtonSize.lg,
                block: true,
                loading: _isLoading,
                trailing: const Icon(Icons.arrow_forward_rounded),
                onPressed: _login,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
