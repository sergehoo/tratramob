// core/constants.dart
import 'dart:ui';

class AppConstants {
  // Couleurs
  static const Color primaryColor = Color(0xFF00B14F);
  static const Color primaryLight = Color(0xFFE8F5E9);
  static const Color primaryDark = Color(0xFF008E40);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color borderColor = Color(0xFFE5E5E5);
  static const Color promoColor = Color(0xFFFF5252);
  static const Color ratingColor = Color(0xFFFFA000);
  static const Color urgentColor = Color(0xFFFF6B6B);
  static const Duration animationDuration = Duration(milliseconds: 160);

  static const String baseUrl = 'https://tratra.net/handy';

  // Endpoints
  static const String usersEndpoint = '/users';
  static const String loginEndpoint = '/auth/login/';
  static const String artisansEndpoint = '/handymen';
  static const String servicesEndpoint = '/services';
  static const String categoriesEndpoint = '/categories';
  static const String bookingsEndpoint = '/bookings';
  static const String paymentsEndpoint = '/payments';
  static const String reviewsEndpoint = '/reviews';
  static const String conversationsEndpoint = '/conversations';
  static const String messagesEndpoint = '/messages';
  static const String notificationsEndpoint = '/notifications';
  static const String priceEstimateEndpoint = '/price/estimate/';
  static const String matchEndpoint = '/match/';

  // Storage keys
  static const String authTokenKey = 'auth_token';
  static const String userDataKey = 'user_data';
  static const String fcmTokenKey = 'fcm_token';

  // Auth
  static const String authLoginEndpoint = '/auth/login/';
  static const String authRefreshEndpoint = '/auth/refresh/';
  static const String authLogoutEndpoint = '/auth/logout/';

  // App settings
  static const String appName = 'Tratra Pro';
  static const String appVersion = '1.0.0';
}
