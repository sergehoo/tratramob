// core/constants.dart
import 'dart:ui';

class AppConstants {
  // ----- Couleurs marque -----
  static const Color primaryColor = Color(0xFF00B14F);
  static const Color primaryLight = Color(0xFFE8F5E9);
  static const Color primaryDark = Color(0xFF008E40);
  // Accent jaune (identité Tratra, cohérent avec le web)
  static const Color accentColor = Color(0xFFF6C90E);
  static const Color accentDark = Color(0xFFE0B400);
  static const Color accentSoft = Color(0xFFFFF4D1);

  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color borderColor = Color(0xFFE5E5E5);
  static const Color promoColor = Color(0xFFFF5252);
  static const Color ratingColor = Color(0xFFFFA000);
  static const Color urgentColor = Color(0xFFFF6B6B);
  static const Color successColor = Color(0xFF00B14F);
  static const Color dangerColor = Color(0xFFE53935);
  static const Duration animationDuration = Duration(milliseconds: 160);

  // Base API — surchargée au build via --dart-define=TRATRA_API_BASE=...
  // (ex. http://10.0.2.2:8000/handy pour l'émulateur Android en local).
  static const String baseUrl = String.fromEnvironment(
    'TRATRA_API_BASE',
    defaultValue: 'https://tratra.net/handy',
  );

  // ----- Endpoints -----
  static const String usersEndpoint = '/users';
  static const String usersMeEndpoint = '/users/me/';
  static const String loginEndpoint = '/auth/login/';
  static const String artisansEndpoint = '/handymen';
  static const String presenceEndpoint = '/handymen/presence/';
  static const String servicesEndpoint = '/services';
  static const String categoriesEndpoint = '/categories';
  static const String bookingsEndpoint = '/bookings';
  static const String paymentsEndpoint = '/payments';
  static const String paymentInitiateEndpoint = '/payments/initiate/';
  static const String payoutsEndpoint = '/payouts';
  static const String payoutsAvailableEndpoint = '/payouts/available/';
  static const String payoutAccountEndpoint = '/payout-account/';
  static const String reviewsEndpoint = '/reviews';
  static const String conversationsEndpoint = '/conversations';
  static const String messagesEndpoint = '/messages';
  static const String notificationsEndpoint = '/notifications';
  static const String handymanDocsEndpoint = '/handyman-docs';
  static const String timeOffsEndpoint = '/timeoffs';
  static const String subscriptionPlansEndpoint = '/subscription-plans';
  static const String subscriptionsEndpoint = '/subscriptions';
  static const String priceEstimateEndpoint = '/price/estimate/';
  static const String matchEndpoint = '/match/';
  static const String couponValidateEndpoint = '/coupons/validate/';
  static const String otpRequestEndpoint = '/auth/otp/request/';
  static const String otpVerifyEndpoint = '/auth/otp/verify/';

  /// Action de transition d'état d'une réservation (machine à états backend).
  static String bookingTransition(String id) => '/bookings/$id/transition/';

  // Storage keys
  static const String authTokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';
  static const String fcmTokenKey = 'fcm_token';

  // Auth
  static const String authLoginEndpoint = '/auth/login/';
  static const String authRefreshEndpoint = '/auth/refresh/';
  static const String authLogoutEndpoint = '/auth/logout/';

  // ----- Rôles (alignés sur le backend Django) -----
  static const String roleClient = 'client';
  static const String roleEmployer = 'employeur';
  static const String roleHandyman = 'handyman';
  static const String roleCompany = 'entreprise';
  static const String roleAdmin = 'admin';

  // App settings
  static const String appName = 'Tratra';
  static const String appVersion = '1.0.0';
}
