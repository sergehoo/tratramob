// lib/routes.dart
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/models/artisan.dart';

class RouteNames {
  static const home = '/';
  static const search = '/search';
  static const serviceDetail = '/service-detail';
  static const booking = '/booking';
  static const artisanProfile = '/artisan-profile';
  static const messaging = '/messaging';
  static const tracking = '/tracking';
  static const payment = '/payment';
  static const register = '/register';
  static const login = '/login';
  static const profile = '/profile';
  static const verifyPhone = '/verify-phone';

  static const String allNearbyArtisans = '/all-nearby-artisans';
  static const String allServices = '/all-services';
  static const String allUrgentServices = '/all-urgent-services';
  static const String allCategories = '/all-categories';
}

// ---- Arguments typés ----
class OtpArgs {
  /// Route à ouvrir une fois le téléphone vérifié (ou en choisissant « Plus tard »).
  final String nextRoute;
  const OtpArgs({this.nextRoute = RouteNames.home});
}

class ServiceDetailArgs {
  final Service service;
  ServiceDetailArgs(this.service);
}

class BookingArgs {
  final Service service;
  BookingArgs(this.service);
}

class ArtisanProfileArgs {
  final Artisan artisan;
  ArtisanProfileArgs(this.artisan);
}

class MessagingArgs {
  final String artisanName;
  final String artisanImage;
  MessagingArgs({required this.artisanName, required this.artisanImage});
}

class TrackingArgs {
  final String bookingId;
  TrackingArgs(this.bookingId);
}

class PaymentArgs {
  final double amount;
  final String serviceName;
  PaymentArgs(
      {required this.amount,
      required this.serviceName,
      required String bookingId});
}
