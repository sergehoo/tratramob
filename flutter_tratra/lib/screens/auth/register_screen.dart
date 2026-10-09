// Users/ogahserge/Documents/handy_tratra/flutter_tratra/lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart';
import 'package:flutter_tratra/services/api_service.dart';
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:provider/provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final ApiService _apiService;
  late final StorageService _storageService;

  bool _isLoading = false;
  bool _acceptTerms = false;
  bool _showTermsWarning = false;
  String? _error;

  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _apiService = context.read<ApiService>();
    _storageService = context.read<StorageService>();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _lastNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _usernameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      setState(() => _showTermsWarning = true);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await _apiService.register(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
      );

      final token = _apiService.authToken;
      if (token == null || token.isEmpty) {
        throw Exception("Jeton d'authentification manquant");
      }
      await _storageService.saveAuthToken(token);
      await _storageService.saveUserData(user);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, RouteNames.home);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Mot de passe requis';
    }
    if (value.length < 8) {
      return 'Le mot de passe doit contenir au moins 8 caractères';
    }
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Doit contenir une majuscule';
    }
    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Doit contenir une minuscule';
    }
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Doit contenir un chiffre';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Veuillez confirmer votre mot de passe';
    }
    if (value != _passwordController.text) {
      return 'Les mots de passe ne correspondent pas';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      eyebrow: 'Nouveau compte',
      title: 'Créer un compte',
      subtitle:
          'Rejoignez Tratra en quelques étapes. Tous les champs sont obligatoires.',
      onBack: () => Navigator.pop(context),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Déjà un compte ?',
            style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Se connecter'),
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
                label: 'Prénom',
                controller: _firstNameController,
                leadingIcon: Icons.person_outline,
                autofillHints: const [AutofillHints.givenName],
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Prénom requis' : null,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _lastNameFocusNode.requestFocus(),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraInput(
                label: 'Nom',
                controller: _lastNameController,
                focusNode: _lastNameFocusNode,
                leadingIcon: Icons.person_outline,
                autofillHints: const [AutofillHints.familyName],
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _emailFocusNode.requestFocus(),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraInput(
                label: 'Adresse email',
                controller: _emailController,
                focusNode: _emailFocusNode,
                keyboardType: TextInputType.emailAddress,
                leadingIcon: Icons.email_outlined,
                autofillHints: const [AutofillHints.email],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email requis';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                      .hasMatch(v.trim())) {
                    return "Format d'email invalide";
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _usernameFocusNode.requestFocus(),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraInput(
                label: "Nom d'utilisateur",
                controller: _usernameController,
                focusNode: _usernameFocusNode,
                leadingIcon: Icons.alternate_email_outlined,
                autofillHints: const [AutofillHints.newUsername],
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? "Nom d'utilisateur requis"
                    : null,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _phoneFocusNode.requestFocus(),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraInput(
                label: 'Téléphone',
                controller: _phoneController,
                focusNode: _phoneFocusNode,
                keyboardType: TextInputType.phone,
                leadingIcon: Icons.phone_outlined,
                autofillHints: const [AutofillHints.telephoneNumber],
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Numéro de téléphone requis'
                    : null,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _passwordFocusNode.requestFocus(),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraInput(
                label: 'Mot de passe',
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                leadingIcon: Icons.lock_outline,
                obscureText: true,
                helper:
                    '8 caractères minimum, avec une majuscule, une minuscule et un chiffre.',
                autofillHints: const [AutofillHints.newPassword],
                validator: _validatePassword,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _confirmPasswordFocusNode.requestFocus(),
              ),
              const SizedBox(height: TtSpace.s4),
              TratraInput(
                label: 'Confirmer le mot de passe',
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocusNode,
                leadingIcon: Icons.lock_outline,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: _validateConfirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _register(),
              ),
              const SizedBox(height: TtSpace.s3),
              CheckboxListTile(
                value: _acceptTerms,
                onChanged: (value) => setState(() {
                  _acceptTerms = value ?? false;
                  if (_acceptTerms) _showTermsWarning = false;
                }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                shape:
                    RoundedRectangleBorder(borderRadius: TtRadius.controlAll),
                title: Text(
                  'J’accepte les conditions d’utilisation et la politique de confidentialité.',
                  style:
                      TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
                ),
              ),
              AuthNotice(
                tone: TratraAlertTone.warning,
                message: _showTermsWarning
                    ? 'Veuillez accepter les conditions d’utilisation'
                    : null,
              ),
              AuthNotice(
                title: 'Erreur d’inscription',
                message: _error,
                onDismiss: () => setState(() => _error = null),
              ),
              const SizedBox(height: TtSpace.s6),
              TratraButton(
                label: _isLoading ? 'Création du compte…' : 'Créer mon compte',
                size: TratraButtonSize.lg,
                block: true,
                loading: _isLoading,
                trailing: const Icon(Icons.arrow_forward_rounded),
                onPressed: _register,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
