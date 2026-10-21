// lib/flash/flash_settings.dart
//
// Réglages sonores Tratra (sonnerie « Pulse ») : son et vibration des nouvelles missions, aperçu de la sonnerie Tratra Flash et du son
// des notifications. Le mode silencieux, le vibreur et « Ne pas déranger » du téléphone sont toujours respectés (l'aperçu le dit).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_native.dart';

class FlashSoundSettings extends StatefulWidget {
  const FlashSoundSettings({super.key});
  @override
  State<FlashSoundSettings> createState() => _FlashSoundSettingsState();
}

class _FlashSoundSettingsState extends State<FlashSoundSettings> {
  String? _feedback;

  Future<void> _preview(FlashController c, String sound) async {
    final FlashPlayback p = sound == 'tratra_flash'
        ? await c.ring()
        : await c.native.play('tratra_notification', withSound: true, withVibration: false);
    if (!mounted) return;
    setState(() => _feedback = p.explanation ??
        (p.played || p.vibrated ? null : 'Son et vibration désactivés pour les nouvelles missions : activez-les ci-dessus pour les entendre.'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FlashController>();
    return TratraCard(
      key: const ValueKey('flash-sound-settings'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sonnerie Tratra', style: TratraTheme.style(TtType.h3)),
        const SizedBox(height: TtSpace.s1),
        Text('Les nouvelles missions ont leur propre sonnerie, « Pulse », distincte des notifications ordinaires. '
            'Le mode silencieux, le vibreur et « Ne pas déranger » de votre téléphone sont toujours respectés.',
            style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        SwitchListTile(
          key: const ValueKey('flash-pref-sound'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Son des nouvelles missions'),
          value: c.soundOn,
          onChanged: (v) => c.setPrefs(sound: v),
        ),
        SwitchListTile(
          key: const ValueKey('flash-pref-vibration'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Vibration des nouvelles missions'),
          value: c.vibrationOn,
          onChanged: (v) => c.setPrefs(vibration: v),
        ),
        const SizedBox(height: TtSpace.s2),
        Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
          TratraButton(
            key: const ValueKey('flash-test-ring'),
            label: 'Tester la sonnerie',
            size: TratraButtonSize.sm,
            leading: const Icon(Icons.bolt_rounded, size: 18),
            onPressed: () => _preview(c, 'tratra_flash'),
          ),
          TratraButton(
            key: const ValueKey('flash-test-notification'),
            label: 'Écouter le son des notifications',
            size: TratraButtonSize.sm,
            variant: TratraButtonVariant.outline,
            leading: const Icon(Icons.notifications_none_rounded, size: 18),
            onPressed: () => _preview(c, 'tratra_notification'),
          ),
        ]),
        if (_feedback != null) ...[
          const SizedBox(height: TtSpace.s2),
          TratraAlert(key: const ValueKey('flash-sound-feedback'), tone: TratraAlertTone.info, message: _feedback!),
        ],
      ]),
    );
  }
}
