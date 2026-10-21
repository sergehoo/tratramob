// core/constants.dart
import 'dart:ui';

import 'package:flutter_tratra/design/tokens.dart';

class AppConstants {
  // ----- Couleurs marque -----
  // Alias des jetons du Design System (lib/design/tokens.dart, généré depuis la landing) :
  // une seule source de vérité. Les nouveaux écrans utilisent directement `TtColors`.
  static const Color primaryColor = TtColors.primary;
  static const Color primaryLight = TtColors.primarySoft;
  static const Color primaryDark = TtColors.primaryDark;
  // Accent jaune (identité Tratra, cohérent avec le web)
  static const Color accentColor = TtColors.accent;
  static const Color accentDark = TtColors.accentDark;
  static const Color accentSoft = TtColors.accentSoft;

  static const Color backgroundColor = TtColors.canvas;
  static const Color cardColor = TtColors.surface;
  static const Color textPrimary = TtColors.ink;
  static const Color textSecondary = TtColors.ash;
  static const Color borderColor = TtColors.line;
  static const Color promoColor = TtColors.danger;
  static const Color ratingColor = TtColors.accent;
  static const Color urgentColor = TtColors.danger;
  static const Color successColor = TtColors.success;
  static const Color dangerColor = TtColors.danger;
  static const Duration animationDuration = Duration(milliseconds: 160);

  // Base API — surchargée au build via --dart-define=TRATRA_API_BASE=...
  // (ex. http://10.0.2.2:8000/handy pour l'émulateur Android en local).
  static const String baseUrl = String.fromEnvironment(
    'TRATRA_API_BASE',
    defaultValue: 'https://api.tratra.net/handy',
  );

  // Fonctions financières (portefeuille, gains, retraits, écran de paiement). DÉSACTIVÉES par défaut : la version publiée sur
  // Google Play n'en propose aucune (Play réserve ces fonctions aux comptes organisation). Activables au build :
  // --dart-define=TRATRA_FINANCIAL=true. Les réservations en espèces et leur suivi restent disponibles.
  static const bool financialFeaturesEnabled = bool.fromEnvironment('TRATRA_FINANCIAL', defaultValue: false);

  // Hôte public du stockage des médias (MinIO / S3), sans barre finale — surchargeable au build via --dart-define=TRATRA_MEDIA_BASE=...
  static const String mediaBase = String.fromEnvironment(
    'TRATRA_MEDIA_BASE',
    defaultValue: 'https://minioapi.tratra.net',
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
  /// « Se souvenir de moi » décoché : la session s'arrête à la fermeture réelle de l'application (démarrage à froid suivant).
  static const String sessionOnlyKey = 'session_only';
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
