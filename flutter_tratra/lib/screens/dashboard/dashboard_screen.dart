// lib/screens/dashboard/dashboard_screen.dart
//
// Espace utilisateur UNIFIÉ (miroir de /dashboard côté web) : un même compte peut réserver
// (client) ET proposer des services (artisan). Cinq onglets : Accueil, Explorer, Réservations,
// Messages, Plus (prestations, portefeuille, avis, notifications, profil & KYC).
import 'package:flutter/material.dart';

import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/core/route_observer.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/statuses/statuses_screen.dart';
import 'package:flutter_tratra/screens/dashboard/bookings_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_home.dart';
import 'package:flutter_tratra/screens/dashboard/messages_screen.dart';
import 'package:flutter_tratra/screens/home_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver, RouteAware {
  static const _titles = ['Mon espace', 'Explorer', 'Mes réservations', 'Messages', 'Plus'];
  int _index = 0;
  final _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DashboardController>().load();
      _applyTabRequest();
    });
    dashboardTabRequest.addListener(_applyTabRequest);
  }

  /// Onglet demandé par un raccourci d'application ou le widget d'accueil.
  void _applyTabRequest() {
    final tab = dashboardTabRequest.value;
    if (tab == null || !mounted) return;
    dashboardTabRequest.value = null;
    _go(tab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  /// Retour sur l'accueil (vérification d'identité, publication, profil…) : statuts relus auprès du serveur.
  @override
  void didPopNext() {
    if (mounted) context.read<DashboardController>().load();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    dashboardTabRequest.removeListener(_applyTabRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) context.read<DashboardController>().load();
  }

  void _go(int i) {
    setState(() {
      _index = i;
      _visited.add(i);
    });
    if (i == 0 || i == 3) context.read<DashboardController>().load(); // pastilles et accueil à jour
  }

  Widget _tab(int i) {
    switch (i) {
      case 0:
        return DashboardHome(onExplore: () => _go(1), onMessages: () => _go(3));
      case 1:
        return const HomeScreen(embedded: true);
      case 2:
        return BookingsList(onExplore: () => _go(1));
      case 3:
        return const MessagesList();
      default:
        return const _MoreTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.select<DashboardController, DashData?>((c) => c.data);
    final unreadNotifs = data?.unreadNotifications ?? 0;
    // Non lus en temps réel (WebSocket) ; à défaut, le compteur du tableau de bord.
    final live = context.select<InboxController, int>((c) => c.unread);
    final unreadMessages = live > 0 ? live : (data?.unreadMessages ?? 0);
    return Scaffold(
      backgroundColor: TtColors.canvas,
      // L'onglet Explorer porte sa propre en-tête (catalogue).
      appBar: _index == 1
          ? null
          : TratraAppBar(
              automaticallyImplyLeading: false,
              // Logo officiel + nom de la marque sur l'accueil ; logo + titre sur les autres onglets
              // (comme la barre supérieure du web).
              titleWidget: Row(mainAxisSize: MainAxisSize.min, children: [
                const TratraBrandMark(size: 38),
                const SizedBox(width: TtSpace.s3),
                if (_index == 0)
                  const TratraWordmark(size: 28)
                else
                  Flexible(
                    child: Text(_titles[_index],
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.h3)),
                  ),
              ]),
              actions: [
                IconButton(
                  tooltip: 'Statuts',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatusesScreen())),
                  icon: const Icon(Icons.motion_photos_on_outlined),
                ),
                IconButton(
                  tooltip: 'Messages',
                  onPressed: () => _go(3),
                  icon: Badge(
                    isLabelVisible: unreadMessages > 0,
                    label: Text('$unreadMessages'),
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => openNotifications(context),
                  icon: Badge(
                    isLabelVisible: unreadNotifs > 0,
                    label: Text('$unreadNotifs'),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                ),
              ],
            ),
      body: IndexedStack(
        index: _index,
        children: [for (var i = 0; i < _titles.length; i++) _visited.contains(i) ? _tab(i) : const SizedBox.shrink()],
      ),
      bottomNavigationBar: TratraBottomNav(
        currentIndex: _index,
        onTap: _go,
        items: [
          const TratraNavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: 'Accueil'),
          const TratraNavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore, label: 'Explorer'),
          const TratraNavItem(icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, label: 'Réservations'),
          TratraNavItem(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Messages', badge: unreadMessages > 0 ? unreadMessages : null),
          TratraNavItem(icon: Icons.more_horiz_rounded, label: 'Plus', badge: (data?.reviewsToWrite ?? 0) > 0 ? data!.reviewsToWrite : null),
        ],
      ),
    );
  }
}

/// Onglet « Plus » : les fonctions qui ne tiennent pas dans la barre basse, selon les capacités réelles.
class _MoreTab extends StatelessWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DashboardController>().data;
    final isProvider = data?.isProvider ?? false;
    final entries = <_Entry>[
      if (isProvider)
        _Entry(Icons.storefront_outlined, 'Mes offres et missions', 'Offres publiées, missions et disponibilité', () => openProviderHub(context))
      else
        _Entry(Icons.add_business_outlined, 'Proposer un service', 'Publiez vos prestations avec ce même compte', () => openProvide(context)),
      _Entry(Icons.description_outlined, 'Engagements', 'Contrats récurrents et de longue durée, offres et candidatures', () => openEngagements(context)),
      if (AppConstants.financialFeaturesEnabled)
        _Entry(Icons.account_balance_wallet_outlined, 'Portefeuille', isProvider ? 'Paiements, gains et retraits' : 'Vos paiements', () => openWallet(context)),
      if (isProvider) ...[
        _Entry(Icons.workspace_premium_outlined, 'Ma réputation', 'Badges, score de confiance et justificatifs', () => openReputation(context)),
        _Entry(Icons.badge_outlined, 'Mon badge Tratra ID', 'QR de vérification et badge imprimable', () => openMyBadge(context)),
      ],
      if (data?.isBusiness == true || data?.isCompany == true)
        _Entry(Icons.apartment_rounded, 'Tratra Business', 'Sites, équipements et demandes d’intervention', () => openBusiness(context)),
      _Entry(Icons.qr_code_scanner_rounded, 'Scanner un badge', 'Vérifier un professionnel ou l’artisan de votre réservation', () => openScanner(context)),
      _Entry(Icons.star_outline_rounded, 'Avis', 'À rédiger, reçus et donnés', () => openReviews(context),
          badge: data?.reviewsToWrite),
      _Entry(Icons.notifications_none_rounded, 'Notifications', 'Réservations, missions, messages', () => openNotifications(context),
          badge: data?.unreadNotifications),
      _Entry(Icons.person_outline_rounded, 'Mon compte', 'Informations personnelles et sécurité', () => openAccount(context)),
      _Entry(Icons.place_outlined, 'Mes adresses', 'Principale, secondaires et favorites', () => openAddresses(context)),
      if (isProvider) ...[
        _Entry(Icons.badge_outlined, 'Profil professionnel', 'Présentation, spécialités, zone', () => openProProfile(context)),
        _Entry(Icons.verified_user_outlined, 'Vérifier mon identité', 'Parcours guidé : pièce, photo, revue par l’équipe', () => openKyc(context)),
        _Entry(Icons.folder_open_outlined, 'Documents et justificatifs', 'Diplômes, attestations et historique des pièces', () => openDocuments(context)),
      ],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
      children: [
        for (final e in entries) ...[
          TratraCard(
            padding: TratraCard.compact,
            onTap: e.onTap,
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)),
                child: Icon(e.icon, color: TtColors.primary),
              ),
              const SizedBox(width: TtSpace.s3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: TratraTheme.style(TtType.title)),
                  Text(e.subtitle, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                ]),
              ),
              if ((e.badge ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CircleAvatar(radius: 11, backgroundColor: TtColors.accent, child: Text('${e.badge}', style: const TextStyle(color: TtColors.night, fontSize: 11, fontWeight: FontWeight.w700))),
                ),
              const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
            ]),
          ),
          const SizedBox(height: TtSpace.s2),
        ],
        const SizedBox(height: TtSpace.s3),
        TratraButton(
          label: 'Déconnexion',
          variant: TratraButtonVariant.outline,
          block: true,
          leading: const Icon(Icons.logout_rounded, color: TtColors.danger),
          onPressed: () async {
            final ok = await showTratraConfirm(context, title: 'Se déconnecter ?', confirmLabel: 'Quitter');
            if (!ok || !context.mounted) return;
            final nav = Navigator.of(context);
            await context.read<Session>().logout();
            nav.pushNamedAndRemoveUntil(RouteNames.login, (r) => false);
          },
        ),
      ],
    );
  }
}

class _Entry {
  _Entry(this.icon, this.title, this.subtitle, this.onTap, {this.badge});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? badge;
}
