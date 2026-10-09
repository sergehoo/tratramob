// lib/screens/dashboard/dash_nav.dart
//
// Navigation depuis l'espace unifié vers les écrans (existants ou nouveaux).
import 'package:flutter/material.dart';

import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/auth/profile_screen.dart';
import 'package:flutter_tratra/screens/dashboard/bookings_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/notifications_screen.dart';
import 'package:flutter_tratra/screens/dashboard/provider_screens.dart';
import 'package:flutter_tratra/screens/dashboard/reviews_screen.dart';
import 'package:flutter_tratra/screens/dashboard/wallet_screen.dart';
import 'package:flutter_tratra/screens/tracking_screen.dart';
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
Future<void> openNotifications(BuildContext context) => pushPage(context, const NotificationsScreen());
Future<void> openProvide(BuildContext context) => pushPage(context, const ProvideScreen());
Future<void> openProProfile(BuildContext context) => pushPage(context, const ProProfileScreen());
Future<void> openKyc(BuildContext context) => pushPage(context, const KycScreen());
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
