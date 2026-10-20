// lib/screens/dashboard/dash_nav.dart
//
// Navigation depuis l'espace unifié vers les écrans (existants ou nouveaux).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/engagements/contract_screen.dart';
import 'package:flutter_tratra/engagements/engagements_home.dart';
import 'package:flutter_tratra/engagements/posting_screen.dart';
import 'package:flutter_tratra/engagements/replacements_screen.dart';
import 'package:flutter_tratra/kyc/identity_flow_screen.dart';
import 'package:flutter_tratra/onboarding/onboarding_entry.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/business/business_screens.dart';
import 'package:flutter_tratra/screens/auth/profile_screen.dart';
import 'package:flutter_tratra/screens/dashboard/addresses_screen.dart';
import 'package:flutter_tratra/screens/dashboard/announcements_screen.dart';
import 'package:flutter_tratra/screens/dashboard/bookings_screen.dart';
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

/// Ouvre l'objet désigné par un lien profond (notification touchée, centre de notifications, bandeau).
/// Chaque écran recharge ses données auprès du serveur : un objet supprimé ou interdit s'affiche comme une erreur normale.
Future<void> openDeepLink(BuildContext context, DeepLink link) {
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
  }
}

