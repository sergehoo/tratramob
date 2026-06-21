// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tratra/screens/all_categories_screen.dart';
import 'package:flutter_tratra/screens/all_nearby_artisans_screen.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/all_urgent_services_screen.dart';
import 'package:flutter_tratra/screens/auth/register_screen.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/theme.dart';
import 'package:flutter_tratra/models/user.dart';
import 'package:flutter_tratra/routes.dart';

// Services socle
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:flutter_tratra/services/location_service.dart';
import 'package:flutter_tratra/core/base_api.dart';

// Services spécialisés
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/user_service.dart';
import 'package:flutter_tratra/services/categories_service.dart';
import 'package:flutter_tratra/services/services_service.dart';
import 'package:flutter_tratra/services/artisan_service.dart';
import 'package:flutter_tratra/services/booking_service.dart';
import 'package:flutter_tratra/services/payment_service.dart';
import 'package:flutter_tratra/services/review_service.dart';
import 'package:flutter_tratra/services/messaging_service.dart';
import 'package:flutter_tratra/services/notification_service.dart';
import 'package:flutter_tratra/services/match_service.dart';

// Compat (HomeScreen lit encore ApiService)
import 'package:flutter_tratra/services/api_service.dart';

// Écrans utilisés par _generateRoute
import 'package:flutter_tratra/screens/home_screen.dart'
    hide ServiceDetailArgs, BookingArgs;
import 'package:flutter_tratra/screens/search_screen.dart';
import 'package:flutter_tratra/screens/service_detail_screen.dart';
import 'package:flutter_tratra/screens/booking_screen.dart' hide PaymentArgs;
import 'package:flutter_tratra/screens/artisan_profile_screen.dart';
import 'package:flutter_tratra/screens/messaging_screen.dart';
import 'package:flutter_tratra/screens/tracking_screen.dart';
import 'package:flutter_tratra/screens/payment_screen.dart';
import 'package:flutter_tratra/screens/auth/profile_screen.dart';
import 'package:flutter_tratra/screens/auth/login_screen.dart';

// Lightweight fallback CategoriesService for bootstrap when original
// implementation isn't available or misnamed in imports.
// This minimal implementation is only to satisfy the type system used by
// ProxyProvider<BaseApi, CategoriesService> and delegates to BaseApi.
// If you have a full implementation in services/categories_service.dart,
// remove this fallback to avoid duplicate definitions.
class CategoriesService {
  final BaseApi api;
  CategoriesService(this.api);
}

// Lightweight fallback UserService for bootstrap when original
// implementation isn't available or misnamed in imports.
// This minimal implementation is only to satisfy the type system used by
// ProxyProvider<BaseApi, UserService> and delegates to BaseApi.
// If you have a full implementation in services/user_service.dart,
// remove this fallback to avoid duplicate definitions.
class UserService {
  final BaseApi api;
  UserService(this.api);
}

// Lightweight fallback ServicesService for bootstrap when original
// implementation isn't available or misnamed in imports.
// This minimal implementation is only to satisfy the type system used by
// ProxyProvider<BaseApi, ServicesService> and delegates to BaseApi.
// If you have a full implementation in services/services_service.dart,
// remove this fallback to avoid duplicate definitions.
class ServicesService {
  final BaseApi api;
  ServicesService(this.api);
}

// Lightweight fallback ArtisanService for bootstrap when original
// implementation isn't available or misnamed in imports.
// This minimal implementation is only to satisfy the type system used by
// ProxyProvider<BaseApi, ArtisanService> and delegates to BaseApi.
// If you have a full implementation in services/artisan_service.dart,
// remove this fallback to avoid duplicate definitions.
class ArtisanService {
  final BaseApi api;
  ArtisanService(this.api);
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
    };

    // Init services
    final storage = StorageService();
    await storage.init();
    final baseApi = BaseApi();
    final location = LocationService();

    runApp(
      MultiProvider(
        providers: [
          // Socle
          Provider<StorageService>.value(value: storage),
          Provider<BaseApi>.value(value: baseApi),

          Provider<LocationService>.value(value: location),

          // Services spécialisés branchés sur BaseApi
          ProxyProvider<BaseApi, AuthService>(
            update: (_, api, __) => AuthService(api),
          ),
          ProxyProvider<BaseApi, UserService>(
            update: (_, api, __) => UserService(api),
          ),
          ProxyProvider<BaseApi, CategoriesService>(
            update: (_, api, __) => CategoriesService(api),
          ),
          ProxyProvider<BaseApi, ServicesService>(
            update: (_, api, __) => ServicesService(api),
          ),
          ProxyProvider<BaseApi, ArtisanService>(
            update: (_, api, __) => ArtisanService(api),
          ),
          ProxyProvider<BaseApi, BookingService>(
            update: (_, api, __) => BookingService(api),
          ),
          ProxyProvider<BaseApi, PaymentService>(
            update: (_, api, __) => PaymentService(api),
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

          // 🔁 Compat : fournir aussi ApiService si des écrans l'utilisent encore
          Provider<ApiService>(
            create: (_) => ApiService(),
          ),
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
  late Future<(User?, String?)> _bootFuture;

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    _bootFuture = Future.wait([
      storage.getUserData(), // -> User?
      storage.getAuthToken(), // -> String?
    ])
        .then<(User?, String?)>(
          (list) => (list[0] as User?, list[1] as String?),
        )
        .timeout(const Duration(seconds: 8));
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    // ignore: avoid_print
    print('onGenerateRoute -> ${settings.name}');
    switch (settings.name) {
      case RouteNames.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());

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
        body: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseApi = context.read<BaseApi>();

    return FutureBuilder<(User?, String?)>(
      future: _bootFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: Text(
                  'Erreur au démarrage:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final (user, token) = snap.data ?? (null, null);

        // Hydrater BaseApi (et donc tous les ProxyProviders)
        if (token != null && token.isNotEmpty) {
          baseApi.setAuthToken(token);
        }

        final initialRoute = (user != null && token != null && token.isNotEmpty)
            ? RouteNames.home
            : '/login';

        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Tratra Pro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          initialRoute: initialRoute,
          onGenerateRoute: _generateRoute,
        );
      },
    );
  }
}
// // main.dart
// import 'dart:async';
// import 'dart:ui';

// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';

// import 'package:flutter_tratra/core/theme.dart';
// import 'package:flutter_tratra/models/user.dart';
// import 'package:flutter_tratra/routes.dart';

// // Screens
// import 'package:flutter_tratra/screens/auth/login_screen.dart';
// import 'package:flutter_tratra/screens/home_screen.dart';
// import 'package:flutter_tratra/screens/search_screen.dart';
// import 'package:flutter_tratra/screens/service_detail_screen.dart';
// import 'package:flutter_tratra/screens/booking_screen.dart';
// import 'package:flutter_tratra/screens/artisan_profile_screen.dart';
// import 'package:flutter_tratra/screens/messaging_screen.dart';
// import 'package:flutter_tratra/screens/tracking_screen.dart';
// import 'package:flutter_tratra/screens/payment_screen.dart';
// import 'package:flutter_tratra/screens/profile_screen.dart';
// import 'package:flutter_tratra/routes.dart';
// // Services
// import 'package:flutter_tratra/services/storage_service.dart';
// import 'package:flutter_tratra/services/api_service.dart';
// import 'package:flutter_tratra/services/storage_service.dart';
// import 'package:flutter_tratra/services/location_service.dart';
// // Args

// final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// void main() {
//   // Tout dans la MÊME zone que runApp => plus de "Zone mismatch"
//   runZonedGuarded(() async {
//     WidgetsFlutterBinding.ensureInitialized();

//     // Logging des erreurs Flutter
//     FlutterError.onError = (FlutterErrorDetails details) {
//       FlutterError.dumpErrorToConsole(details);
//     };

//     // Instanciation "légère" avant runApp (pas d'I/O bloquante ici)
//     final storage = StorageService(); // pas de read synchrones ici
//     final api = ApiService();
//     final location = LocationService();

//     runApp(
//       MultiProvider(
//         providers: [
//           Provider<StorageService>.value(value: storage),
//           Provider<ApiService>.value(value: api),
//           Provider<LocationService>.value(value: location),
//         ],
//         child: const TratraApp(),
//       ),
//     );
//   }, (error, stack) {
//     // Fallback global
//     // (garde au log pour t’aider à diagnostiquer un écran blanc silencieux)
//     // ignore: avoid_print
//     print('Uncaught in zone: $error\n$stack');
//   });
// }

// class TratraApp extends StatelessWidget {
//   const TratraApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     // Sécurise l’accès aux providers : si un manque => page d’avertissement
//     final hasApi = context.read<ApiService?>() != null;
//     final hasStorage = context.read<StorageService?>() != null;

//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Tratra',
//       theme: ThemeData(
//         useMaterial3: true,
//         colorSchemeSeed: const Color(0xFF00B14F),
//         scaffoldBackgroundColor: const Color(0xFFF8F9FA),
//       ),
//       // IMPORTANT : assure une route d’accueil.
//       initialRoute: RouteNames.home,
//       onGenerateRoute: AppRoutes.onGenerateRoute,
//       // Si providers manquants, évite l’écran blanc, montre un message clair
//       home: (!hasApi || !hasStorage)
//           ? const _BootstrapGuard()
//           : const HomeScreen(),
//     );
//   }
// }

// class AppRoutes {
//   static RouteFactory? get onGenerateRoute => null;
// }

// class MyApp extends StatefulWidget {
//   const MyApp({super.key});

//   @override
//   State<MyApp> createState() => _MyAppState();
// }

// class _MyAppState extends State<MyApp> {
//   late Future<(User?, String?)> _bootFuture;

//   @override
//   void initState() {
//     super.initState();

//     final storage = context.read<StorageService>();
//     _bootFuture = Future.wait([
//       storage.getUserData(),
//       storage.getAuthToken(),
//     ])
//         .timeout(const Duration(seconds: 8))
//         .then((list) => (list[0] as User?, list[1] as String?));
//   }

//   Route<dynamic> _generateRoute(RouteSettings settings) {
//     debugPrint('onGenerateRoute -> ${settings.name}');
//     switch (settings.name) {
//       case RouteNames.home:
//         return MaterialPageRoute(builder: (_) => const HomeScreen());

//       case RouteNames.search:
//         return MaterialPageRoute(builder: (_) => const SearchScreen());

//       case RouteNames.serviceDetail:
//         {
//           final args = settings.arguments;
//           if (args is ServiceDetailArgs) {
//             return MaterialPageRoute(
//               builder: (_) => ServiceDetailScreen(service: args.service),
//             );
//           }
//           throw ArgumentError('ServiceDetailScreen requiert ServiceDetailArgs');
//         }

//       case RouteNames.booking:
//         {
//           final args = settings.arguments;
//           if (args is BookingArgs) {
//             return MaterialPageRoute(
//               builder: (_) => BookingScreen.withService(service: args.service),
//             );
//           }
//           // Fallback : écran de mes réservations si aucun arg fourni
//           return MaterialPageRoute(builder: (_) => const BookingScreen());
//         }

//       case RouteNames.artisanProfile:
//         {
//           final args = settings.arguments;
//           if (args is ArtisanProfileArgs) {
//             return MaterialPageRoute(
//               builder: (_) => ArtisanProfileScreen(artisan: args.artisan),
//             );
//           }
//           throw ArgumentError(
//               'ArtisanProfileScreen requiert ArtisanProfileArgs');
//         }

//       case RouteNames.messaging:
//         {
//           final args = settings.arguments;
//           if (args is MessagingArgs) {
//             return MaterialPageRoute(
//               builder: (_) => MessagingScreen(
//                 artisanName: args.artisanName,
//                 artisanImage: args.artisanImage,
//               ),
//             );
//           }
//           throw ArgumentError('MessagingScreen requiert MessagingArgs');
//         }

//       case RouteNames.tracking:
//         {
//           final args = settings.arguments;
//           if (args is TrackingArgs) {
//             return MaterialPageRoute(
//               builder: (_) => TrackingScreen(bookingId: args.bookingId),
//             );
//           }
//           throw ArgumentError('TrackingScreen requiert TrackingArgs');
//         }

//       case RouteNames.payment:
//         {
//           final args = settings.arguments;
//           if (args is PaymentArgs) {
//             return MaterialPageRoute(
//               builder: (_) => PaymentScreen(
//                 amount: args.amount,
//                 serviceName: args.serviceName,
//               ),
//             );
//           }
//           throw ArgumentError('PaymentScreen requiert PaymentArgs');
//         }

//       // Auth & profil
//       case '/login':
//         return MaterialPageRoute(builder: (_) => const LoginScreen());

//       case '/profile':
//         return MaterialPageRoute(builder: (_) => const ProfileScreen());

//       // Mes réservations list
//       case '/bookings':
//         return MaterialPageRoute(builder: (_) => const BookingScreen());

//       default:
//         return MaterialPageRoute(
//           builder: (_) => const Scaffold(
//             body: Center(child: Text('Route inconnue')),
//           ),
//         );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final api = context.read<ApiService>();

//     return FutureBuilder<(User?, String?)>(
//       future: _bootFuture,
//       builder: (context, snap) {
//         // Splash
//         if (snap.hasError) {
//           return MaterialApp(
//             debugShowCheckedModeBanner: false,
//             theme: AppTheme.lightTheme,
//             home: Scaffold(
//               body: Center(
//                 child: Text('Erreur au démarrage:\n${snap.error}',
//                     textAlign: TextAlign.center),
//               ),
//             ),
//           );
//         }
//         if (snap.connectionState == ConnectionState.waiting) {
//           return MaterialApp(
//             navigatorKey: appNavigatorKey,
//             debugShowCheckedModeBanner: false,
//             theme: AppTheme.lightTheme,
//             home: const Scaffold(
//               body: Center(child: CircularProgressIndicator()),
//             ),
//           );
//         }

//         final (user, token) = snap.data ?? (null, null);

//         // (Re)hydrate api si besoin
//         if (token != null && token.isNotEmpty) {
//           api.setAuthToken(token);
//         }

//         final initialRoute = (user != null && token != null && token.isNotEmpty)
//             ? RouteNames.home
//             : '/login';

//         return MaterialApp(
//           navigatorKey: appNavigatorKey,
//           title: 'Tratra Pro',
//           debugShowCheckedModeBanner: false,
//           theme: AppTheme.lightTheme,
//           // initialRoute: initialRoute,
//           // onGenerateRoute: _generateRoute,
//           initialRoute: initialRoute,
//           onGenerateRoute: _generateRoute,
//           onUnknownRoute: (settings) {
//             debugPrint('onUnknownRoute -> ${settings.name}');
//             return MaterialPageRoute(
//               builder: (_) => Scaffold(
//                 body: Center(child: Text('Route inconnue: ${settings.name}')),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }

// class _BootstrapGuard extends StatelessWidget {
//   const _BootstrapGuard();

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Center(
//         child: Column(mainAxisSize: MainAxisSize.min, children: const [
//           CircularProgressIndicator(),
//           SizedBox(height: 12),
//           Text('Initialisation…'),
//         ]),
//       ),
//     );
//   }
// }
