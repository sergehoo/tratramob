// lib/screens/dashboard/eligibility_panel.dart
//
// « Mon espace professionnel » : quatre notions DISTINCTES calculées par le serveur (handy/eligibility.py) — profil complet, identité,
// autorisation de publication, offres — avec les blocages réels et l'action qui lève chacun. Aucune règle ici : l'application affiche.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/auth/widgets/login_lock_notice.dart' show defaultSupportEmail;
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart';

/// Action corrective standard. `onEditProfile` remplace l'ouverture du profil pro quand on y est déjà (défilement vers le formulaire).
Future<void> runEligibilityAction(BuildContext context, DashActionRef action, {VoidCallback? onEditProfile, VoidCallback? onChanged}) async {
  switch (action.code) {
    case 'edit_profile':
      if (onEditProfile != null) return onEditProfile();
      await openProProfile(context);
    case 'verify_identity':
      await openKyc(context);
    case 'add_service':
      final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewServiceScreen()));
      if (added == true) onChanged?.call();
      return;
    case 'manage_services':
      await openProviderHub(context);
    case 'contact_support':
      await launchUrl(Uri(scheme: 'mailto', path: defaultSupportEmail, query: 'subject=Mon espace professionnel Tratra'));
      return;
    default:
      return;
  }
  onChanged?.call();
}

(String, TratraTone) kycBadge(String status, String label) => switch (status) {
      'approved' => (label, TratraTone.success),
      'pending' => (label, TratraTone.accent),
      'rejected' => (label, TratraTone.danger),
      _ => (label, TratraTone.gray),
    };

class EligibilityPanel extends StatelessWidget {
  const EligibilityPanel({super.key, required this.eligibility, this.onEditProfile, this.onChanged, this.showOffers = true});
  final DashEligibility eligibility;
  final VoidCallback? onEditProfile;
  final VoidCallback? onChanged;
  final bool showOffers;

  @override
  Widget build(BuildContext context) {
    final e = eligibility;
    void act(DashActionRef a) => runEligibilityAction(context, a, onEditProfile: onEditProfile, onChanged: onChanged);
    final missing = [for (final i in e.profileItems) if (!i.done) i.label.toLowerCase()];
    final kyc = kycBadge(e.kycStatus, e.kycLabel);
    return TratraCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Mon espace professionnel', style: TratraTheme.style(TtType.h3))),
          TratraBadge(e.authorized ? 'Publié' : 'Non publié', tone: e.authorized ? TratraTone.success : TratraTone.gray, dot: true),
        ]),
        const SizedBox(height: TtSpace.s3),
        _Block(
          key: const ValueKey('elig-profile'),
          icon: Icons.person_outline_rounded,
          title: 'Profil complet',
          value: '${e.profileDone}/${e.profileTotal}',
          ok: e.profileComplete,
          detail: e.profileComplete ? 'Présentation, spécialités, expérience, zone et photo renseignées.' : 'À compléter : ${missing.join(', ')}.',
        ),
        _Block(
          key: const ValueKey('elig-kyc'),
          icon: Icons.verified_user_outlined,
          title: 'Identité',
          badge: TratraBadge(kyc.$1, tone: kyc.$2, dot: true),
          ok: e.kycApproved,
          detail: switch (e.kycStatus) {
            'approved' => 'Pièce d’identité validée par l’équipe Tratra.',
            'pending' => 'L’équipe Tratra examine votre pièce. Aucune action n’est nécessaire.',
            'rejected' => e.kycReason ?? 'Une nouvelle pièce est demandée.',
            _ => 'Faites vérifier votre pièce d’identité en quelques minutes.',
          },
        ),
        _Block(
          key: const ValueKey('elig-publication'),
          icon: Icons.public_rounded,
          title: 'Autorisation de publication',
          value: e.authorized ? 'Autorisée' : 'Non autorisée',
          ok: e.authorized,
          detail: e.authorized ? 'Vos offres actives sont visibles des clients.' : e.approvalLabel,
        ),
        if (showOffers)
          _Block(
            key: const ValueKey('elig-offers'),
            icon: Icons.storefront_outlined,
            title: 'Offres',
            value: '${e.offersPublished} publiée${e.offersPublished > 1 ? 's' : ''} / ${e.offersTotal}',
            ok: e.authorized && e.offersPublished > 0,
            detail: e.offersLabel,
            action: e.offersAction,
            onAction: act,
            last: true,
          ),
        if (!e.authorized && e.blockers.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s3),
          Text('Ce qui bloque la publication', style: TratraTheme.style(TtType.title)),
          const SizedBox(height: TtSpace.s2),
          for (final b in e.blockers)
            Padding(
              padding: const EdgeInsets.only(bottom: TtSpace.s2),
              child: Container(
                key: ValueKey('blocker-${b.code}'),
                width: double.infinity,
                padding: const EdgeInsets.all(TtSpace.s3),
                decoration: BoxDecoration(color: TtColors.canvas, borderRadius: BorderRadius.circular(TtRadius.control), border: Border.all(color: TtColors.lineSoft)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(b.action == null ? Icons.hourglass_top_rounded : Icons.error_outline_rounded, size: 18,
                        color: b.action == null ? TtColors.accentDark : TtColors.dangerInk),
                    const SizedBox(width: TtSpace.s2),
                    Expanded(child: Text(b.label, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600))),
                  ]),
                  if (b.hint != null) ...[
                    const SizedBox(height: 2),
                    Padding(padding: const EdgeInsets.only(left: 26), child: Text(b.hint!, style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
                  ],
                  if (b.action != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: TextButton(onPressed: () => act(b.action!), child: Text(b.action!.label)),
                    ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({super.key, required this.icon, required this.title, required this.ok, required this.detail, this.value, this.badge, this.action, this.onAction, this.last = false});
  final IconData icon;
  final String title;
  final bool ok;
  final String detail;
  final String? value;
  final Widget? badge;
  final DashActionRef? action;
  final void Function(DashActionRef)? onAction;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: TtSpace.s2),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: TtColors.lineSoft))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle_rounded : icon, size: 20, color: ok ? TtColors.success : TtColors.ash),
        const SizedBox(width: TtSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: TtSpace.s2, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(title, style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
              if (value != null) Text(value!, style: TratraTheme.style(TtType.caption, color: ok ? TtColors.successInk : TtColors.inkSoft).copyWith(fontWeight: FontWeight.w700)),
              if (badge != null) badge!,
            ]),
            const SizedBox(height: 2),
            Text(detail, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            if (action != null && onAction != null)
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => onAction!(action!), child: Text(action!.label))),
          ]),
        ),
      ]),
    );
  }
}
