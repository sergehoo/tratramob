// lib/screens/dashboard/pro_status.dart
//
// Ce que l'accueil montre de l'espace professionnel, d'après les statuts RÉELS du serveur (handy/eligibility.py,
// `eligibility_summary`) — jamais déduit du seul « 7/7 » de la liste de contrôle. Même logique que le site
// (frontend/src/lib/proStatus.ts) :
//   • vérifié (publication autorisée) : plus de carte de progression, un badge « ✓ Vérifié » ; sans prestation, « Créer ma première prestation » ;
//   • pièce refusée : la correction demandée ;
//   • profil incomplet ou identité à faire : la carte de progression et « Continuer » ;
//   • pièce en revue ou validation finale de l'équipe : un statut compact, sans bouton inutile ;
//   • autre blocage (expérience minimale du métier, compte désactivé…) : son libellé et son action éventuelle.
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

enum ProHomeKind { verified, firstOffer, kycRejected, progress, kycPending, approvalPending, blocked }

class ProHomeState {
  const ProHomeState(this.kind, {this.title = '', this.message = '', this.actionCode, this.actionLabel});
  final ProHomeKind kind;
  final String title;
  final String message;

  /// Code d'action du serveur (edit_profile, verify_identity, add_service, manage_services, contact_support) ou null : aucun bouton.
  final String? actionCode;
  final String? actionLabel;

  /// Publication autorisée par le serveur : badge « ✓ Vérifié » près du nom.
  bool get verified => kind == ProHomeKind.verified || kind == ProHomeKind.firstOffer;

  /// Carte de progression (barre + « Continuer ») : seulement tant qu'il reste quelque chose à faire soi-même.
  bool get showsProgress => kind == ProHomeKind.progress || kind == ProHomeKind.kycRejected;
}

ProHomeState proHomeState(DashProvider p) {
  final e = p.eligibility;
  if (e == null) {
    // Serveur plus ancien (sans synthèse) : seule l'autorisation de publication calculée par le serveur fait foi.
    return p.publishable
        ? (p.servicesTotal == 0 ? const ProHomeState(ProHomeKind.firstOffer) : const ProHomeState(ProHomeKind.verified))
        : const ProHomeState(ProHomeKind.progress, actionCode: 'edit_profile', actionLabel: 'Continuer');
  }
  if (e.authorized) {
    return e.offersTotal == 0
        ? const ProHomeState(ProHomeKind.firstOffer,
            title: 'Créez votre première prestation',
            message: 'Votre profil est vérifié : ajoutez une prestation pour recevoir vos premières missions.',
            actionCode: 'add_service',
            actionLabel: 'Créer ma première prestation')
        : const ProHomeState(ProHomeKind.verified);
  }
  if (e.kycStatus == 'rejected') {
    return ProHomeState(ProHomeKind.kycRejected,
        title: 'Nouvelle pièce d’identité demandée',
        message: (e.kycReason ?? '').trim().isNotEmpty ? e.kycReason!.trim() : 'Reprenez des photos nettes et complètes de votre pièce.',
        actionCode: 'verify_identity',
        actionLabel: 'Reprendre ma pièce');
  }
  DashBlocker? blocker(String code) {
    for (final b in e.blockers) {
      if (b.code == code) return b;
    }
    return null;
  }

  final incomplete = blocker('profile_incomplete');
  if (incomplete != null || !e.profileComplete) {
    return ProHomeState(ProHomeKind.progress,
        title: 'Profil professionnel', message: incomplete?.label ?? '', actionCode: 'edit_profile', actionLabel: 'Continuer');
  }
  if (e.kycStatus == 'draft') {
    return const ProHomeState(ProHomeKind.progress,
        title: 'Profil professionnel', message: 'Il reste à faire vérifier votre identité.', actionCode: 'verify_identity', actionLabel: 'Continuer');
  }
  if (e.kycStatus == 'pending') {
    return const ProHomeState(ProHomeKind.kycPending,
        title: 'Identité en cours de vérification', message: 'L’équipe Tratra examine votre pièce. Vous serez prévenu(e) de la décision.');
  }
  final other = [for (final b in e.blockers) if (!{'approval_pending', 'profile_incomplete'}.contains(b.code) && !b.code.startsWith('kyc_')) b];
  if (other.isNotEmpty) {
    final b = other.first;
    return ProHomeState(ProHomeKind.blocked, title: b.label, message: b.hint ?? '', actionCode: b.action?.code, actionLabel: b.action?.label);
  }
  return const ProHomeState(ProHomeKind.approvalPending,
      title: 'Validation finale en cours', message: 'Votre identité est vérifiée. L’équipe Tratra valide votre profil : aucune action n’est nécessaire.');
}
