// lib/screens/dashboard/eligibility_panel.dart
//
// « Mon espace professionnel » : les trois niveaux DISTINCTS calculés par le serveur (handy/eligibility.py) — publication (service
// visible, « Non vérifié »), commandes (pièce d'identité vérifiée), badge « Vérifié » (vérification faciale) — puis le profil et les
// offres, avec les blocages réels du niveau en cours et l'action qui lève chacun. Aucune règle ici : l'application affiche.
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
      await openKyc(context, step: action.step);
    case 'verify_phone':
      await openVerifyPhone(context);
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
    final face = e.stage('face');
    // Blocages du niveau EN COURS : la publication d'abord, puis les commandes.
    final blockers = !e.authorized ? e.blockers : (e.ordersAuthorized ? const <DashBlocker>[] : e.ordersBlockers);
    return TratraCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Petit écran ou texte agrandi : la mention passe sous le titre au lieu de déborder.
        SizedBox(
          width: double.infinity,
          child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: TtSpace.s2, runSpacing: TtSpace.s1, children: [
            Text('Mon espace professionnel', style: TratraTheme.style(TtType.h3)),
            TratraBadge(e.verificationLabel,
                key: const ValueKey('elig-level'),
                tone: e.verified ? TratraTone.success : e.verificationLevel == 'IDENTITE_VERIFIEE' ? TratraTone.info : TratraTone.gray,
                dot: true),
          ]),
        ),
        const SizedBox(height: TtSpace.s3),
        _Block(
          key: const ValueKey('elig-publication'),
          icon: Icons.public_rounded,
          title: 'Publication',
          value: e.authorized ? 'Publié' : 'Non publié',
          ok: e.authorized,
          detail: e.authorized
              ? (e.verified
                  ? 'Vos services actifs sont visibles des clients, avec le badge « Vérifié ».'
                  : 'Vos services actifs sont visibles des clients, avec la mention « ${e.verificationLabel} ».')
              : e.blockers.isEmpty
                  ? e.approvalLabel
                  : '${e.blockers.length} point${e.blockers.length > 1 ? 's bloquent' : ' bloque'} la publication : voir ci-dessous.',
        ),
        _Block(
          key: const ValueKey('elig-kyc'),
          icon: Icons.verified_user_outlined,
          title: 'Commandes',
          value: e.ordersAuthorized ? 'Activées' : 'Non activées',
          badge: e.ordersAuthorized ? null : TratraBadge(kyc.$1, tone: kyc.$2, dot: true),
          ok: e.ordersAuthorized,
          detail: e.ordersAuthorized
              ? 'Réservations, missions Tratra Flash et contrats sont ouverts.'
              : switch (e.kycStatus) {
                  'approved' => e.ordersBlockers.isNotEmpty ? e.ordersBlockers.first.label : e.ordersLabel,
                  'pending' => 'L’équipe Tratra examine votre pièce d’identité. Aucune action n’est nécessaire.',
                  'rejected' => e.kycReason ?? 'Une nouvelle pièce d’identité est demandée.',
                  _ => 'Faites vérifier votre pièce d’identité pour recevoir des réservations et des missions.',
                },
        ),
        if (e.hasLevels)
          _Block(
            key: const ValueKey('elig-badge'),
            icon: Icons.verified_outlined,
            title: 'Badge « Vérifié »',
            value: e.verified ? 'Attribué' : (face?.status ?? ''),
            ok: e.verified,
            detail: e.verified
                ? 'Votre visage correspond à votre pièce d’identité : le badge est affiché sur votre profil et vos offres.'
                : (face?.benefit.isNotEmpty ?? false)
                    ? face!.benefit
                    : 'Une vérification faciale confirme que la pièce d’identité est bien la vôtre.',
          ),
        _Block(
          key: const ValueKey('elig-profile'),
          icon: Icons.person_outline_rounded,
          title: 'Profil',
          value: '${e.profileDone}/${e.profileTotal}',
          ok: e.profileComplete,
          detail: e.profileComplete ? 'Présentation, spécialités, expérience, zone et photo renseignées.' : 'À compléter : ${missing.join(', ')}.',
          last: !showOffers,
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
        if (blockers.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s3),
          Text(e.authorized ? 'Ce qui manque pour recevoir des commandes' : 'Ce qui bloque la publication', style: TratraTheme.style(TtType.title)),
          const SizedBox(height: TtSpace.s2),
          for (final b in blockers)
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
              if (value != null && value!.isNotEmpty) Text(value!, style: TratraTheme.style(TtType.caption, color: ok ? TtColors.successInk : TtColors.inkSoft).copyWith(fontWeight: FontWeight.w700)),
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
