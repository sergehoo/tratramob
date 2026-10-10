// lib/screens/dashboard/announcements_screen.dart
//
// Annonces de Tratra (GET /me/announcements/) : écran dédié et bandeau d'accueil.
// Le serveur décide de la visibilité (audience, expiration, consentement marketing) ; l'application n'affiche que ce
// qu'il renvoie, signale « vue » / « ouverte » / « écartée » (statistiques agrégées côté serveur, un seul horodatage par
// événement) et n'exécute que des actions revérifiées (https ou écran connu).
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_tratra/core/announcement_action.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';

/// Appels « vue / ouverte / écartée » : jamais bloquants ni bruyants (une statistique manquée ne gêne pas l'utilisateur).
Future<void> _signal(DashboardApi api, Object id, String event) async {
  try {
    await api.post('/me/announcements/$id/$event/', {});
  } catch (_) {}
}

Future<void> _runAction(BuildContext context, DashboardApi api, Map<String, dynamic> a) async {
  final action = parseAnnouncementAction((a['action'] as Map?)?.cast<String, dynamic>());
  if (action == null) return;
  unawaited(_signal(api, a['id'] as Object, 'open'));
  switch (action) {
    case OpenExternalLink(:final uri):
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) showMessage(context, 'Impossible d’ouvrir ce lien.', error: true);
    case OpenAppScreen(:final link):
      await openDeepLink(context, link);
  }
}

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.highlightId});

  /// Annonce touchée depuis une notification : comptée comme ouverte et mise en tête.
  final int? highlightId;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final Set<Object> _seen = {};
  final Set<Object> _dismissed = {};
  bool _openedHighlight = false;

  void _onSeen(Object id) {
    if (_seen.add(id)) unawaited(_signal(_api, id, 'seen'));
  }

  Future<void> _dismiss(Object id) async {
    try {
      await _api.post('/me/announcements/$id/dismiss/', {});
      if (mounted) setState(() => _dismissed.add(id));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Impossible de masquer cette annonce.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashPage(
      title: 'Annonces',
      body: ApiView<List<Map<String, dynamic>>>(
        key: const ValueKey('announcements'),
        errorTitle: 'Annonces indisponibles',
        load: () => _api.getList('/me/announcements/'),
        builder: (context, all, reload) {
          final items = all.where((a) => !_dismissed.contains(a['id'])).toList();
          final focus = widget.highlightId;
          if (focus != null) {
            items.sort((a, b) => (b['id'] == focus ? 1 : 0) - (a['id'] == focus ? 1 : 0));
            if (!_openedHighlight && items.any((a) => a['id'] == focus)) {
              _openedHighlight = true;
              unawaited(_signal(_api, focus, 'open')); // la notification touchée compte comme une ouverture
            }
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
              children: [
                if (items.isEmpty)
                  const SizedBox(
                    height: 360,
                    child: TratraEmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'Aucune annonce',
                      description: 'Les informations importantes de Tratra et, si vous l’avez accepté, ses offres apparaîtront ici.',
                    ),
                  ),
                for (final a in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TtSpace.s3),
                    child: AnnouncementCard(
                      key: ValueKey('announcement-${a['id']}'),
                      announcement: a,
                      highlighted: a['id'] == focus,
                      onSeen: () => _onSeen(a['id'] as Object),
                      onDismiss: () => _dismiss(a['id'] as Object),
                      onAction: () => _runAction(context, _api, a),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class AnnouncementCard extends StatefulWidget {
  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onSeen,
    required this.onDismiss,
    required this.onAction,
    this.highlighted = false,
  });

  final Map<String, dynamic> announcement;
  final bool highlighted;
  final VoidCallback onSeen;
  final VoidCallback onDismiss;
  final VoidCallback onAction;

  @override
  State<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<AnnouncementCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSeen()); // affichée = vue
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final promo = a['kind'] == 'promotion';
    final image = '${a['image'] ?? ''}';
    final date = DateTime.tryParse('${a['delivered_at'] ?? ''}');
    final action = parseAnnouncementAction((a['action'] as Map?)?.cast<String, dynamic>());
    return TratraCard(
      variant: widget.highlighted ? TratraCardVariant.soft : TratraCardVariant.standard,
      padding: EdgeInsets.zero,
      semanticLabel: '${promo ? 'Offre' : 'Information'} : ${a['title']}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (image.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(TtRadius.card)),
            child: Image.network(
              image,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(), // image indisponible : le texte suffit
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(TtSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: promo ? TtColors.accent.withValues(alpha: 0.25) : TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)),
                child: Text(promo ? 'Offre' : 'Information', style: TratraTheme.style(TtType.caption, color: TtColors.ink).copyWith(fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (date != null) Text(formatWhen(date), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            ]),
            const SizedBox(height: TtSpace.s2),
            Text('${a['title']}', style: TratraTheme.style(TtType.h3)),
            const SizedBox(height: TtSpace.s1),
            Text('${a['body']}', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            const SizedBox(height: TtSpace.s3),
            Row(children: [
              if (action != null) TratraButton(label: action.label, size: TratraButtonSize.sm, onPressed: widget.onAction),
              const Spacer(),
              TextButton(onPressed: widget.onDismiss, child: const Text('Masquer')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Bandeau de l'accueil : la première annonce active. Rien n'est affiché sans annonce ni en cas d'erreur réseau
/// (l'accueil ne dépend pas des annonces) ; « Toutes les annonces » ouvre l'écran dédié.
class AnnouncementsBanner extends StatefulWidget {
  const AnnouncementsBanner({super.key});
  @override
  State<AnnouncementsBanner> createState() => _AnnouncementsBannerState();
}

class _AnnouncementsBannerState extends State<AnnouncementsBanner> {
  late final DashboardApi _api = context.read<DashboardApi>();
  Object? _lastDashboard;
  List<Map<String, dynamic>> _items = const [];
  Object? _shown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = context.watch<DashboardController>().data;
    if (!identical(data, _lastDashboard)) {
      _lastDashboard = data;
      _load(); // l'accueil vient d'être (re)chargé : les annonces aussi
    }
  }

  Future<void> _load() async {
    try {
      final list = await _api.getList('/me/announcements/');
      if (mounted) setState(() => _items = list);
    } catch (_) {
      // non bloquant : le bandeau reste simplement absent
    }
  }

  Future<void> _dismiss(Object id) async {
    try {
      await _api.post('/me/announcements/$id/dismiss/', {});
      if (mounted) setState(() => _items = _items.where((a) => a['id'] != id).toList());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Impossible de masquer cette annonce.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final a = _items.first;
    final id = a['id'] as Object;
    if (_shown != id) {
      _shown = id;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_signal(_api, id, 'seen')));
    }
    final action = parseAnnouncementAction((a['action'] as Map?)?.cast<String, dynamic>());
    return Padding(
      padding: const EdgeInsets.only(bottom: TtSpace.s4),
      child: TratraCard(
        variant: TratraCardVariant.soft,
        padding: TratraCard.compact,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.campaign_outlined, color: TtColors.primary),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['title']}', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${a['body']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              ]),
            ),
            IconButton(tooltip: 'Masquer l’annonce', icon: const Icon(Icons.close_rounded), onPressed: () => _dismiss(id)),
          ]),
          Wrap(spacing: TtSpace.s2, children: [
            if (action != null) TextButton(onPressed: () => _runAction(context, _api, a), child: Text(action.label)),
            TextButton(onPressed: () => pushPage(context, const AnnouncementsScreen()), child: Text(_items.length > 1 ? 'Toutes les annonces (${_items.length})' : 'Voir l’annonce')),
          ]),
        ]),
      ),
    );
  }
}
