// lib/flash/flash_client.dart
//
// Côté client : « Trouver un pro maintenant » (Tratra Flash). Le client décrit son besoin (métier, adresse, quand, prix ferme ou
// devis) ; Tratra le propose par vagues aux professionnels vérifiés et disponibles. Le suivi affiche la progression réelle (contactés,
// en attente, refus, sans réponse), les devis à choisir, puis le professionnel retenu et la réservation créée.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/flash/flash_controller.dart';
import 'package:flutter_tratra/flash/flash_hybrid.dart';
import 'package:flutter_tratra/flash/flash_search_screen.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/screens/dashboard/catalog_pickers.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';
import 'package:flutter_tratra/widgets/address_autocomplete.dart';

export 'package:flutter_tratra/flash/flash_search_screen.dart' show FlashRequestScreen, FlashSearchMap;

String _key(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

/// Carte d'entrée sur l'accueil, précédée de la recherche en cours s'il y en a une : après une fermeture de l'application, le client
/// reprend sa demande d'un geste (jamais de doublon : la demande existante est rouverte, pas recréée).
class FlashRequestEntry extends StatefulWidget {
  const FlashRequestEntry({super.key});
  @override
  State<FlashRequestEntry> createState() => _FlashRequestEntryState();
}

class _FlashRequestEntryState extends State<FlashRequestEntry> {
  Map<String, dynamic>? _open;

  @override
  void initState() {
    super.initState();
    unawaited(_findOpen());
  }

  Future<void> _findOpen() async {
    try {
      final rows = await context.read<FlashController>().api.requests();
      final open = rows.where((r) => const {'searching', 'quoting', 'awaiting'}.contains(r['status'])).toList();
      if (mounted) setState(() => _open = open.isEmpty ? null : open.first);
    } catch (_) {
      // hors ligne : la carte de reprise n'apparaît simplement pas
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open == null) return const _FlashEntryCard();
    final id = int.tryParse('${open['id']}');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TratraCard(
        key: const ValueKey('flash-resume'),
        variant: TratraCardVariant.soft,
        padding: TratraCard.compact,
        onTap: id == null
            ? null
            : () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FlashRequestScreen(requestId: id)));
                if (mounted) unawaited(_findOpen());
              },
        child: Row(children: [
          const Icon(Icons.radar_rounded, color: TtColors.primary),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${(open['category'] as Map?)?['name'] ?? 'Votre demande'} — ${open['status_label'] ?? 'en cours'}',
                  style: TratraTheme.style(TtType.title)),
              Text('Reprendre le suivi de votre demande en cours', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ]),
      ),
      const SizedBox(height: TtSpace.s2),
      const _FlashEntryCard(),
    ]);
  }
}

class _FlashEntryCard extends StatelessWidget {
  const _FlashEntryCard();
  @override
  Widget build(BuildContext context) => TratraCard(
        key: const ValueKey('flash-entry'),
        padding: TratraCard.compact,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FlashRequestFormScreen())),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: TtColors.accent, borderRadius: BorderRadius.circular(TtRadius.control)),
            child: const Icon(Icons.bolt_rounded, color: TtColors.night),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Trouver un professionnel', style: TratraTheme.style(TtType.title)),
              Text('Laissez Tratra trouver un pro vérifié et disponible, ou choisissez-le vous-même sur ses avis et badges.',
                  style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ]),
      );
}

/// Accès aux professionnels favoris (réservation rapide).
class FlashFavoritesEntry extends StatelessWidget {
  const FlashFavoritesEntry({super.key});
  @override
  Widget build(BuildContext context) => TratraCard(
        key: const ValueKey('favorites-entry'),
        variant: TratraCardVariant.flat,
        padding: TratraCard.compact,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FlashFavoritesScreen())),
        child: Row(children: [
          const Icon(Icons.favorite_border, color: TtColors.danger),
          const SizedBox(width: TtSpace.s3),
          Expanded(child: Text('Mes professionnels favoris', style: TratraTheme.style(TtType.title))),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ]),
      );
}

/// Commande unique (Hybrid Matching) : métier, mode (« Trouvez-moi un professionnel » / « Choisir mon professionnel »), lieu, date, prix.
class FlashRequestFormScreen extends StatefulWidget {
  const FlashRequestFormScreen({super.key, this.initialCategory, this.initialMatching, this.initialPro});
  final Category? initialCategory;
  final String? initialMatching;
  final ChosenPro? initialPro;
  @override
  State<FlashRequestFormScreen> createState() => _FlashRequestFormScreenState();
}

class _FlashRequestFormScreenState extends State<FlashRequestFormScreen> {
  late final Future<Catalog> _catalog = CatalogRepository.shared(context.read<BaseApi>()).load();
  late Category? _category = widget.initialCategory;
  late String _matching = widget.initialMatching ?? kAuto;
  late bool _matchingTouched = widget.initialMatching != null;   // choix explicite du client : jamais écrasé par le conseil
  late ChosenPro? _pro = widget.initialPro;
  Map<String, dynamic>? _suggestion;
  AddressPick? _place;                 // adresse d'intervention (enregistrée, suggestion, position de l'appareil ou saisie libre)
  final _commune = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _quote = false;
  DateTime? _when;              // null = maintenant
  ({double lat, double lng})? get _position =>
      _place?.lat != null && _place?.lng != null ? (lat: _place!.lat!, lng: _place!.lng!) : null;
  bool _busy = false;
  String? _error;
  final String _idempotency = _key('flash-req');

  @override
  void initState() {
    super.initState();
    final offer = widget.initialPro?.offer;
    if (offer != null && offer['price_type'] == 'quote') _quote = true;
    _refreshSuggestion();
  }

  /// Conseil du serveur (type de mission, favori disponible, dernier choix) : appliqué tant que le client n'a pas choisi lui-même.
  Future<void> _refreshSuggestion() async {
    final c = _category;
    if (c == null) return;
    try {
      final s = await context.read<FlashController>().api.suggest(int.parse(c.id), when: _when, quote: _quote,
          lat: _position?.lat, lng: _position?.lng, commune: _commune.text.trim());
      if (!mounted) return;
      setState(() {
        _suggestion = s;
        if (!_matchingTouched && s['preselected'] is String) _matching = s['preselected'] as String;
      });
    } catch (_) {
      // conseil indisponible : le choix reste celui du client
    }
  }

  Future<void> _pickPro() async {
    final c = _category;
    if (c == null) {
      setState(() => _error = 'Choisissez d’abord le métier recherché.');
      return;
    }
    final chosen = await Navigator.of(context).push<ChosenPro>(MaterialPageRoute(
        builder: (_) => FlashProsScreen(categoryId: int.parse(c.id), categoryName: c.name, when: _when, lat: _position?.lat, lng: _position?.lng,
            commune: _commune.text.trim())));
    if (chosen != null && mounted) {
      setState(() {
        _pro = chosen;
        _matching = kDirect;
        _matchingTouched = true;
        _quote = chosen.offer?['price_type'] == 'quote';
        if (chosen.offer?['price'] is num) _amount.text = '${(chosen.offer!['price'] as num).toInt()}';
      });
    }
  }

  @override
  void dispose() {
    _commune.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: now);
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))));
    if (time == null) return;
    setState(() => _when = DateTime(day.year, day.month, day.day, time.hour, time.minute));
    _refreshSuggestion();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final problem = _category == null
        ? 'Choisissez le métier recherché.'
        : (_place == null || _place!.label.trim().isEmpty)
            ? 'Indiquez l’adresse de l’intervention.'
            : (_commune.text.trim().isEmpty && _position == null)
                ? 'Indiquez la commune ou partagez votre position.'
                : (_matching == kDirect && _pro == null)
                    ? 'Choisissez votre professionnel, ou laissez Tratra en trouver un.'
                    : (!_quote && (amount == null || amount <= 0))
                        ? 'Indiquez le montant que vous proposez.'
                        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<FlashController>().api.createRequest({
        'category': int.tryParse(_category!.id),
        'address': _place!.label.trim(),
        'commune': _commune.text.trim(),
        'mode': _quote ? 'quote' : 'firm',
        if (!_quote) 'amount': amount,
        'description': _description.text.trim(),
        if (_when != null) 'scheduled_for': _when!.toIso8601String(),
        if (_position != null) 'lat': _position!.lat,
        if (_position != null) 'lng': _position!.lng,
        'matching': _matching,
        if (_matching == kDirect) 'target': _pro!.id,
        if (_matching == kDirect && _pro!.offer != null) 'service': _pro!.offer!['id'],
      }, _idempotency);
      if (!mounted) return;
      final id = int.tryParse('${r['id']}');
      if (id != null) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => FlashRequestScreen(requestId: id)));
      }
    } on FlashApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Connexion impossible : votre demande n’a pas été envoyée.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_category == null ? 'Nouvelle demande' : _category!.name)),
      body: FutureBuilder<Catalog>(
        future: _catalog,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(child: snap.hasError ? const Text('Catalogue indisponible.') : const CircularProgressIndicator());
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (_category == null)
                CatalogAutocomplete(catalog: snap.data!, label: 'Métier recherché', hint: 'Plomberie, ménage, électricité…',
                    onSelected: (c) {
                      setState(() {
                        _category = c;
                        _pro = null;
                      });
                      _refreshSuggestion();
                    })
              else
                TratraCard(
                  key: const ValueKey('flash-category'),
                  padding: TratraCard.compact,
                  child: Row(children: [
                    const Icon(Icons.handyman_outlined, color: TtColors.primary),
                    const SizedBox(width: TtSpace.s3),
                    Expanded(child: Text(_category!.name, style: TratraTheme.style(TtType.title))),
                    TextButton(onPressed: () => setState(() {
                          _category = null;
                          _pro = null;
                          _suggestion = null;
                        }), child: const Text('Changer')),
                  ]),
                ),
              const SizedBox(height: TtSpace.s3),
              Text('Comment trouver votre professionnel ?', style: TratraTheme.style(TtType.title)),
              const SizedBox(height: TtSpace.s2),
              ModeSelector(
                value: _matching,
                suggestion: _suggestion,
                onChanged: (v) => setState(() {
                  _matching = v;
                  _matchingTouched = true;
                }),
              ),
              if (_matching == kDirect) ...[
                const SizedBox(height: TtSpace.s3),
                if (_pro == null)
                  TratraButton(key: const ValueKey('flash-pick-pro'), label: 'Choisir le professionnel', variant: TratraButtonVariant.outline,
                      leading: const Icon(Icons.person_search_rounded, size: 18), block: true, onPressed: _pickPro)
                else
                  ProCard(
                    key: const ValueKey('flash-chosen-pro'),
                    card: _pro!.card,
                    chooseLabel: 'Changer',
                    onChoose: _pickPro,
                  ),
                if (_pro?.offer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: TtSpace.s1),
                    child: Text('Prestation : ${_pro!.offer!['title']}', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
                  ),
              ],
              const SizedBox(height: TtSpace.s3),
              AddressAutocompleteField(
                key: const ValueKey('flash-address'),
                helper: 'Communiquée au professionnel seulement quand il a accepté.',
                onChanged: (pick) {
                  setState(() {
                    _place = pick;
                    if (pick != null && pick.commune.isNotEmpty) _commune.text = pick.commune;
                  });
                  if (pick?.lat != null) _refreshSuggestion();
                },
              ),
              const SizedBox(height: TtSpace.s2),
              TratraInput(key: const ValueKey('flash-commune'), controller: _commune, label: 'Commune ou quartier', hint: 'Cocody, Yopougon…',
                  helper: _position != null ? 'Position connue : les professionnels les plus proches sont sollicités.' : null),
              const SizedBox(height: TtSpace.s2),
              Text('Quand ?', style: TratraTheme.style(TtType.title)),
              Wrap(spacing: TtSpace.s2, children: [
                TratraChip(label: 'Maintenant', selected: _when == null, onTap: () {
                  setState(() => _when = null);
                  _refreshSuggestion();
                }),
                TratraChip(
                    label: _when == null ? 'Planifier' : '${_when!.day.toString().padLeft(2, '0')}/${_when!.month.toString().padLeft(2, '0')} à '
                        '${_when!.hour.toString().padLeft(2, '0')} h ${_when!.minute.toString().padLeft(2, '0')}',
                    selected: _when != null,
                    onTap: _pickDate),
              ]),
              const SizedBox(height: TtSpace.s3),
              Text('Prix', style: TratraTheme.style(TtType.title)),
              Wrap(spacing: TtSpace.s2, children: [
                TratraChip(key: const ValueKey('flash-mode-firm'), label: 'Je propose un prix', selected: !_quote, onTap: () {
                  setState(() => _quote = false);
                  _refreshSuggestion();
                }),
                TratraChip(key: const ValueKey('flash-mode-quote'), label: 'Je veux des devis', selected: _quote, onTap: () {
                  setState(() => _quote = true);
                  _refreshSuggestion();
                }),
              ]),
              const SizedBox(height: TtSpace.s2),
              if (!_quote)
                TratraInput(key: const ValueKey('flash-amount-input'), controller: _amount, label: 'Montant proposé (FCFA, déplacement compris)',
                    keyboardType: TextInputType.number, helper: 'Le premier professionnel qui accepte ce montant obtient la mission.')
              else
                Text('Les professionnels disponibles vous envoient un prix ; vous choisissez celui qui vous convient.',
                    style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
              const SizedBox(height: TtSpace.s3),
              TratraInput(controller: _description, label: 'Décrivez votre besoin', optional: true, maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: TtSpace.s3),
                TratraAlert(key: const ValueKey('flash-form-error'), tone: TratraAlertTone.danger, message: _error!),
              ],
              const SizedBox(height: TtSpace.s4),
              TratraButton(key: const ValueKey('flash-submit'), label: 'Envoyer ma demande', size: TratraButtonSize.lg, block: true,
                  loading: _busy, onPressed: _busy ? null : _submit),
            ],
          );
        },
      ),
    );
  }
}
