// lib/screens/dashboard/pro_status.dart
//
// Ce que l'accueil montre de l'espace professionnel, d'après les statuts RÉELS du serveur (handy/eligibility.py,
// `eligibility_summary`) — jamais déduit du seul « 7/7 » de la liste de contrôle. Même logique que le site
// (frontend/src/lib/proStatus.ts). Trois niveaux distincts :
//   • PUBLICATION : le service est visible, avec la mention « Non vérifié » tant que l'identité n'est pas vérifiée ;
//   • COMMANDES   : pièce d'identité approuvée → réservations, missions et Tratra Flash (« Identité vérifiée ») ;
//   • BADGE       : vérification faciale validée → « Vérifié ». Aucun autre état n'affiche ce badge.
// La carte propose toujours UNE action : terminer la publication, « Activer mes commandes », reprendre une pièce refusée,
// « Obtenir le badge Vérifié » — ou un statut compact quand la suite dépend de l'équipe.
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

enum ProHomeKind {
  /// Rien à faire ni à attendre : aucune carte.
  none,
  firstOffer,
  kycRejected,
  progress,

  /// Service publié, identité à faire : « Activer mes commandes ».
  activate,

  /// Commandes activées, vérification faciale possible : « Obtenir le badge Vérifié ».
  badge,
  kycPending,
  facePending,
  approvalPending,
  blocked,
}

class ProHomeState {
  const ProHomeState(this.kind,
      {this.title = '', this.message = '', this.actionCode, this.actionLabel, this.actionStep, this.level = 'NON_VERIFIE', this.levelLabel = 'Non vérifié', this.published = false});
  final ProHomeKind kind;
  final String title;
  final String message;

  /// Code d'action du serveur (edit_profile, verify_identity, verify_phone, add_service, manage_services, contact_support) ou null : aucun bouton.
  final String? actionCode;
  final String? actionLabel;

  /// Étape visée par l'action (`face` : vérification faciale).
  final String? actionStep;

  /// NON_VERIFIE | IDENTITE_VERIFIEE | VERIFIE.
  final String level;
  final String levelLabel;
  final bool published;

  /// Badge « Vérifié » : uniquement après la vérification faciale validée.
  bool get verified => level == 'VERIFIE';

  /// Mention affichée près du nom dès que le service est public (« Non vérifié », « Identité vérifiée », « Vérifié »).
  String? get mention => published ? levelLabel : null;

  /// Carte de progression (barre + « Continuer ») : seulement tant qu'il reste quelque chose à faire soi-même pour publier.
  bool get showsProgress => kind == ProHomeKind.progress;
}

DashBlocker? _blocker(List<DashBlocker> list, String code) {
  for (final b in list) {
    if (b.code == code) return b;
  }
  return null;
}

ProHomeState proHomeState(DashProvider p) {
  final e = p.eligibility;
  if (e == null) {
    // Serveur plus ancien (sans synthèse) : seule l'autorisation calculée par le serveur fait foi ; jamais de badge « Vérifié ».
    if (!p.publishable) return const ProHomeState(ProHomeKind.progress, actionCode: 'edit_profile', actionLabel: 'Continuer');
    return ProHomeState(p.servicesTotal == 0 ? ProHomeKind.firstOffer : ProHomeKind.none,
        level: 'IDENTITE_VERIFIEE', levelLabel: 'Identité vérifiée', published: true);
  }
  ProHomeState st(ProHomeKind kind, {String title = '', String message = '', String? code, String? label, String? step}) => ProHomeState(kind,
      title: title, message: message, actionCode: code, actionLabel: label, actionStep: step,
      level: e.verificationLevel, levelLabel: e.verificationLabel, published: e.authorized);
  ProHomeState rejected() => st(ProHomeKind.kycRejected,
      title: 'Nouvelle pièce d’identité demandée',
      message: (e.kycReason ?? '').trim().isNotEmpty ? e.kycReason!.trim() : 'Reprenez des photos nettes et complètes de votre pièce.',
      code: 'verify_identity',
      label: 'Reprendre ma pièce');

  // 1. Publication.
  if (!e.authorized) {
    final incomplete = _blocker(e.blockers, 'profile_incomplete');
    if (!e.hasLevels && e.kycStatus == 'rejected') return rejected();
    if (incomplete != null || !e.profileComplete) {
      return st(ProHomeKind.progress, title: 'Profil professionnel', message: incomplete?.label ?? '', code: 'edit_profile', label: 'Continuer');
    }
    if (!e.hasLevels) {
      // Ancien serveur : la publication attendait la vérification d'identité.
      if (e.kycStatus == 'draft') {
        return st(ProHomeKind.progress,
            title: 'Profil professionnel', message: 'Il reste à faire vérifier votre identité.', code: 'verify_identity', label: 'Continuer');
      }
      if (e.kycStatus == 'pending') {
        return st(ProHomeKind.kycPending,
            title: 'Identité en cours de vérification', message: 'L’équipe Tratra examine votre pièce. Vous serez prévenu(e) de la décision.');
      }
    }
    final other = [for (final b in e.blockers) if (!{'approval_pending', 'profile_incomplete'}.contains(b.code) && !b.code.startsWith('kyc_')) b];
    if (other.isNotEmpty) {
      final b = other.first;
      return st(ProHomeKind.blocked, title: b.label, message: b.hint ?? '', code: b.action?.code, label: b.action?.label);
    }
    return st(ProHomeKind.approvalPending,
        title: 'Validation en cours', message: 'L’équipe Tratra valide votre profil : aucune action n’est nécessaire.');
  }

  // 2. Un service à montrer.
  if (e.offersTotal == 0) {
    return st(ProHomeKind.firstOffer,
        title: 'Publiez votre premier service',
        message: 'Votre profil est visible des clients. Ajoutez un service pour apparaître dans la recherche.',
        code: 'add_service',
        label: 'Publier un service');
  }
  if (e.offersActive == 0 && e.offersAction != null) {
    return st(ProHomeKind.blocked,
        title: 'Aucun service actif',
        message: 'Réactivez un service pour redevenir visible dans la recherche.',
        code: e.offersAction!.code,
        label: e.offersAction!.label);
  }

  // 3. Commandes.
  if (!e.ordersAuthorized) {
    if (e.kycStatus == 'rejected') return rejected();
    if (e.kycStatus == 'pending') {
      return st(ProHomeKind.kycPending,
          title: 'Identité en cours de vérification',
          message: 'L’équipe Tratra examine votre pièce. Votre service reste visible avec la mention « ${e.verificationLabel} » ; vous serez prévenu(e) de la décision.');
    }
    if (e.kycStatus == 'draft') {
      return st(ProHomeKind.activate,
          title: 'Activez vos commandes',
          message: 'Votre service est en ligne avec la mention « ${e.verificationLabel} ». Faites vérifier votre pièce d’identité pour recevoir des réservations et des missions.',
          code: 'verify_identity',
          label: 'Activer mes commandes');
    }
    final face = _blocker(e.ordersBlockers, 'face_required');
    if (face != null) {
      if (e.faceState == 'pending') {
        return st(ProHomeKind.facePending,
            title: 'Vérification faciale en cours de revue',
            message: 'Votre métier demande cette vérification avant les commandes. L’équipe Tratra l’examine : vous serez prévenu(e).');
      }
      return st(ProHomeKind.activate,
          title: 'Dernière étape avant vos commandes',
          message: face.hint ?? face.label,
          code: face.action?.code,
          label: face.action?.label,
          step: face.action?.step ?? 'face');
    }
    final b = e.ordersBlockers.isEmpty ? null : e.ordersBlockers.first;
    if (b == null || b.code == 'approval_pending') {
      return st(ProHomeKind.approvalPending,
          title: 'Activation des commandes en attente',
          message: b?.hint ?? 'Votre identité est vérifiée. L’équipe Tratra active vos commandes : aucune action n’est nécessaire.');
    }
    return st(ProHomeKind.blocked, title: b.label, message: b.hint ?? '', code: b.action?.code, label: b.action?.label);
  }

  // 4. Badge « Vérifié ».
  if (e.verified) return st(ProHomeKind.none);
  if (e.faceState == 'todo' || e.faceState == 'retry') {
    final benefit = e.stage('face')?.benefit ?? '';
    return st(ProHomeKind.badge,
        title: e.faceState == 'retry' ? 'Reprenez la vérification faciale' : 'Obtenez le badge « Vérifié »',
        message: benefit.isNotEmpty ? benefit : 'Une vérification faciale confirme que la pièce d’identité est bien la vôtre.',
        code: 'verify_identity',
        label: e.nextAction?.step == 'face' ? e.nextAction!.label : 'Obtenir le badge Vérifié',
        step: 'face');
  }
  if (e.faceState == 'pending') {
    return st(ProHomeKind.facePending,
        title: 'Vérification faciale en cours de revue',
        message: 'Vos commandes restent activées. Le badge « Vérifié » s’affichera après la décision de l’équipe Tratra.');
  }
  return st(ProHomeKind.none);
}
