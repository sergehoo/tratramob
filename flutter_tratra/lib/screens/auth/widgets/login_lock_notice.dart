// Connexion bloquée après trop de tentatives : message clair avec compte à rebours et accès au support.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Adresse du support quand le serveur n'en fournit pas.
const String defaultSupportEmail = 'support@tratra.net';

/// « 3330 » → « 55:30 » (minutes:secondes ; une heure s'écrit « 60:00 »). Jamais négatif.
String formatCountdown(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Message de blocage : « Téléphone bloqué… consultez le support ou patientez 55:30 ». Le décompte n'est PAS une zone « live » :
/// un lecteur d'écran n'annonce pas chaque seconde (le blocage est annoncé une fois, à son apparition).
class LoginLockNotice extends StatelessWidget {
  const LoginLockNotice({super.key, required this.secondsLeft, required this.onContactSupport});

  final int secondsLeft;
  final VoidCallback onContactSupport;

  @override
  Widget build(BuildContext context) {
    final fg = TtColors.warningInk;
    final base = TratraTheme.style(TtType.bodySm, color: fg);
    final minutes = secondsLeft ~/ 60;
    final spoken = 'Connexion bloquée après trop de tentatives. Patientez ${minutes > 0 ? '$minutes minute${minutes > 1 ? 's' : ''} ' : ''}'
        'et ${secondsLeft % 60} secondes, ou contactez le support.';
    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TtColors.warningSoft,
            borderRadius: TtRadius.panelAll,
            border: Border.all(color: TtColors.warning.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_clock_outlined, size: 20, color: TtColors.warning),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Connexion bloquée', style: base.copyWith(fontWeight: FontWeight.w800))),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Trop de tentatives de connexion. Consultez le support ou patientez :', style: base),
                const SizedBox(height: 6),
                Text(
                  formatCountdown(secondsLeft),
                  key: const ValueKey('login-lock-countdown'),
                  style: base.copyWith(fontSize: 28, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: onContactSupport,
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('Contacter le support'),
                  style: TextButton.styleFrom(foregroundColor: TtColors.primaryDark, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
