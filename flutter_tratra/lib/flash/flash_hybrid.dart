// lib/flash/flash_hybrid.dart
//
// Hybrid Matching (application) : après le métier, deux façons d'obtenir un professionnel, sur UNE seule commande :
//  * « Trouvez-moi un professionnel » (AUTO_MATCH) : Tratra propose la demande aux pros vérifiés et disponibles ;
//  * « Choisir mon professionnel » (DIRECT_SELECTION) : le client choisit sur profils, avis et badges (favoris d'abord).
// Le serveur conseille un mode et se souvient du dernier choix ; on peut basculer ensuite, avec confirmation, sans rien ressaisir.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_client.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

const kAuto = 'auto';
const kDirect = 'direct';

/// Professionnel choisi (carte publique renvoyée par l'API) et, éventuellement, l'offre retenue.
class ChosenPro {
  const ChosenPro(this.card, [this.offer]);
  final Map<String, dynamic> card;
  final Map<String, dynamic>? offer;
  int get id => int.tryParse('${card['id']}') ?? 0;
  String get name => '${card['name'] ?? 'Professionnel'}';
}

/// Ouvre la commande (formulaire commun aux deux modes).
Future<void> openOrder(BuildContext context, {Category? category, String? matching, ChosenPro? pro}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FlashRequestFormScreen(initialCategory: category, initialMatching: matching, initialPro: pro)));

/// Les deux entrées après le choix d'un métier ou d'une prestation.
class ModeChoiceButtons extends StatelessWidget {
  const ModeChoiceButtons({super.key, required this.category, this.onBeforeOpen});
  final Category category;
  final VoidCallback? onBeforeOpen;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TratraButton(
          key: ValueKey('mode-auto-${category.id}'),
          label: 'Trouvez-moi un professionnel',
          leading: const Icon(Icons.bolt_rounded, size: 18),
          block: true,
          onPressed: () {
            onBeforeOpen?.call();
            openOrder(context, category: category, matching: kAuto);
          },
        ),
        const SizedBox(height: TtSpace.s2),
        TratraButton(
          key: ValueKey('mode-direct-${category.id}'),
          label: 'Choisir mon professionnel',
          leading: const Icon(Icons.person_search_rounded, size: 18),
          variant: TratraButtonVariant.outline,
          block: true,
          onPressed: () {
            onBeforeOpen?.call();
            openOrder(context, category: category, matching: kDirect);
          },
        ),
      ]);
}

/// Sélecteur de mode dans le formulaire : conseil du serveur (motif) et choix du client, toujours modifiable.
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.value, required this.onChanged, this.suggestion});
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, dynamic>? suggestion;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final suggested = s?['suggested'];
    Widget option(String v, String label, String hint, IconData icon) {
      final selected = value == v;
      return Expanded(
        child: TratraCard(
          key: ValueKey('mode-option-$v'),
          variant: selected ? TratraCardVariant.soft : TratraCardVariant.flat,
          padding: const EdgeInsets.all(TtSpace.s3),
          onTap: () => onChanged(v),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: selected ? TtColors.primary : TtColors.ash),
              const Spacer(),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? TtColors.primary : TtColors.fog, size: 20),
            ]),
            const SizedBox(height: TtSpace.s2),
            Text(label, style: TratraTheme.style(TtType.title).copyWith(fontSize: 14)),
            const SizedBox(height: 2),
            Text(hint, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            if (suggested == v) ...[
              const SizedBox(height: TtSpace.s2),
              const TratraBadge('Conseillé', tone: TratraTone.accent),
            ],
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        option(kAuto, 'Trouvez-moi un professionnel', 'Le premier pro disponible qui accepte', Icons.bolt_rounded),
        const SizedBox(width: TtSpace.s2),
        option(kDirect, 'Choisir mon professionnel', 'Profils, avis et badges', Icons.person_search_rounded),
      ]),
      if (s != null && '${s['reason'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: TtSpace.s2),
        Text('${s['reason']}', key: const ValueKey('mode-reason'), style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
      ],
      if (s != null && '${s['note'] ?? ''}'.isNotEmpty)
        Text('${s['note']}', style: TratraTheme.style(TtType.caption, color: TtColors.warningInk)),
    ]);
  }
}

/// Carte d'un professionnel (liste, favoris, commande) : nom, badges, score, note, distance, prix.
class ProCard extends StatelessWidget {
  const ProCard({super.key, required this.card, this.onChoose, this.onFavorite, this.chooseLabel = 'Choisir'});
  final Map<String, dynamic> card;
  final VoidCallback? onChoose;
  final VoidCallback? onFavorite;
  final String chooseLabel;

  @override
  Widget build(BuildContext context) {
    final badges = ((card['badges'] as List?) ?? const []).map((e) => '$e').toList();
    final rating = card['rating'];
    final reviews = int.tryParse('${card['reviews'] ?? 0}') ?? 0;
    final distance = double.tryParse('${card['distance_km'] ?? ''}');
    final price = card['price_from'];
    final why = ((card['why'] as List?) ?? const []).whereType<Map>().toList();
    return TratraCard(
      key: ValueKey('pro-${card['id']}'),
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TratraAvatar(name: '${card['name']}', photoUrl: card['photo'] as String?, size: 48),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${card['name']}', style: TratraTheme.style(TtType.title)),
              Text([
                if (rating is num) '★ ${rating.toStringAsFixed(1).replaceAll('.', ',')} ($reviews avis)' else if (reviews == 0) 'Nouveau sur Tratra' else '$reviews avis',
                if (distance != null) '${distance.toStringAsFixed(1).replaceAll('.', ',')} km',
                if (card['trust_score'] != null) 'Trust ${card['trust_score']}/100',
              ].join(' · '), style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            ]),
          ),
          if (onFavorite != null)
            IconButton(
              key: ValueKey('favorite-${card['id']}'),
              tooltip: card['favorite'] == true ? 'Retirer des favoris' : 'Ajouter aux favoris',
              icon: Icon(card['favorite'] == true ? Icons.favorite : Icons.favorite_border, color: TtColors.danger),
              onPressed: onFavorite,
            ),
        ]),
        if (badges.isNotEmpty) ...[
          const SizedBox(height: TtSpace.s2),
          TratraTrustBadges(badges),
        ],
        if (why.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Pourquoi ce professionnel ?', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              children: [
                for (final w in why)
                  Align(alignment: Alignment.centerLeft, child: Text('${w['label']} : ${w['detail']}', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
              ],
            ),
          ),
        if (onChoose != null) ...[
          const SizedBox(height: TtSpace.s2),
          Row(children: [
            Expanded(child: Text(price is num ? 'À partir de ${_money(price.toInt())}' : 'Prix sur devis ou à proposer',
                style: TratraTheme.style(TtType.bodySm, color: TtColors.primaryDark))),
            TratraButton(key: ValueKey('choose-${card['id']}'), label: chooseLabel, size: TratraButtonSize.sm, onPressed: onChoose),
          ]),
        ],
      ]),
    );
  }
}

String _money(int amount) {
  final s = amount.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b FCFA';
}

/// Choisir mon professionnel : professionnels réellement disponibles pour ce métier et ce créneau (aucun profil inventé).
class FlashProsScreen extends StatefulWidget {
  const FlashProsScreen({super.key, required this.categoryId, required this.categoryName, this.when, this.lat, this.lng, this.commune, this.excludeIds = const {}});
  final int categoryId;
  final String categoryName;
  final DateTime? when;
  final double? lat;
  final double? lng;
  final String? commune;
  final Set<int> excludeIds;

  @override
  State<FlashProsScreen> createState() => _FlashProsScreenState();
}

class _FlashProsScreenState extends State<FlashProsScreen> {
  String _sort = 'recommended';
  bool _favoritesOnly = false;
  bool _topRated = false;
  String? _badge;
  late Future<List<Map<String, dynamic>>> _future = _load();

  FlashApi get _api => context.read<FlashController>().api;

  Future<List<Map<String, dynamic>>> _load() => context.read<FlashController>().api.pros(widget.categoryId,
      when: widget.when, lat: widget.lat, lng: widget.lng, commune: widget.commune, sort: _sort,
      minRating: _topRated ? 4.0 : null, badge: _badge, favorites: _favoritesOnly);

  void _reload() => setState(() => _future = _load());

  Future<void> _toggleFavorite(Map<String, dynamic> card) async {
    final id = int.tryParse('${card['id']}') ?? 0;
    try {
      card['favorite'] == true ? await _api.removeFavorite(id) : await _api.addFavorite(id);
      _reload();
    } on FlashApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _choose(Map<String, dynamic> card) async {
    final offers = ((card['offers'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    Map<String, dynamic>? offer;
    if (offers.length > 1) {
      offer = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Quelle prestation ?', style: TratraTheme.style(TtType.h3)),
            for (final o in offers)
              ListTile(
                key: ValueKey('offer-${o['id']}'),
                title: Text('${o['title']}'),
                trailing: Text(o['price'] is num ? _money((o['price'] as num).toInt()) : 'Sur devis'),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ]),
        ),
      );
      if (offer == null) return;
    } else if (offers.length == 1) {
      offer = offers.first;
    }
    if (mounted) Navigator.of(context).pop(ChosenPro(card, offer));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Choisir · ${widget.categoryName}')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s2),
          child: Row(children: [
            for (final (v, l) in const [('recommended', 'Recommandés'), ('distance', 'Plus proches'), ('rating', 'Mieux notés'), ('price', 'Prix')]) ...[
              TratraChip(key: ValueKey('sort-$v'), label: l, selected: _sort == v, onTap: () {
                _sort = v;
                _reload();
              }),
              const SizedBox(width: TtSpace.s2),
            ],
            TratraChip(key: const ValueKey('filter-favorites'), label: 'Favoris', icon: Icons.favorite_border, selected: _favoritesOnly, onTap: () {
              _favoritesOnly = !_favoritesOnly;
              _reload();
            }),
            const SizedBox(width: TtSpace.s2),
            TratraChip(label: '4★ et plus', selected: _topRated, onTap: () {
              _topRated = !_topRated;
              _reload();
            }),
            const SizedBox(width: TtSpace.s2),
            TratraChip(label: 'Expert', selected: _badge == 'EXPERT', onTap: () {
              _badge = _badge == 'EXPERT' ? null : 'EXPERT';
              _reload();
            }),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              final rows = (snap.data ?? const []).where((c) => !widget.excludeIds.contains(int.tryParse('${c['id']}'))).toList();
              if (rows.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(TtSpace.s6),
                    child: TratraEmptyState(icon: Icons.person_search_rounded, title: 'Aucun professionnel disponible',
                        description: 'Personne n’est libre pour ce métier et ce créneau. Changez l’horaire ou laissez Tratra trouver un professionnel.'),
                  ),
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
                itemBuilder: (_, i) => ProCard(card: rows[i], onChoose: () => _choose(rows[i]), onFavorite: () => _toggleFavorite(rows[i])),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Confirmation d'un changement de mode : la proposition en cours est retirée, la demande est conservée telle quelle.
Future<bool> confirmSwitch(BuildContext context, {required String to, String? currentPro, String? newPro}) async {
  final text = to == kAuto
      ? '${currentPro != null ? 'La proposition à $currentPro sera retirée. ' : ''}Tratra proposera votre demande aux professionnels disponibles. '
          'Adresse, date et prix sont conservés.'
      : '${newPro ?? 'Ce professionnel'} recevra votre demande. Les propositions en cours seront retirées ; les devis déjà reçus restent valables.';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(to == kAuto ? 'Trouvez-moi un professionnel ?' : 'Choisir ${newPro ?? 'ce professionnel'} ?'),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(key: const ValueKey('confirm-switch'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
      ],
    ),
  );
  return ok == true;
}

/// Mes professionnels favoris : réservation rapide (« Choisir mon professionnel » prérempli).
class FlashFavoritesScreen extends StatefulWidget {
  const FlashFavoritesScreen({super.key});
  @override
  State<FlashFavoritesScreen> createState() => _FlashFavoritesScreenState();
}

class _FlashFavoritesScreenState extends State<FlashFavoritesScreen> {
  late Future<List<Map<String, dynamic>>> _future = context.read<FlashController>().api.favorites();

  void _reload() => setState(() => _future = context.read<FlashController>().api.favorites());

  Future<void> _book(Map<String, dynamic> card) async {
    final offers = ((card['offers'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (offers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce professionnel n’a aucune offre active pour le moment.')));
      return;
    }
    final offer = offers.length == 1
        ? offers.first
        : await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final o in offers)
                  ListTile(title: Text('${o['title']}'), trailing: Text(o['price'] is num ? _money((o['price'] as num).toInt()) : 'Sur devis'),
                      onTap: () => Navigator.pop(ctx, o)),
              ]),
            ),
          );
    if (offer == null || !mounted) return;
    final catalog = await CatalogRepository.shared(context.read<BaseApi>()).load();
    final category = catalog.items.where((c) => c.id == '${offer['category']}').firstOrNull;
    if (!mounted) return;
    await openOrder(context, category: category, matching: kDirect, pro: ChosenPro(card, offer));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes professionnels favoris')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const Center(
              child: TratraEmptyState(icon: Icons.favorite_border, title: 'Aucun favori',
                  description: 'Touchez le cœur d’un professionnel pour le retrouver ici et le réserver en deux gestes.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(TtSpace.s4),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: TtSpace.s2),
            itemBuilder: (_, i) {
              final card = rows[i];
              return ProCard(
                card: card,
                chooseLabel: 'Réserver',
                onChoose: card['bookable'] == true ? () => _book(card) : null,
                onFavorite: () async {
                  await context.read<FlashController>().api.removeFavorite(int.tryParse('${card['id']}') ?? 0);
                  _reload();
                },
              );
            },
          );
        },
      ),
    );
  }
}
