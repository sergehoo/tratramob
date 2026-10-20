// lib/onboarding/onboarding_entry.dart
//
// Entrées de l'inscription professionnelle :
//  • OnboardingChoiceScreen — « Proposer mes services » : Inscription ACCOMPAGNÉE (nouvelle) ou CLASSIQUE (inchangée), et
//    « Continuer mon inscription » quand un brouillon existe ;
//  • BeginnerProgressCard — tableau de bord débutant : étapes faites/restantes et UN seul bouton « Continuer » vers la prochaine action
//    calculée par le serveur (handy/onboarding.py).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/onboarding/guided_onboarding_screen.dart';
import 'package:flutter_tratra/onboarding/onboarding_api.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart' show ProProfileScreen, ProvideScreen;

Future<void> openGuidedOnboarding(BuildContext context, {String? startAt}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuidedOnboardingScreen(startAt: startAt)));

class OnboardingChoiceScreen extends StatefulWidget {
  const OnboardingChoiceScreen({super.key, this.api});
  final OnboardingApi? api;
  @override
  State<OnboardingChoiceScreen> createState() => _OnboardingChoiceScreenState();
}

class _OnboardingChoiceScreenState extends State<OnboardingChoiceScreen> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi(context.read<BaseApi>());
  OnbDraft? _draft;

  @override
  void initState() {
    super.initState();
    _api.loadLocal().then((d) {
      if (mounted && d != null && d.started) setState(() => _draft = d);
    });
  }

  void _classic() {
    if (context.read<Session>().isAuthenticated) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProvideScreen()));
    } else {
      Navigator.of(context).pushNamed(RouteNames.register);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Proposer mes services'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text('Comment voulez-vous vous inscrire ?', style: TratraTheme.style(TtType.h2)),
          const SizedBox(height: TtSpace.s2),
          Text('Les deux créent le même compte Tratra. Vous pouvez changer en cours de route : rien n’est perdu.',
              style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)),
          const SizedBox(height: TtSpace.s4),
          if (_draft != null) ...[
            _BigCard(
              key: const ValueKey('choice-resume'),
              icon: Icons.play_circle_fill_rounded,
              title: 'Continuer mon inscription',
              text: 'Vous aviez commencé${_draft!.tradeName.isEmpty ? '' : ' (${_draft!.tradeName})'}. Reprenez là où vous vous étiez arrêté.',
              highlight: true,
              onTap: () => openGuidedOnboarding(context),
            ),
            const SizedBox(height: TtSpace.s3),
          ],
          _BigCard(
            key: const ValueKey('choice-guided'),
            icon: Icons.record_voice_over_rounded,
            title: 'Inscription accompagnée',
            badge: 'Recommandée si vous débutez',
            text: 'Une question à la fois, de gros boutons et une voix qui vous guide. Votre annonce est écrite pour vous.',
            highlight: _draft == null,
            onTap: () => openGuidedOnboarding(context),
          ),
          const SizedBox(height: TtSpace.s3),
          _BigCard(
            key: const ValueKey('choice-classic'),
            icon: Icons.edit_note_rounded,
            title: 'Inscription classique',
            text: 'Je remplis moi-même le formulaire complet.',
            onTap: _classic,
          ),
        ],
      ),
    );
  }
}

class _BigCard extends StatelessWidget {
  const _BigCard({super.key, required this.icon, required this.title, required this.text, required this.onTap, this.badge, this.highlight = false});
  final IconData icon;
  final String title;
  final String text;
  final String? badge;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title. $text',
        excludeSemantics: true,
        child: Material(
          color: highlight ? TtColors.primarySoft : TtColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TtRadius.card),
            side: BorderSide(color: highlight ? TtColors.primary : TtColors.line, width: highlight ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(TtRadius.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(TtSpace.s4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 36, color: TtColors.primary),
                const SizedBox(width: TtSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (badge != null) ...[TratraBadge(badge!, tone: TratraTone.accent), const SizedBox(height: TtSpace.s1)],
                    Text(title, style: TratraTheme.style(TtType.h3)),
                    const SizedBox(height: 4),
                    Text(text, style: TratraTheme.style(TtType.body, color: TtColors.inkSoft)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: TtColors.ash),
              ]),
            ),
          ),
        ),
      );
}

/// Tableau de bord débutant : progression claire et UN bouton « Continuer » (prochaine action calculée par le serveur).
class BeginnerProgressCard extends StatefulWidget {
  const BeginnerProgressCard({super.key, this.api});
  final OnboardingApi? api;
  @override
  State<BeginnerProgressCard> createState() => _BeginnerProgressCardState();
}

class _BeginnerProgressCardState extends State<BeginnerProgressCard> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi(context.read<BaseApi>());
  OnbState? _state;
  Object? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Le tableau de bord vient d'être rechargé (tirer pour actualiser, retour d'un écran) : la progression aussi.
  void _follow(Object? data) {
    if (identical(data, _seen)) return;
    final first = _seen == null;
    _seen = data;
    if (!first) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _load() : null);
  }

  Future<void> _load() async {
    try {
      final s = await _api.sync(userId: context.read<Session>().user?.id); // un brouillon du téléphone rejoint le compte (rien n'est perdu)
      if (mounted) setState(() => _state = s);
    } catch (_) {
      // hors ligne : la carte réapparaîtra au prochain chargement
    }
  }

  Future<void> _continue() async {
    final s = _state!;
    switch (s.nextCode) {
      case 'verify_identity':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IdentityFlowScreen(simplified: true)));
      case 'wait' || 'done' || 'blocked':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProProfileScreen()));
      case 'verify_phone':
        await openGuidedOnboarding(context, startAt: 'phone');
      default:
        await openGuidedOnboarding(context, startAt: s.nextStep);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    _follow(context.select<DashboardController?, Object?>((c) => c?.data));
    final s = _state;
    if (s == null || s.published || !s.draft.started) return const SizedBox.shrink();
    final waiting = s.nextCode == 'wait' || s.nextCode == 'blocked';
    final card = TratraCard(
      key: const ValueKey('beginner-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Mon inscription professionnelle', style: TratraTheme.style(TtType.h3))),
          Text('${s.done}/${s.total}', style: TratraTheme.style(TtType.title, color: TtColors.primaryDark)),
        ]),
        const SizedBox(height: TtSpace.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(TtRadius.pill),
          child:
              LinearProgressIndicator(value: s.total == 0 ? 0 : s.done / s.total, minHeight: 10, backgroundColor: TtColors.lineSoft, color: TtColors.primary),
        ),
        const SizedBox(height: TtSpace.s3),
        Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
          for (final st in s.steps)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                switch (st.state) { 'done' => Icons.check_circle_rounded, 'waiting' => Icons.hourglass_top_rounded, _ => Icons.radio_button_unchecked_rounded },
                size: 16,
                color: switch (st.state) { 'done' => TtColors.success, 'waiting' => TtColors.accentDark, _ => TtColors.fog },
              ),
              const SizedBox(width: 4),
              Text(st.label, style: TratraTheme.style(TtType.caption, color: st.state == 'todo' ? TtColors.ash : TtColors.inkSoft)),
            ]),
        ]),
        const SizedBox(height: TtSpace.s3),
        if (s.experienceWarning != null) ...[
          TratraAlert(key: const ValueKey('beginner-blocked'), tone: TratraAlertTone.warning, message: s.experienceWarning!),
          const SizedBox(height: TtSpace.s2),
        ],
        if (s.nextCode == 'blocked')
          const SizedBox.shrink()
        else if (waiting)
          Text('L’équipe Tratra vérifie votre dossier. Vous serez prévenu(e) par notification.',
              style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
        if (!waiting) Text('Prochaine étape : ${s.nextLabel}', style: TratraTheme.style(TtType.body).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: TtSpace.s3),
        TratraButton(
          key: const ValueKey('beginner-continue'),
          label: waiting ? 'Voir mon dossier' : 'Continuer',
          size: TratraButtonSize.lg,
          block: true,
          onPressed: _continue,
        ),
      ]),
    );
    return Padding(padding: const EdgeInsets.only(bottom: TtSpace.s4), child: card);
  }
}
