// lib/screens/dashboard/dash_nav.dart
//
// Navigation depuis l'espace unifié vers les écrans (existants ou nouveaux).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/flash/flash_client.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_pro.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/engagements/contract_screen.dart';
import 'package:flutter_tratra/engagements/engagements_home.dart';
import 'package:flutter_tratra/engagements/posting_screen.dart';
import 'package:flutter_tratra/engagements/replacements_screen.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/onboarding/onboarding_entry.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/flash/flash_hybrid.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/all_categories_screen.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/all_urgent_services_screen.dart';
import 'package:flutter_tratra/screens/panne_screen.dart';
import 'package:flutter_tratra/screens/search_screen.dart';
import 'package:flutter_tratra/screens/service_link_screen.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';
import 'package:flutter_tratra/screens/business/business_screens.dart';
import 'package:flutter_tratra/screens/auth/profile_screen.dart';
import 'package:flutter_tratra/screens/dashboard/addresses_screen.dart';
import 'package:flutter_tratra/screens/dashboard/announcements_screen.dart';
import 'package:flutter_tratra/screens/dashboard/bookings_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/messages_screen.dart';
import 'package:flutter_tratra/screens/dashboard/my_badge_screen.dart';
import 'package:flutter_tratra/screens/dashboard/notifications_screen.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart';
import 'package:flutter_tratra/screens/dashboard/reputation_screen.dart';
import 'package:flutter_tratra/screens/dashboard/reviews_screen.dart';
import 'package:flutter_tratra/screens/dashboard/wallet_screen.dart';
import 'package:flutter_tratra/screens/tracking_screen.dart';
import 'package:flutter_tratra/screens/trust/scan_screen.dart';
import 'package:flutter_tratra/screens/worker/kyc_screen.dart';
import 'package:flutter_tratra/screens/worker/mission_detail_screen.dart';

Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

/// Réservation (client) → suivi ; mission (artisan) → détail de mission.
Future<void> openItem(BuildContext context, DashItem item) => pushPage(
      context,
      item.isMission ? MissionDetailScreen(bookingId: '${item.id}') : TrackingScreen(bookingId: '${item.id}'),
    );

Future<void> openBookings(BuildContext context) => pushPage(context, const BookingsScreen());
Future<void> openProviderHub(BuildContext context) => pushPage(context, const ProviderHubScreen());
Future<void> openWallet(BuildContext context) => pushPage(context, const WalletScreen());
Future<void> openReviews(BuildContext context) => pushPage(context, const ReviewsScreen());
Future<void> openReputation(BuildContext context) => pushPage(context, const ReputationScreen());
Future<void> openMyBadge(BuildContext context) => pushPage(context, const MyBadgeScreen());
Future<void> openScanner(BuildContext context) => pushPage(context, const ScanScreen());
Future<void> openEngagements(BuildContext context) => pushPage(context, const EngagementsHomeScreen());
Future<void> openBusiness(BuildContext context) => pushPage(context, const BusinessHomeScreen());
Future<void> openNotifications(BuildContext context) => pushPage(context, const NotificationsScreen());
/// « Proposer un service » : choix entre l'inscription accompagnée et l'inscription classique (un artisan existant garde l'écran habituel).
Future<void> openProvide(BuildContext context) => pushPage(
      context,
      (context.read<DashboardController>().data?.isProvider ?? false) ? const ProvideScreen() : const OnboardingChoiceScreen(),
    );
Future<void> openProProfile(BuildContext context) => pushPage(context, const ProProfileScreen());
/// « Vérifier mon identité » : le parcours guidé (une seule entrée pour la pièce d'identité et la vérification faciale).
Future<void> openKyc(BuildContext context) => pushPage(context, const IdentityFlowScreen());
/// Autres justificatifs (diplômes, casier, assurance…) et historique des pièces.
Future<void> openDocuments(BuildContext context) => pushPage(context, const KycScreen());
Future<void> openAddresses(BuildContext context) => pushPage(context, const AddressesScreen());
Future<void> openAccount(BuildContext context) => pushPage(context, const ProfileScreen());

/// Destination d'une « action à traiter » (cibles neutres renvoyées par l'API).
void openTarget(BuildContext context, DashTarget target, {VoidCallback? onMessages}) {
  switch (target) {
    case DashTarget.provider:
      openProviderHub(context);
    case DashTarget.profile:
      openProProfile(context);
    case DashTarget.profileKyc:
      openKyc(context);
    case DashTarget.reviews:
      openReviews(context);
    case DashTarget.messages:
      onMessages?.call();
    case DashTarget.verifyPhone:
      Navigator.pushNamed(context, RouteNames.verifyPhone, arguments: const OtpArgs());
    case DashTarget.unknown:
      break;
  }
}

/// Le compte courant a-t-il le rôle exigé ? Données de l'espace rechargées si elles manquent (lancement à froid). Sans réponse du
/// serveur, l'écran est ouvert : ses propres données restent protégées par le serveur (refus affiché comme une erreur normale).
Future<bool> _hasRole(BuildContext context, LinkRole role) async {
  final dash = context.read<DashboardController>();
  if (dash.data == null) {
    try {
      await dash.load();
    } catch (_) {}
  }
  final data = dash.data;
  if (data == null) return true;
  return switch (role) {
    LinkRole.provider => data.isProvider,
    LinkRole.business => data.isBusiness || data.isCompany,
  };
}

/// Métier ou prestation du catalogue par identifiant : ses offres ; introuvable → tous les métiers.
Future<void> _openCategory(BuildContext context, int id) async {
  String? name;
  try {
    name = (await CatalogRepository.shared(context.read<BaseApi>()).load()).byId('$id')?.name;
  } catch (_) {}
  if (!context.mounted) return;
  if (name == null) {
    showMessage(context, 'Ce métier n’est plus proposé : voici tous les métiers.');
    return pushPage(context, const AllCategoriesScreen());
  }
  return pushPage(context, AllServicesScreen(initialCategory: name));
}

/// Ouvre l'objet désigné par un lien profond (notification touchée, centre de notifications, bandeau, annonce).
/// Chaque écran recharge ses données auprès du serveur : un objet supprimé ou interdit s'affiche comme une erreur normale. Un écran
/// réservé (professionnel, entreprise) n'est jamais affiché à un autre compte : retour à l'accueil avec un message.
Future<void> openDeepLink(BuildContext context, DeepLink link) async {
  final role = requiredRole(link.kind);
  if (role != null && !await _hasRole(context, role)) {
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    dashboardTabRequest.value = 0;
    showMessage(context, role == LinkRole.provider
        ? 'Cette page est réservée aux professionnels Tratra.'
        : 'Cette page est réservée aux comptes entreprise.');
    return;
  }
  if (!context.mounted) return;
  return _open(context, link);
}

Future<void> _open(BuildContext context, DeepLink link) {
  switch (link.kind) {
    case DeepLinkKind.booking:
      return pushPage(context, TrackingScreen(bookingId: '${link.id}'));
    case DeepLinkKind.mission:
      return pushPage(context, MissionDetailScreen(bookingId: '${link.id}'));
    case DeepLinkKind.conversation:
      return pushPage(context, ConversationScreen(conversationId: link.id!, title: 'Conversation'));
    case DeepLinkKind.reviews:
      return openReviews(context);
    case DeepLinkKind.kyc:
      return openKyc(context);
    case DeepLinkKind.businessRequest:
      return openBusiness(context);
    case DeepLinkKind.announcement:
      return pushPage(context, AnnouncementsScreen(highlightId: link.id));
    case DeepLinkKind.contract:
      return pushPage(context, ContractScreen(id: link.id!));
    case DeepLinkKind.posting:
      return pushPage(context, PostingScreen(id: link.id!));
    case DeepLinkKind.replacements:
      return pushPage(context, const ReplacementsScreen());
    case DeepLinkKind.notifications:
      return openNotifications(context);
    case DeepLinkKind.explore || DeepLinkKind.bookings || DeepLinkKind.messages:
      Navigator.of(context).popUntil((r) => r.isFirst);
      dashboardTabRequest.value = switch (link.kind) { DeepLinkKind.explore => 1, DeepLinkKind.bookings => 2, _ => 3 };
      return Future.value();
    case DeepLinkKind.pro:
      final provider = context.read<DashboardController>().data?.isProvider ?? false;
      return provider ? openProviderHub(context) : openProvide(context);
    case DeepLinkKind.flashOffer:
      return context.read<FlashController>().present(link.id!);
    case DeepLinkKind.flashRequest:
      return pushPage(context, FlashRequestScreen(requestId: link.id!));
    case DeepLinkKind.availability:
      return pushPage(context, const FlashOffersScreen());
    case DeepLinkKind.trustPenalty:
      return openReputation(context);
    case DeepLinkKind.home:
      Navigator.of(context).popUntil((r) => r.isFirst);
      dashboardTabRequest.value = 0;
      return Future.value();
    case DeepLinkKind.categories:
      return pushPage(context, const AllCategoriesScreen());
    case DeepLinkKind.category:
      return _openCategory(context, link.id!);
    case DeepLinkKind.services:
      return pushPage(context, const AllServicesScreen());
    case DeepLinkKind.service:
      return pushPage(context, ServiceLinkScreen(serviceId: link.id!));
    case DeepLinkKind.search:
      return pushPage(context, const SearchScreen());
    case DeepLinkKind.urgent:
      return pushPage(context, const AllUrgentServicesScreen());
    case DeepLinkKind.panne:
      return pushPage(context, const PanneScreen());
    case DeepLinkKind.flashOrder:
      return pushPage(context, const FlashRequestFormScreen());
    case DeepLinkKind.favorites:
      return pushPage(context, const FlashFavoritesScreen());
    case DeepLinkKind.profile:
      return openAccount(context);
    case DeepLinkKind.addresses:
      return openAddresses(context);
    case DeepLinkKind.reputation:
      return openReputation(context);
    case DeepLinkKind.badge:
      return openMyBadge(context);
    case DeepLinkKind.engagements:
      return openEngagements(context);
    case DeepLinkKind.business:
      return openBusiness(context);
  }
}

