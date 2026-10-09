// lib/screens/auth/otp_screen.dart
//
// Vérification du téléphone par code OTP (6 chiffres) — mêmes endpoints que le web :
// POST /auth/otp/request/ puis POST /auth/otp/verify/. Aucun code n'est jamais affiché.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/widgets/auth_frame.dart';
import 'package:flutter_tratra/services/auth_service.dart';

/// Délai minimal entre deux envois de code (secondes).
const int kOtpResendSeconds = 60;

/// « +2250700000002 » -> « +225 •• •• •• 02 » (le numéro complet n'est jamais affiché).
String maskPhone(String phone) {
  final p = phone.replaceAll(RegExp(r'\s+'), '');
  if (p.length < 6) return p;
  final prefix = p.startsWith('+') ? p.substring(0, 4) : '';
  return '${prefix.isEmpty ? '' : '$prefix '}•• •• •• ${p.substring(p.length - 2)}';
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, this.nextRoute = RouteNames.home});
  final String nextRoute;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';

  /// Change après une erreur : recrée le champ (vide, refocalisé), comme sur le web.
  int _attempt = 0;
  bool _sent = false;
  bool _busy = false;
  bool _done = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  /// Le profil en session peut être périmé : on le recharge avant de décider si le numéro
  /// est déjà vérifié.
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    await context.read<Session>().refreshProfile();
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = kOtpResendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().requestOtp();
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code = '';
      });
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify([String? value]) async {
    final code = value ?? _code;
    if (code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final session = context.read<Session>();
    try {
      await auth.verifyOtp(code);
      await session.refreshProfile();
      if (mounted) setState(() => _done = true);
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

  void _continue() => Navigator.pushReplacementNamed(context, widget.nextRoute);

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    final phone = user?.phoneNumber;
    final alreadyVerified = (user?.isVerified ?? false) || _done;

    Widget body;
    if (_checking) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: TtSpace.s4),
        child: TratraSkeletonText(lines: 3),
      );
    } else if (alreadyVerified) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TratraAlert(
            tone: TratraAlertTone.success,
            title: 'Téléphone vérifié',
            message: 'Votre numéro est confirmé. Merci !',
          ),
          const SizedBox(height: TtSpace.s5),
          TratraButton(label: 'Continuer', size: TratraButtonSize.lg, block: true, onPressed: _continue),
        ],
      );
    } else if (phone == null || phone.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TratraAlert(
            tone: TratraAlertTone.warning,
            title: 'Aucun numéro enregistré',
            message: 'Aucun numéro de téléphone n’est associé à votre compte : il n’y a rien à vérifier pour le moment.',
          ),
          const SizedBox(height: TtSpace.s5),
          TratraButton(
              label: 'Retour', variant: TratraButtonVariant.outline, size: TratraButtonSize.lg, block: true, onPressed: _continue),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_sent)
            Text(
              'Nous enverrons un code à 6 chiffres par SMS au ${maskPhone(phone)}.',
              style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
            )
          else ...[
            Text(
              'Saisissez le code reçu au ${maskPhone(phone)}.',
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
              onCompleted: _verify,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: TtSpace.s4),
            TratraAlert(tone: TratraAlertTone.danger, message: _error!),
          ],
          const SizedBox(height: TtSpace.s5),
          if (!_sent)
            TratraButton(
              label: 'Recevoir le code',
              size: TratraButtonSize.lg,
              block: true,
              loading: _busy,
              onPressed: _request,
            )
          else ...[
            TratraButton(
              label: 'Vérifier',
              size: TratraButtonSize.lg,
              block: true,
              loading: _busy,
              onPressed: _code.length == 6 ? _verify : null,
            ),
            const SizedBox(height: TtSpace.s2),
            TextButton(
              onPressed: (_busy || _cooldown > 0) ? null : _request,
              child: Text(_cooldown > 0 ? 'Renvoyer le code ($_cooldown s)' : 'Renvoyer le code'),
            ),
          ],
          const SizedBox(height: TtSpace.s1),
          TextButton(onPressed: _busy ? null : _continue, child: const Text('Plus tard')),
        ],
      );
    }

    return AuthFrame(
      eyebrow: 'Sécurité du compte',
      title: 'Vérifiez votre téléphone',
      subtitle: 'Confirmez votre numéro pour sécuriser votre compte Tratra.',
      onBack: _continue,
      child: body,
    );
  }
}
