// lib/screens/auth/forgot_password_screen.dart
//
// Récupération du compte par OTP (mêmes endpoints que le web) :
// POST /auth/password-reset/request/ puis /confirm/. Le numéro n'est jamais confirmé comme inscrit
// ou non ; aucun code n'est affiché ; l'échec d'envoi du SMS est annoncé clairement.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/auth/otp_screen.dart' show kOtpResendSeconds, maskPhone;
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart';
import 'package:flutter_tratra/services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phone = TextEditingController(text: '+225 ');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _code = '';
  int _attempt = 0;
  bool _sent = false;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  bool get _phoneOk => _phone.text.replaceAll(RegExp(r'\D'), '').length >= 8;

  Future<void> _request() async {
    if (!_phoneOk) {
      setState(() => _error = 'Numéro de téléphone invalide.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<AuthService>().requestPasswordReset(_phone.text.trim());
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code = '';
        _attempt++;
      });
      _startCooldown((r['resend_in'] as num?)?.toInt() ?? kOtpResendSeconds);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_code.length != 6) return;
    if (_password.text.length < 8) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().confirmPasswordReset(
            phone: _phone.text.trim(),
            code: _code,
            password: _password.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Mot de passe mis à jour. Connectez-vous avec votre numéro.'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = authErrorMessage(e);
          _code = '';
          _attempt++;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthFrame(
      eyebrow: 'Sécurité du compte',
      title: 'Mot de passe oublié',
      subtitle: 'Récupérez votre compte avec un code reçu par SMS.',
      onBack: () => Navigator.pop(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_sent) ...[
            Text(
              'Saisissez le numéro de votre compte : nous vous enverrons un code par SMS pour définir un nouveau mot de passe.',
              style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
            ),
            const SizedBox(height: TtSpace.s4),
            TratraInput(
              label: 'Téléphone',
              controller: _phone,
              keyboardType: TextInputType.phone,
              leadingIcon: Icons.phone_outlined,
              helper: 'Avec l’indicatif du pays : +225 pour la Côte d’Ivoire.',
              onSubmitted: (_) => _request(),
            ),
          ] else ...[
            Text(
              'Si ce numéro correspond à un compte, un code à 6 chiffres vient d’être envoyé au ${maskPhone(_phone.text.trim())}.',
              style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
            ),
            const SizedBox(height: TtSpace.s4),
            TratraOtpInput(
              key: ValueKey(_attempt),
              enabled: !_busy,
              hasError: _error != null,
              onChanged: (v) => setState(() {
                _code = v;
                if (_error != null) _error = null;
              }),
            ),
            const SizedBox(height: TtSpace.s4),
            TratraInput(label: 'Nouveau mot de passe', controller: _password, obscureText: true, leadingIcon: Icons.lock_outline,
                helper: '8 caractères minimum.'),
            const SizedBox(height: TtSpace.s4),
            TratraInput(label: 'Confirmer le mot de passe', controller: _confirm, obscureText: true, leadingIcon: Icons.lock_outline),
          ],
          if (_error != null) ...[
            const SizedBox(height: TtSpace.s4),
            TratraAlert(tone: TratraAlertTone.danger, message: _error!),
          ],
          const SizedBox(height: TtSpace.s5),
          if (!_sent)
            TratraButton(label: 'Recevoir le code', size: TratraButtonSize.lg, block: true, loading: _busy, onPressed: _request)
          else ...[
            TratraButton(
              label: 'Définir le nouveau mot de passe',
              size: TratraButtonSize.lg,
              block: true,
              loading: _busy,
              onPressed: _code.length == 6 ? _submit : null,
            ),
            const SizedBox(height: TtSpace.s2),
            TextButton(
              onPressed: (_busy || _cooldown > 0) ? null : _request,
              child: Text(_cooldown > 0 ? 'Renvoyer le code ($_cooldown s)' : 'Renvoyer le code'),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                _sent = false;
                _error = null;
              }),
              child: const Text('Changer de numéro'),
            ),
          ],
        ],
      ),
    );
  }
}
