// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/theme.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/design/gallery.dart';
import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/continuity/activities_controller.dart';
import 'package:flutter_tratra/continuity/drafts.dart';
import 'package:flutter_tratra/continuity/offline_queue.dart';
import 'package:flutter_tratra/continuity/vault.dart';
import 'package:flutter_tratra/engagements/evidence_viewer.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_native.dart';
import 'package:flutter_tratra/routes.dart';

// Services socle
import 'package:flutter_tratra/services/storage_service.dart';
import 'package:flutter_tratra/services/location_service.dart';

// Services spécialisés branchés sur BaseApi
import 'package:flutter_tratra/services/auth_service.dart';
import 'package:flutter_tratra/services/booking_service.dart';
import 'package:flutter_tratra/services/cash_service.dart';
import 'package:flutter_tratra/services/payment_service.dart';
import 'package:flutter_tratra/services/review_service.dart';
import 'package:flutter_tratra/services/messaging_service.dart';
import 'package:flutter_tratra/services/notification_service.dart';
import 'package:flutter_tratra/services/push_service.dart';
import 'package:flutter_tratra/services/match_service.dart';
import 'package:flutter_tratra/services/handyman_service.dart';

// Compat : certains écrans lisent encore ApiService
import 'package:flutter_tratra/services/api_service.dart';

// Écrans
import 'package:flutter_tratra/screens/home_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_screen.dart';
import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/core/notification_links.dart';
import 'package:flutter_tratra/core/route_observer.dart';
import 'package:flutter_tratra/services/home_widget_sync.dart';
import 'package:flutter_tratra/engagements/engagements_api.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/search_screen.dart';
import 'package:flutter_tratra/screens/service_detail_screen.dart';
import 'package:flutter_tratra/screens/booking_screen.dart';
import 'package:flutter_tratra/screens/artisan_profile_screen.dart';
import 'package:flutter_tratra/screens/messaging_screen.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/notifications/notice_banner.dart';
import 'package:flutter_tratra/notifications/notice_center.dart';
import 'package:flutter_tratra/notifications/screen_presence.dart';
import 'package:flutter_tratra/onboarding/onboarding_api.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_presence.dart';
import 'package:flutter_tratra/screens/tracking_screen.dart';
import 'package:flutter_tratra/screens/payment_screen.dart';
import 'package:flutter_tratra/screens/auth/profile_screen.dart';
import 'package:flutter_tratra/screens/auth/login_screen.dart';
import 'package:flutter_tratra/screens/auth/otp_screen.dart';
import 'package:flutter_tratra/screens/auth/forgot_password_screen.dart';
import 'package:flutter_tratra/screens/auth/register_screen.dart';
import 'package:flutter_tratra/screens/all_categories_screen.dart';
import 'package:flutter_tratra/screens/panne_screen.dart';
import 'package:flutter_tratra/screens/all_nearby_artisans_screen.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/all_urgent_services_screen.dart';
import 'package:flutter_tratra/screens/worker/worker_home_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Ouvre le guide de style au lancement (debug uniquement) :
/// `flutter run --dart-define=TRATRA_GALLERY=true`.
const bool _openGallery = bool.fromEnvironment('TRATRA_GALLERY');

/// App en français (sélecteurs de date/heure, boutons système…).
const Locale _appLocale = Locale('fr');
const List<Locale> _supportedLocales = [Locale('fr'), Locale('en')];

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
    final push = PushService(baseApi);
    final vault = ContinuityVault();
    // Copies temporaires d'un PDF privé laissées par une lecture interrompue (application fermée pendant l'affichage).
    unawaited(EvidenceFiles.purge());

    runApp(
      MultiProvider(
        providers: [
          // Socle
          Provider<StorageService>.value(value: storage),
          Provider<BaseApi>.value(value: baseApi),
          Provider<LocationService>.value(value: location),
          Provider<AuthService>.value(value: authService),

          // Continuité : coffre chiffré cloisonné par compte, brouillons, activités en cours, file hors ligne (actions sûres)
          Provider<ContinuityVault>.value(value: vault),
          Provider<DraftStore>.value(value: DraftStore(vault)),

          // Notifications push (FCM, Android) : appareil rattaché au compte courant
          ChangeNotifierProvider<PushService>.value(value: push),
          // Rubans de notification, application ouverte : un à la fois, sans doublon, Tratra Flash en priorité
          ChangeNotifierProvider<NoticeCenter>(create: (_) => NoticeCenter()),

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
          ProxyProvider<BaseApi, CashService>(
            update: (_, api, __) => CashService(api),
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

          // Engagements récurrents et de longue durée (API commune web/Flutter)
          ProxyProvider<BaseApi, EngagementsApi>(
            update: (_, api, __) => EngagementsApi(api),
          ),

          // Messagerie temps réel et statuts : une WebSocket par session (billet signé), rattrapage par l'API
          ProxyProvider<BaseApi, MessagingApi>(
            update: (_, api, __) => MessagingApi(api),
          ),
          ProxyProvider<BaseApi, StatusApi>(
            update: (_, api, __) => StatusApi(api),
          ),
          ChangeNotifierProxyProvider3<BaseApi, MessagingApi, Session, InboxController>(
            create: (ctx) => InboxController(ctx.read<BaseApi>(), ctx.read<MessagingApi>()),
            update: (_, base, api, session, prev) {
              final c = prev ?? InboxController(base, api);
              unawaited(c.bindUser(session.user?.id));
              return c;
            },
          ),
          // Anneaux des statuts sur les avatars (accueil, messagerie, profils), comme WhatsApp
          ChangeNotifierProxyProvider3<StatusApi, InboxController, Session, StatusPresence>(
            create: (ctx) => StatusPresence(ctx.read<StatusApi>(), ctx.read<InboxController>()),
            update: (_, api, inbox, session, prev) {
              final p = prev ?? StatusPresence(api, inbox);
              p.bindUser(session.user?.id);
              return p;
            },
          ),

          // Espace unifié : API bornée au compte courant + données partagées (purgées au changement de compte)
          ProxyProvider<BaseApi, DashboardApi>(
            update: (_, api, __) => DashboardApi(api),
          ),
          ChangeNotifierProxyProvider2<DashboardApi, Session, DashboardController>(
            create: (ctx) => DashboardController(ctx.read<DashboardApi>()),
            update: (_, api, session, prev) {
              final c = prev ?? DashboardController(api);
              c.bindUser(session.user?.id);
              return c;
            },
          ),

          ChangeNotifierProxyProvider2<DashboardApi, Session, ActivitiesController>(
            create: (ctx) => ActivitiesController(fetch: ctx.read<DashboardApi>().getMap, vault: vault)..startObserving(),
            update: (_, api, session, prev) {
              final c = prev ?? ActivitiesController(fetch: api.getMap, vault: vault)..startObserving();
              unawaited(c.bindUser(session.user?.id));
              return c;
            },
          ),
          ChangeNotifierProxyProvider2<BaseApi, Session, OfflineQueue>(
            create: (ctx) => OfflineQueue(send: (a) => _sendQueued(ctx.read<BaseApi>(), a), vault: vault),
            update: (_, api, session, prev) {
              final q = prev ?? OfflineQueue(send: (a) => _sendQueued(api, a), vault: vault);
              unawaited(q.bindUser(session.user?.id));
              return q;
            },
          ),

          // Tratra Flash : réception des nouvelles missions (écran, sonnerie, actions des alertes), demandes des clients
          ChangeNotifierProvider<FlashController>(
            create: (ctx) => FlashController(
              api: FlashApi(ctx.read<BaseApi>()),
              native: MethodChannelFlashNative(),
              navigatorKey: appNavigatorKey,
              isAuthenticated: () => ctx.read<Session>().isAuthenticated,
            )..attachLive(ctx.read<InboxController>().events),   // proposition close ou modifiée, liaison rétablie
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

/// Envoi d'une action de la file hors ligne (jeton + rafraîchissement automatique via BaseApi). Renvoie le code HTTP ;
/// une panne réseau lève une exception : l'action reste en file.
Future<int> _sendQueued(BaseApi api, QueuedAction a) async {
  final uri = Uri.parse('${api.baseUrl}${a.path}');
  final headers = await api.headers;
  final body = a.body == null ? '{}' : jsonEncode(a.body);
  final r = a.method == 'PATCH'
      ? await api.client.patch(uri, headers: headers, body: body)
      : await api.client.post(uri, headers: headers, body: body);
  return r.statusCode;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

/// Prévient à chaque changement d'écran : une notification touchée pendant la connexion s'ouvre dès que l'espace est affiché.
class _RouteChanges extends NavigatorObserver {
  _RouteChanges(this.onChange);
  final VoidCallback onChange;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => onChange();
}

/// Écrans de connexion : rien ne s'ouvre par-dessus, la notification touchée attend la fin de la connexion.
const Set<String> _authRoutes = {RouteNames.login, RouteNames.register, RouteNames.verifyPhone, RouteNames.forgotPassword};

/// Durée pendant laquelle une notification touchée attend que l'application soit prête (démarrage, connexion).
const Duration _pendingTapTtl = Duration(minutes: 5);

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final Future<void> _bootFuture;
  late final Session _session = context.read<Session>();
  late final PushService _push = context.read<PushService>();
  late final DashboardController _dash = context.read<DashboardController>();
  late final NoticeCenter _notices = context.read<NoticeCenter>();
  late final FlashController _flash = context.read<FlashController>();
  late final _RouteChanges _routeChanges = _RouteChanges(_flushPendingTapSoon);
  StreamSubscription<Uri?>? _widgetClicks;
  String? _pendingLink;
  bool _booted = false;
  // Notification touchée avant que l'application ne soit prête : gardée puis ouverte (une seule, la dernière).
  PushMessage? _pendingTap;
  DateTime? _pendingTapAt;
  bool _flushScheduled = false;
  Timer? _refresh;
  String? _noticeUser;

  @override
  void initState() {
    super.initState();
    // Hydrate la session (utilisateur + rôle) depuis le stockage chiffré.
    final session = _session;
    final push = _push;
    session.onBeforeLogout = push.unregister;
    // Déconnexion volontaire : brouillons, file hors ligne et activités mises en cache sont effacés.
    session.addLogoutWipe(context.read<ContinuityVault>().wipeAll);
    session.addLogoutWipe(context.read<ActivitiesController>().wipe);
    session.addLogoutWipe(context.read<OfflineQueue>().wipe);
    // Chaque synchronisation réussie (retour du réseau, reprise au premier plan) vide la file des actions sûres.
    context.read<ActivitiesController>().onSynced = context.read<OfflineQueue>().flush;
    push.onForeground = _onPushForeground;
    push.onTap = _onPushTap;
    session.addListener(_syncPush);
    // Rubans : toucher → objet concerné ; signal sonore ; rien pour ce qui est déjà à l'écran ni par-dessus l'écran Tratra Flash.
    _notices
      ..onOpen = ((n) => _openFromPush(n.message))
      ..onShow = _onNoticeShown
      ..suppress = _noticeOnScreen;
    _flash.addListener(_syncNoticeHold);
    session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    // Widget d'accueil : données minimales mises à jour à chaque synchronisation de l'espace, effacées à la déconnexion.
    session.addLogoutWipe(HomeWidgetSync.clear);
    session.addLogoutWipe(OnboardingApi.clearStored);
    _dash.addListener(_syncHomeWidget);
    // Raccourcis d'application et widget : mêmes liens profonds que les notifications.
    AppShortcuts.init(_openLink);
    HomeWidgetSync.initialLink().then((uri) {
      if (uri != null) _openLink(uri.toString());
    });
    _widgetClicks = HomeWidgetSync.clicks.listen((uri) {
      if (uri != null) _openLink(uri.toString());
    });
    // « Se souvenir de moi » décoché : une session ouverte avant la fermeture réelle de l'application ne survit pas au démarrage.
    _bootFuture = session.endSessionOnlyAtColdStart().then((_) => session.loadFromStorage()).timeout(
          const Duration(seconds: 10),
          onTimeout: () {},
        );
    // Push : démarré une fois la session connue, sans bloquer l'affichage.
    final flash = context.read<FlashController>();
    _bootFuture.whenComplete(() {
      _syncPush();
      unawaited(push.start());
      unawaited(flash.start());   // action d'une alerte qui a lancé l'application, réglages sonores
      _booted = true;
      final pending = _pendingLink;
      _pendingLink = null;
      if (pending != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openLink(pending));
      _flushPendingTapSoon();
      // Annonces avec image (notification construite par l'application) : lien touché, y compris au lancement à froid.
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(NotificationLinks.start(_onNotificationTap)));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_syncPush);
    _session.removeListener(_onSessionChanged);
    _flash.removeListener(_syncNoticeHold);
    _dash.removeListener(_syncHomeWidget);
    _widgetClicks?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  void _syncHomeWidget() {
    final data = _dash.data;
    if (data != null) {
      unawaited(HomeWidgetSync.update(data));
    } else if (_dash.sessionExpired) {
      unawaited(HomeWidgetSync.clear());
    }
  }

  /// Raccourci d'application ou widget : ouvre la destination (connexion d'abord si elle l'exige). Avant la fin du démarrage, le lien
  /// est gardé puis ouvert dès que l'écran est prêt.
  void _openLink(String uri) {
    if (!_booted) {
      _pendingLink = uri;
      return;
    }
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final link = parseDeepLink({'deeplink': uri});
    if (requiresSignIn(link) && !_session.isAuthenticated) {
      Navigator.of(ctx).pushNamed(RouteNames.login);
      return;
    }
    if (link.kind == DeepLinkKind.explore && !_session.isAuthenticated) {
      Navigator.of(ctx).pushNamed(RouteNames.explore);
      return;
    }
    openDeepLink(ctx, link);
  }

  /// L'appareil suit toujours le compte connecté (enregistré à la connexion, retiré à la déconnexion).
  void _syncPush() {
    unawaited(_push.bindUser(_session.user?.id));
  }

  /// Notification reçue application ouverte : ruban flottant en haut de l'écran (un à la fois, sans doublon, touchable → objet
  /// concerné) et compteur à jour. Nouvelle mission Tratra Flash : écran dédié avec sonnerie, jamais le ruban en plus.
  void _onPushForeground(PushMessage m, [int attempt = 0]) {
    if (!mounted || !_session.isAuthenticated) return;
    if (appNavigatorKey.currentState == null) {
      // Tout début de session : la navigation n'est pas encore construite — nouvel essai à l'image suivante.
      if (attempt < 20) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _onPushForeground(m, attempt + 1));
        WidgetsBinding.instance.ensureVisualUpdate();
      }
      return;
    }
    if (_flash.handlePush(m.data)) return;
    _refreshSoon();
    _notices.arrivals.value++;
    final notice = AppNotice.fromPush(m);
    if (notice != null && _noticeOnScreen(notice)) {
      // Objet déjà sous les yeux : pas de ruban, la notification est lue ; Tratra Flash garde son signal sonore.
      if (_notices.markSeen(m)) {
        _markNotificationRead(int.tryParse('${m.data['nid'] ?? ''}'));
        if (notice.priority && _flash.showing == null) _chime();
      }
      return;
    }
    _notices.offer(m);
  }

  /// Objet déjà sous les yeux (conversation ouverte, demande suivie, proposition affichée) : pas de ruban.
  bool _noticeOnScreen(AppNotice n) {
    final link = n.link;
    if (ScreenPresence.isVisible(ScreenPresence.targetOf(link))) return true;
    return link.kind == DeepLinkKind.flashOffer && link.id != null && link.id == _flash.showing;
  }

  /// Ruban devenu visible : signal sonore court, sauf catégories discrètes (annonces, conseils…) et ruban déjà montré.
  void _onNoticeShown(AppNotice n, bool replay) {
    if (replay || n.quiet || _flash.showing != null) return;
    _chime();
  }

  /// Réglages son/vibration de Tratra et mode du téléphone respectés. iOS : le son est joué par le système à la réception.
  void _chime() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(_flash.native
        .play('tratra_notification', withSound: _flash.soundOn, withVibration: _flash.vibrationOn)
        .then<void>((_) {}, onError: (_) {}));
  }

  /// Écran Tratra Flash affiché (sonnerie, décision à prendre) : aucun ruban par-dessus ; ils reprennent à sa fermeture, comme la
  /// notification touchée entre-temps.
  void _syncNoticeHold() {
    _notices.hold(_flash.showing != null);
    if (_flash.showing == null) _flushPendingTapSoon();
  }

  /// Déconnexion ou changement de compte : plus aucun ruban ni lien en attente du compte précédent. Connexion : la notification
  /// touchée auparavant s'ouvre.
  void _onSessionChanged() {
    final id = _session.user?.id;
    if (id != _noticeUser) {
      if (_noticeUser != null) {
        _pendingTap = null;
        _pendingTapAt = null;
        unawaited(_notices.clear());
      }
      _noticeUser = id;
    }
    _flushPendingTapSoon();
  }

  /// Retour au premier plan : permission peut-être modifiée dans les réglages du téléphone, notifications reçues entre-temps
  /// (compteur, centre de notifications affiché), notification touchée qui attendait.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_booted) return;
    unawaited(_push.recheck());
    if (_session.isAuthenticated) {
      _refreshSoon();
      _notices.arrivals.value++;
    }
    _flushPendingTapSoon();
  }

  /// Compteur de notifications et tableau de bord : une seule relecture pour une rafale de messages.
  void _refreshSoon() {
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 600), () {
      if (mounted && _session.isAuthenticated) unawaited(_dash.load());
    });
  }

  /// Notification touchée (application en arrière-plan ou fermée) : ouvre directement l'objet concerné, une seule fois même si
  /// le système la remet deux fois.
  void _onPushTap(PushMessage m) {
    if (_notices.firstOpen(m)) _openFromPush(m);
  }

  bool _onAuthRoute(NavigatorState nav) {
    String? top;
    nav.popUntil((route) {
      top = route.settings.name;
      return true;      // rien n'est dépilé : lecture de l'écran du dessus
    });
    return _authRoutes.contains(top);
  }

  void _keepTap(PushMessage m, DateTime? since) {
    _pendingTap = m;
    _pendingTapAt = since ?? DateTime.now();
  }

  /// Ouvre l'objet d'une notification touchée (ruban, barre du système, lancement à froid). Tant que l'application n'est pas
  /// prête — démarrage, navigation pas encore construite, connexion ou vérification du téléphone en cours, décision Tratra Flash
  /// à l'écran — la notification est gardée (5 minutes au plus) puis ouverte dès que possible : jamais de lien perdu, jamais
  /// d'écran ouvert par-dessus la connexion.
  void _openFromPush(PushMessage m, {DateTime? since}) {
    final nav = appNavigatorKey.currentState;
    final ctx = appNavigatorKey.currentContext;
    if (!_booted || nav == null || ctx == null || !ctx.mounted) {
      _keepTap(m, since);
      return;
    }
    final onAuth = _onAuthRoute(nav);
    if (!_session.isAuthenticated || onAuth) {
      _keepTap(m, since);
      // Visiteur non connecté ailleurs que sur la connexion : on l'y amène, la notification s'ouvrira ensuite.
      if (!onAuth) nav.pushNamed(RouteNames.login);
      return;
    }
    final link = parseDeepLink(m.data);
    if (_flash.showing != null && link.kind != DeepLinkKind.flashOffer) {
      _keepTap(m, since);     // la proposition à l'écran d'abord (délai court) ; ouverte à sa fermeture
      return;
    }
    if (m.data['t'] == 'announcement') _markAnnouncementOpened(int.tryParse('${m.data['id'] ?? ''}'));
    _markNotificationRead(int.tryParse('${m.data['nid'] ?? ''}'));
    // Écran de l'objet déjà ouvert (conversation, demande suivie) : on y revient au lieu d'en empiler un second.
    if (ScreenPresence.reveal(ScreenPresence.targetOf(link))) return;
    // L'objet est rechargé auprès du serveur : un lien d'un autre compte (changement de compte) échoue proprement.
    openDeepLink(ctx, link);
  }

  void _flushPendingTapSoon() {
    if (_pendingTap == null || _flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) _flushPendingTap();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _flushPendingTap() {
    final m = _pendingTap;
    final at = _pendingTapAt;
    if (m == null || at == null) return;
    _pendingTap = null;
    _pendingTapAt = null;
    if (DateTime.now().difference(at) > _pendingTapTtl) return;   // trop ancienne : elle reste dans le centre de notifications
    _openFromPush(m, since: at);
  }

  /// Annonce avec image (notification construite par l'application) touchée : comptée comme ouverte et lue, puis son lien est
  /// ouvert (connexion d'abord si nécessaire ; rôle vérifié par openDeepLink).
  void _onNotificationTap(NotificationTap tap) {
    _markAnnouncementOpened(tap.announcementId);
    _markNotificationRead(tap.notificationId);
    _openLink(tap.link);
  }

  /// Notification ouverte depuis un ruban ou la barre du système : lue dans le centre de notifications (compteur à jour).
  void _markNotificationRead(int? id) {
    if (id == null || id <= 0 || !_session.isAuthenticated) return;
    try {
      unawaited(context
          .read<OfflineQueue>()
          .enqueue('PATCH', '/notifications/$id/', {'is_read': true})
          .then<void>((_) => _refreshSoon(), onError: (_) {}));
    } catch (_) {}
  }

  void _markAnnouncementOpened(int? id) {
    if (id == null || !_session.isAuthenticated) return;
    try {
      unawaited(context.read<OfflineQueue>().enqueue('POST', '/me/announcements/$id/open/'));
    } catch (_) {}
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RouteNames.home:
        // Accueil = espace utilisateur unifié (client + artisan sur un même compte).
        return MaterialPageRoute(builder: (_) => const DashboardScreen());
      case RouteNames.explore:
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
      case RouteNames.panne:
        return MaterialPageRoute(builder: (_) => const PanneScreen());

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

      case RouteNames.verifyPhone:
        final args = settings.arguments;
        return MaterialPageRoute(
          builder: (_) => OtpScreen(
            nextRoute: args is OtpArgs ? args.nextRoute : RouteNames.home,
            autoSend: args is OtpArgs && args.autoSend,
          ),
        );
      case RouteNames.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());

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
            locale: _appLocale,
            supportedLocales: _supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
            : RouteNames.home;

        return MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRouteObserver, _routeChanges],
          // Rubans de notification au-dessus de tous les écrans (feuilles et dialogues compris).
          builder: (context, child) => NoticeHost(child: child ?? const SizedBox.shrink()),
          title: 'Tratra',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: _appLocale,
          supportedLocales: _supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          initialRoute: initialRoute,
          onGenerateRoute: _generateRoute,
        );
      },
    );
  }
}
