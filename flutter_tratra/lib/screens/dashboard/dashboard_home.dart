// lib/screens/dashboard/dashboard_home.dart
//
// Onglet « Accueil » de l'espace unifié (miroir de frontend/src/app/dashboard/page.tsx) :
// hero personnalisé, actions rapides, indicateurs réels, prochaines interventions,
// actions à traiter, activité récente, progression du profil pro et du KYC.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/core/session.dart';
import 'package:flutter_tratra/continuity/continuity_widgets.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/onboarding/onboarding_entry.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/dashboard/announcements_screen.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/eligibility_panel.dart' show runEligibilityAction;
import 'package:flutter_tratra/screens/dashboard/pro_status.dart';
import 'package:flutter_tratra/screens/dashboard/recommended_card.dart';
import 'package:flutter_tratra/statuses/status_bar.dart';

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key, required this.onExplore, required this.onMessages});
  final VoidCallback onExplore;
  final VoidCallback onMessages;

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  bool _showMissions = false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DashboardController>();
    final data = c.data;
    if (data == null) {
      if (c.error != null) {
        // Sans réseau au démarrage, la dernière activité connue (mission, réservation, contrat) reste accessible au-dessus de l'erreur :
        // reprendre son travail ne dépend pas du tableau de bord (voir continuity/ — l'état hors ligne y est signalé comme tel).
        return Column(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, 0), child: ActivityBanner()),
            Expanded(
              child: c.sessionExpired
                  ? TratraEmptyState(
                      icon: Icons.lock_clock_outlined,
                      title: 'Session expirée',
                      description: c.error,
                      actions: [
                        TratraButton(
                          key: const ValueKey('relogin'),
                          label: 'Se reconnecter',
                          leading: const Icon(Icons.login_rounded),
                          onPressed: () async {
                            final nav = Navigator.of(context);
                            await context.read<Session>().logout();
                            nav.pushNamedAndRemoveUntil(RouteNames.login, (r) => false);
                          },
                        ),
                      ],
                    )
                  : TratraEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Tableau de bord indisponible',
                      description: c.error,
                      actions: [TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: c.load)],
                    ),
            ),
          ],
        );
      }
      return const TratraSkeletonList(count: 4);
    }

    final provider = data.provider;
    final summary = data.upcoming.isNotEmpty
        ? '${data.upcoming.length} intervention${data.upcoming.length > 1 ? 's' : ''} à venir.'
        : provider != null
            ? 'Gérez vos prestations et trouvez aussi un artisan pour vos propres besoins.'
            : 'Trouvez un artisan vérifié près de chez vous, ou proposez vos propres services.';

    final kpis = <Widget>[
      if (data.bookingsTotal > 0 || provider == null)
        DashKpi(
          icon: Icons.event_available_outlined,
          label: 'Réservations en cours',
          value: '${data.bookingsActive}',
          hint: data.bookingsTotal > 0
              ? '${data.bookingsCompleted} terminée${data.bookingsCompleted > 1 ? 's' : ''}'
              : 'Aucune pour le moment',
          onTap: () => openBookings(context),
        ),
      if (provider != null) ...[
        DashKpi(
          icon: Icons.handyman_outlined,
          tone: TratraTone.accent,
          label: 'Missions à traiter',
          value: '${provider.pending}',
          hint: provider.pending > 0 ? 'En attente de votre réponse' : 'Aucune demande en attente',
          onTap: () => openProviderHub(context),
        ),
        DashKpi(
          icon: Icons.work_outline_rounded,
          label: 'Missions à venir',
          value: '${provider.confirmed + provider.inProgress}',
          hint: '${provider.completed} terminée${provider.completed > 1 ? 's' : ''}',
          onTap: () => openProviderHub(context),
        ),
        if (AppConstants.financialFeaturesEnabled)
          DashKpi(
            icon: Icons.account_balance_wallet_outlined,
            tone: TratraTone.night,
            label: 'Gains disponibles',
            value: fcfaOrZero(provider.earnings),
            onTap: () => openWallet(context),
          ),
      ] else ...[
        DashKpi(
          icon: Icons.check_circle_outline_rounded,
          label: 'Prestations terminées',
          value: '${data.bookingsCompleted}',
          onTap: () => openBookings(context),
        ),
        DashKpi(
          icon: Icons.star_outline_rounded,
          tone: TratraTone.accent,
          label: 'Avis à rédiger',
          value: '${data.reviewsToWrite}',
          hint: data.reviewsToWrite > 0 ? 'Partagez votre expérience' : 'Rien à noter',
          onTap: () => openReviews(context),
        ),
      ],
    ];

    final recent = _showMissions && provider != null ? provider.recentMissions : data.recentBookings;

    return RefreshIndicator(
      color: TtColors.primary,
      onRefresh: c.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
        children: [
          // Statuts : « Mon statut » d'abord, puis les contacts Tratra (non lus avant les consultés)
          const StatusBar(horizontalPadding: 0),
          const SizedBox(height: TtSpace.s3),
          const ActivityBanner(),
          _Hero(
            greeting: data.greeting,
            verified: provider != null && proHomeState(provider).verified,
            summary: summary,
            isProvider: provider != null,
            onExplore: widget.onExplore,
            onSearch: () => Navigator.pushNamed(context, RouteNames.allServices),
            onProvide: () => provider != null ? openProviderHub(context) : openProvide(context),
          ),
          const SizedBox(height: TtSpace.s4),
          // Inscription professionnelle commencée et pas encore publiée : progression et UN bouton « Continuer ».
          const BeginnerProgressCard(),
          const AnnouncementsBanner(),
          const RecommendedCard(),
          for (final k in kpis) ...[k, const SizedBox(height: TtSpace.s3)],
          if (data.actions.isNotEmpty) ...[
            const TratraSectionHeader(title: 'À traiter', subtitle: 'Ce qui demande votre attention.', padding: EdgeInsets.fromLTRB(0, 20, 0, 12)),
            for (final a in data.actions) ...[
              _ActionTile(action: a, onTap: () => openTarget(context, a.target, onMessages: widget.onMessages)),
              const SizedBox(height: TtSpace.s2),
            ],
          ],
          TratraSectionHeader(
            title: 'Prochaines interventions',
            subtitle: 'Vos réservations et missions à venir, par date.',
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
          ),
          if (data.upcoming.isEmpty)
            const TratraCard(
              variant: TratraCardVariant.flat,
              child: _Hint(icon: Icons.event_busy_outlined, text: 'Aucune intervention prévue pour le moment.'),
            )
          else
            for (final i in data.upcoming) ...[
              DashItemTile(item: i, onTap: () => openItem(context, i)),
              const SizedBox(height: TtSpace.s2),
            ],
          TratraSectionHeader(
            title: 'Activité récente',
            actionLabel: 'Tout voir',
            onAction: () => _showMissions && provider != null ? openProviderHub(context) : openBookings(context),
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
          ),
          if (provider != null)
            Padding(
              padding: const EdgeInsets.only(bottom: TtSpace.s3),
              child: Wrap(spacing: TtSpace.s2, children: [
                TratraChip(label: 'Réservations', selected: !_showMissions, onTap: () => setState(() => _showMissions = false)),
                TratraChip(label: 'Missions', selected: _showMissions, onTap: () => setState(() => _showMissions = true)),
              ]),
            ),
          if (recent.isEmpty)
            TratraCard(
              variant: TratraCardVariant.flat,
              child: _Hint(
                icon: Icons.inbox_outlined,
                text: _showMissions ? 'Aucune mission pour le moment.' : 'Vos réservations apparaîtront ici.',
              ),
            )
          else
            for (final i in recent) ...[
              DashItemTile(item: i, onTap: () => openItem(context, i)),
              const SizedBox(height: TtSpace.s2),
            ],
          const SizedBox(height: TtSpace.s4),
          _ProfileCard(data: data),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.greeting, required this.summary, required this.isProvider, required this.onExplore, required this.onSearch, required this.onProvide, this.verified = false});
  final String greeting;

  /// Publication autorisée par le serveur : badge discret « ✓ Vérifié » près du nom.
  final bool verified;
  final String summary;
  final bool isProvider;
  final VoidCallback onExplore;
  final VoidCallback onSearch;
  final VoidCallback onProvide;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      variant: TratraCardVariant.night,
      padding: const EdgeInsets.all(TtSpace.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MON ESPACE', style: TratraTheme.style(TtType.eyebrow, color: TtColors.accent)),
          const SizedBox(height: TtSpace.s2),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Bonjour, '),
              TextSpan(text: greeting, style: const TextStyle(color: TtColors.accent)),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TratraTheme.style(TtType.h1, color: Colors.white),
          ),
          if (verified) ...[
            const SizedBox(height: TtSpace.s2),
            Semantics(
              label: 'Profil professionnel vérifié par Tratra',
              excludeSemantics: true,
              child: Container(
                key: const ValueKey('hero-verified'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: TtColors.success.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(TtRadius.pill)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_rounded, size: 16, color: TtColors.successSoft),
                  const SizedBox(width: 4),
                  Text('Vérifié', style: TratraTheme.style(TtType.caption, color: Colors.white).copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ],
          const SizedBox(height: TtSpace.s2),
          Text(summary, style: TratraTheme.style(TtType.bodySm, color: Colors.white70)),
          const SizedBox(height: TtSpace.s4),
          // La recherche réelle (texte, filtres, tri) vit dans le catalogue : le champ l'ouvre.
          TratraInput(
            hint: 'Plomberie, électricité, ménage…',
            leadingIcon: Icons.search_rounded,
            readOnly: true,
            onTap: onSearch,
          ),
          const SizedBox(height: TtSpace.s3),
          Wrap(spacing: TtSpace.s3, runSpacing: TtSpace.s3, children: [
            TratraButton(label: 'Trouver un artisan', leading: const Icon(Icons.explore_outlined, size: 18), onPressed: onExplore),
            TratraButton(
              label: isProvider ? 'Gérer mes offres' : 'Proposer mes services',
              variant: TratraButtonVariant.accent,
              leading: const Icon(Icons.handyman_outlined, size: 18),
              onPressed: onProvide,
            ),
          ]),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: TtColors.fog),
        const SizedBox(width: TtSpace.s3),
        Expanded(child: Text(text, style: TratraTheme.style(TtType.bodySm, color: TtColors.ash))),
      ]);
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});
  final DashAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (action.severity) {
      'danger' => (TtColors.dangerSoft, TtColors.danger, Icons.error_outline_rounded),
      'warning' => (TtColors.warningSoft, TtColors.warning, Icons.warning_amber_rounded),
      _ => (TtColors.infoSoft, TtColors.info, Icons.info_outline_rounded),
    };
    return TratraCard(
      padding: TratraCard.compact,
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(TtRadius.control)),
          child: Icon(icon, color: fg, size: 20),
        ),
        const SizedBox(width: TtSpace.s3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(action.title, style: TratraTheme.style(TtType.title)),
            if (action.description.isNotEmpty)
              Text(action.description, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
      ]),
    );
  }
}

/// Profil pro + KYC : progression réelle si le compte a un profil artisan, invitation sinon.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.data});
  final DashData data;

  @override
  Widget build(BuildContext context) {
    final p = data.provider;
    if (p == null) {
      return TratraCard(
        variant: TratraCardVariant.soft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Proposez vos services', style: TratraTheme.style(TtType.h3)),
          const SizedBox(height: TtSpace.s2),
          Text(
            'Créez votre profil professionnel avec ce même compte, faites vérifier votre identité puis publiez vos prestations.',
            style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
          ),
          const SizedBox(height: TtSpace.s4),
          TratraButton(label: 'Proposer un service', block: true, onPressed: () => openProvide(context)),
        ]),
      );
    }
    final st = proHomeState(p);
    void act() {
      if (st.actionCode == null) return;
      runEligibilityAction(context, DashActionRef({'code': st.actionCode, 'label': st.actionLabel ?? ''}),
          onChanged: () => context.read<DashboardController>().load());
    }

    switch (st.kind) {
      // Vérifié : plus de carte de progression (badge « ✓ Vérifié » près du nom ; le détail reste dans Profil → Mon profil
      // professionnel → Vérification et réputation).
      case ProHomeKind.verified:
        return const SizedBox.shrink(key: ValueKey('pro-card-hidden'));
      case ProHomeKind.firstOffer:
        return TratraCard(
          key: const ValueKey('pro-first-offer'),
          variant: TratraCardVariant.soft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(st.title, style: TratraTheme.style(TtType.h3)),
            const SizedBox(height: TtSpace.s2),
            Text(st.message, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            const SizedBox(height: TtSpace.s4),
            TratraButton(label: st.actionLabel!, block: true, leading: const Icon(Icons.add_rounded, size: 18), onPressed: act),
          ]),
        );
      // Pièce en revue, validation finale, autre blocage : un statut compact ; un bouton seulement s'il y a vraiment quelque chose à faire.
      case ProHomeKind.kycPending || ProHomeKind.approvalPending || ProHomeKind.blocked:
        return TratraCard(
          key: ValueKey('pro-status-${st.kind.name}'),
          variant: TratraCardVariant.flat,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(st.kind == ProHomeKind.blocked ? Icons.info_outline_rounded : Icons.hourglass_top_rounded,
                color: st.kind == ProHomeKind.blocked ? TtColors.warning : TtColors.accentDark),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.title, style: TratraTheme.style(TtType.title)),
                if (st.message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(st.message, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                ],
                if (st.actionCode != null) ...[
                  const SizedBox(height: TtSpace.s2),
                  TratraButton(label: st.actionLabel ?? 'Voir', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: act),
                ],
              ]),
            ),
          ]),
        );
      case ProHomeKind.kycRejected || ProHomeKind.progress:
        break;
    }
    // Il reste quelque chose à faire soi-même : progression et « Continuer » (ou la correction demandée si la pièce a été refusée).
    final missing = p.checklist.where((i) => !i.done).toList();
    return TratraCard(
      key: const ValueKey('pro-progress'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Profil professionnel', style: TratraTheme.style(TtType.h3))),
          Text('${p.done}/${p.total}', style: TratraTheme.style(TtType.title, color: TtColors.primaryDark)),
        ]),
        const SizedBox(height: TtSpace.s3),
        ClipRRect(
          borderRadius: BorderRadius.circular(TtRadius.pill),
          child: LinearProgressIndicator(
            value: p.total == 0 ? 0 : p.done / p.total,
            minHeight: 8,
            backgroundColor: TtColors.lineSoft,
            color: TtColors.primary,
          ),
        ),
        if (st.kind == ProHomeKind.kycRejected) ...[
          const SizedBox(height: TtSpace.s3),
          TratraAlert(key: const ValueKey('pro-kyc-rejected'), tone: TratraAlertTone.danger, title: st.title, message: st.message),
        ] else if (missing.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s3),
          Text('Encore à faire : ${missing.map((i) => i.label.toLowerCase()).join(', ')}.',
              style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ],
        const SizedBox(height: TtSpace.s4),
        TratraButton(key: const ValueKey('pro-continue'), label: st.actionLabel ?? 'Continuer', block: true, onPressed: act),
      ]),
    );
  }
}
