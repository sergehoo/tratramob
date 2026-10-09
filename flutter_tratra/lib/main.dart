// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/theme.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/design/gallery.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/routes.dart';

// Services socle
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:flutter_tratra/services/location_service.dart';

// Services spécialisés branchés sur BaseApi
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/booking_service.dart';
import 'package:flutter_tratra/services/payment_service.dart';
import 'package:flutter_tratra/services/review_service.dart';
import 'package:flutter_tratra/services/messaging_service.dart';
import 'package:flutter_tratra/services/notification_service.dart';
import 'package:flutter_tratra/services/match_service.dart';
import 'package:flutter_tratra/services/handyman_service.dart';

// Compat : certains écrans lisent encore ApiService
import 'package:flutter_tratra/services/api_service.dart';

// Écrans
import 'package:flutter_tratra/screens/home_screen.dart';
import 'package:flutter_tratra/screens/search_screen.dart';
import 'package:flutter_tratra/screens/service_detail_screen.dart';
import 'package:flutter_tratra/screens/booking_screen.dart';
import 'package:flutter_tratra/screens/artisan_profile_screen.dart';
import 'package:flutter_tratra/screens/messaging_screen.dart';
import 'package:flutter_tratra/screens/tracking_screen.dart';
import 'package:flutter_tratra/screens/payment_screen.dart';
import 'package:flutter_tratra/screens/auth/profile_screen.dart';
import 'package:flutter_tratra/screens/auth/login_screen.dart';
import 'package:flutter_tratra/screens/auth/register_screen.dart';
import 'package:flutter_tratra/screens/all_categories_screen.dart';
import 'package:flutter_tratra/screens/all_nearby_artisans_screen.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/all_urgent_services_screen.dart';
import 'package:flutter_tratra/screens/worker/worker_home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Ouvre le guide de style au lancement (debug uniquement) :
/// `flutter run --dart-define=TRATRA_GALLERY=true`.
const bool _openGallery = bool.fromEnvironment('TRATRA_GALLERY');

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
    };

    // Init services socle
    final storage = StorageService();
    await storage.init();
    final baseApi = BaseApi();
    final location = LocationService();
    final authService = AuthService(baseApi);

    runApp(
      MultiProvider(
        providers: [
          // Socle
          Provider<StorageService>.value(value: storage),
          Provider<BaseApi>.value(value: baseApi),
          Provider<LocationService>.value(value: location),
          Provider<AuthService>.value(value: authService),

          // Session (rôle / utilisateur courant)
          ChangeNotifierProvider<Session>(
            create: (_) => Session(authService, storage),
          ),

          // Services métier (auto-refresh JWT via BaseApi)
          ProxyProvider<BaseApi, BookingService>(
            update: (_, api, __) => BookingService(api),
          ),
          ProxyProvider<BaseApi, PaymentService>(
            update: (_, api, __) => PaymentService(api),
          ),
          ProxyProvider<BaseApi, HandymanService>(
            update: (_, api, __) => HandymanService(api),
          ),
          ProxyProvider<BaseApi, ReviewService>(
            update: (_, api, __) => ReviewService(api),
          ),
          ProxyProvider<BaseApi, MessagingService>(
            update: (_, api, __) => MessagingService(api),
          ),
          ProxyProvider<BaseApi, NotificationService>(
            update: (_, api, __) => NotificationService(api),
          ),
          ProxyProvider<BaseApi, MatchService>(
            update: (_, api, __) => MatchService(api),
          ),

          // Compat
          Provider<ApiService>(create: (_) => ApiService()),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    // ignore: avoid_print
    print('Uncaught in zone: $error\n$stack');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<void> _bootFuture;

  @override
  void initState() {
    super.initState();
    // Hydrate la session (utilisateur + rôle) depuis le stockage chiffré.
    _bootFuture = context.read<Session>().loadFromStorage().timeout(
          const Duration(seconds: 8),
          onTimeout: () {},
        );
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RouteNames.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/worker':
        return MaterialPageRoute(builder: (_) => const WorkerHomeScreen());
      case RouteNames.search:
        return MaterialPageRoute(builder: (_) => const SearchScreen());
      case RouteNames.allNearbyArtisans:
        return MaterialPageRoute(
            builder: (_) => const AllNearbyArtisansScreen());
      case RouteNames.allServices:
        return MaterialPageRoute(builder: (_) => const AllServicesScreen());
      case RouteNames.allUrgentServices:
        return MaterialPageRoute(
            builder: (_) => const AllUrgentServicesScreen());
      case RouteNames.allCategories:
        return MaterialPageRoute(builder: (_) => const AllCategoriesScreen());

      case RouteNames.serviceDetail:
        final args = settings.arguments;
        if (args is ServiceDetailArgs) {
          return MaterialPageRoute(
            builder: (_) => ServiceDetailScreen(service: args.service),
          );
        }
        return _errorRoute('ServiceDetailScreen requiert ServiceDetailArgs');

      case RouteNames.booking:
        final args = settings.arguments;
        if (args is BookingArgs) {
          return MaterialPageRoute(
            builder: (_) => BookingScreen.withService(service: args.service),
          );
        }
        return MaterialPageRoute(builder: (_) => const BookingScreen());

      case RouteNames.artisanProfile:
        final args = settings.arguments;
        if (args is ArtisanProfileArgs) {
          return MaterialPageRoute(
            builder: (_) => ArtisanProfileScreen(
                artisan: args.artisan, artisanId: args.artisan.id),
          );
        }
        return _errorRoute('ArtisanProfileScreen requiert ArtisanProfileArgs');

      case RouteNames.messaging:
        final args = settings.arguments;
        if (args is MessagingArgs) {
          return MaterialPageRoute(
            builder: (_) => MessagingScreen(
              artisanName: args.artisanName,
              artisanImage: args.artisanImage,
            ),
          );
        }
        return _errorRoute('MessagingScreen requiert MessagingArgs');

      case RouteNames.tracking:
        final args = settings.arguments;
        if (args is TrackingArgs) {
          return MaterialPageRoute(
            builder: (_) => TrackingScreen(bookingId: args.bookingId),
          );
        }
        return _errorRoute('TrackingScreen requiert TrackingArgs');

      case RouteNames.payment:
        final args = settings.arguments;
        if (args is PaymentArgs) {
          return MaterialPageRoute(
            builder: (_) => PaymentScreen(
              amount: args.amount,
              serviceName: args.serviceName,
            ),
          );
        }
        return _errorRoute('PaymentScreen requiert PaymentArgs');

      case TratraGalleryScreen.route:
        // Guide de style : disponible en debug uniquement.
        if (kDebugMode) return MaterialPageRoute(builder: (_) => const TratraGalleryScreen());
        return _errorRoute('Route inconnue: ${settings.name}');

      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case '/register':
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case '/profile':
        return MaterialPageRoute(builder: (_) => const ProfileScreen());

      default:
        return _errorRoute('Route inconnue: ${settings.name}');
    }
  }

  MaterialPageRoute _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: const TratraAppBar(title: 'Tratra'),
        body: TratraEmptyState(
          icon: Icons.explore_off_outlined,
          title: 'Page introuvable',
          description: message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TratraBrandMark(size: 72),
                    SizedBox(height: 24),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final session = context.watch<Session>();
        final String initialRoute = (kDebugMode && _openGallery)
            ? TratraGalleryScreen.route
            : !session.isAuthenticated
            ? '/login'
            : (session.isHandyman ? '/worker' : RouteNames.home);

        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Tratra',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          initialRoute: initialRoute,
          onGenerateRoute: _generateRoute,
        );
      },
    );
  }
}
