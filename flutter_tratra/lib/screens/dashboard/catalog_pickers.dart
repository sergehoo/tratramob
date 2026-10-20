// lib/screens/dashboard/catalog_pickers.dart
//
// Sélection dans le catalogue commun des métiers (/handy/catalog/) : autocomplétion (« Métier » d'une offre) et choix des spécialités
// du profil professionnel. Aucun métier n'est créé par saisie libre : seules les entrées du catalogue sont retenues.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

int _id(Category c) => int.parse(c.id);

/// Liste de suggestions commune : nom, et rattachement (« Métier · 3 prestations », « Prestation · Plomberie »).
Widget catalogOptionsView(Catalog catalog, AutocompleteOnSelected<Category> select, Iterable<Category> options, {String? tradeId}) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        color: TtColors.surface,
        borderRadius: BorderRadius.circular(TtRadius.control),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = options.elementAt(i);
              final under = !c.isTrade && tradeId == null ? catalog.byId(c.trade ?? '')?.name : null;
              final n = c.isTrade ? catalog.prestationsOf(c.id).length : 0;
              return ListTile(
                key: ValueKey('option-${c.id}'),
                dense: true,
                leading: Icon(c.isTrade ? Icons.handyman_outlined : Icons.subdirectory_arrow_right_rounded, color: TtColors.primary, size: 20),
                title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  c.isTrade ? (n == 0 ? 'Métier' : 'Métier · $n prestation${n > 1 ? 's' : ''}') : under == null ? 'Prestation' : 'Prestation · $under',
                  style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                ),
                onTap: () => select(c),
              );
            },
          ),
        ),
      ),
    );

/// Champ à autocomplétion sur le catalogue : suggestions dès la saisie (sans accents ni majuscules), métiers et prestations avec leur
/// rattachement ; seule une suggestion choisie dans la liste est retenue.
class CatalogAutocomplete extends StatefulWidget {
  const CatalogAutocomplete({super.key, required this.catalog, required this.label, required this.onSelected, this.tradeId, this.hint, this.error});
  final Catalog catalog;
  final String label;
  final String? tradeId;
  final String? hint;
  final String? error;
  final ValueChanged<Category?> onSelected;

  @override
  State<CatalogAutocomplete> createState() => _CatalogAutocompleteState();
}

class _CatalogAutocompleteState extends State<CatalogAutocomplete> {
  Category? chosen;

  String _display(Category c) => widget.tradeId == null ? widget.catalog.pathOf(c) : c.name;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Category>(
      displayStringForOption: _display,
      optionsBuilder: (v) => widget.catalog.search(v.text, tradeId: widget.tradeId),
      onSelected: (c) {
        chosen = c;
        FocusScope.of(context).unfocus();
        widget.onSelected(c);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TratraInput(
        controller: controller,
        focusNode: focusNode,
        label: widget.label,
        hint: widget.hint,
        required: true,
        errorText: widget.error,
        textInputAction: TextInputAction.search,
        leadingIcon: Icons.search_rounded,
        suffix: _ClearButton(controller: controller, onClear: () {
          chosen = null;
          widget.onSelected(null);
          focusNode.requestFocus();
        }),
        onChanged: (text) {
          if (chosen != null && text != _display(chosen!)) {
            chosen = null;                                         // la saisie ne correspond plus au choix : il faut rechoisir
            widget.onSelected(null);
          }
        },
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (context, select, options) => catalogOptionsView(widget.catalog, select, options, tradeId: widget.tradeId),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.controller, required this.onClear});
  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, v, _) => v.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onClear();
                },
              ),
      );
}

/// Spécialités du profil professionnel, organisées pour une liste longue :
///  1. les spécialités CHOISIES remontent en haut (croix pour retirer) ;
///  2. une recherche à autocomplétion ajoute un métier ou une prestation en quelques lettres ;
///  3. le reste se parcourt par MÉTIER (famille), chaque métier dépliant ses prestations ; tout ce qui est choisi disparaît de cette
///     liste, qui se resserre — inutile de la parcourir en entier.
class SkillsPicker extends StatefulWidget {
  const SkillsPicker({super.key, required this.catalog, required this.selected, required this.onChanged, this.initialGroups = 8});
  final Catalog catalog;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  /// Métiers affichés avant « Voir les autres métiers ».
  final int initialGroups;

  @override
  State<SkillsPicker> createState() => _SkillsPickerState();
}

class _SkillsPickerState extends State<SkillsPicker> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  bool _showAll = false;

  Catalog get _c => widget.catalog;
  bool _has(Category c) => widget.selected.contains(_id(c));

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(Category c) => widget.onChanged({...widget.selected, _id(c)});
  void _remove(int id) => widget.onChanged({...widget.selected}..remove(id));

  @override
  Widget build(BuildContext context) {
    // Choisies, dans l'ordre du catalogue ; une spécialité retirée du catalogue reste visible pour pouvoir l'enlever.
    final known = [for (final c in _c.items) if (_has(c)) c];
    final unknown = [for (final id in widget.selected) if (_c.byId('$id') == null) id];
    // Familles = métiers ; un métier disparaît quand lui et toutes ses prestations sont choisis.
    final groups = <(Category, List<Category>)>[
      for (final t in _c.trades)
        if (!_has(t) || _c.prestationsOf(t.id).any((p) => !_has(p))) (t, [for (final p in _c.prestationsOf(t.id)) if (!_has(p)) p]),
    ];
    final visible = _showAll ? groups : groups.take(widget.initialGroups).toList();
    final n = widget.selected.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Spécialités', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600))),
        if (n > 0) TratraBadge('$n choisie${n > 1 ? 's' : ''}', tone: TratraTone.success),
      ]),
      const SizedBox(height: 4),
      Text('Recherchez ou parcourez les métiers : ce que vous choisissez remonte ici.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
      const SizedBox(height: TtSpace.s2),
      AnimatedSize(
        duration: TtMotion.fast,
        alignment: Alignment.topLeft,
        child: n == 0
            ? Text('Aucune spécialité choisie.', key: const ValueKey('skills-none'), style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))
            : Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
                for (final c in known)
                  InputChip(
                    key: ValueKey('skill-chosen-${c.id}'),
                    label: Text(_c.pathOf(c)),
                    selected: true,
                    showCheckmark: false,
                    selectedColor: TtColors.primarySoft,
                    side: const BorderSide(color: TtColors.primary),
                    labelStyle: TratraTheme.style(TtType.bodySm, color: TtColors.primaryDark).copyWith(fontWeight: FontWeight.w600),
                    deleteIcon: const Icon(Icons.close_rounded, size: 18),
                    deleteButtonTooltipMessage: 'Retirer',
                    onDeleted: () => _remove(_id(c)),
                  ),
                for (final id in unknown)
                  InputChip(
                    key: ValueKey('skill-chosen-$id'),
                    label: const Text('Spécialité retirée du catalogue'),
                    deleteButtonTooltipMessage: 'Retirer',
                    onDeleted: () => _remove(id),
                  ),
              ]),
      ),
      const SizedBox(height: TtSpace.s3),
      RawAutocomplete<Category>(
        textEditingController: _search,
        focusNode: _focus,
        displayStringForOption: (c) => _c.pathOf(c),
        optionsBuilder: (v) => v.text.trim().isEmpty ? const <Category>[] : _c.search(v.text).where((c) => !_has(c)),
        onSelected: (c) {
          _add(c);
          _search.clear();                                         // prêt pour la spécialité suivante
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) => TratraInput(
          key: const ValueKey('skills-search'),
          controller: controller,
          focusNode: focusNode,
          label: 'Ajouter une spécialité',
          hint: 'Ex. plomberie, fuite, nounou',
          leadingIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          suffix: _ClearButton(controller: controller, onClear: focusNode.requestFocus),
          onSubmitted: (_) => onSubmit(),
        ),
        optionsViewBuilder: (context, select, options) => catalogOptionsView(_c, select, options),
      ),
      if (groups.isNotEmpty) ...[
        const SizedBox(height: TtSpace.s3),
        Text('Ou parcourez par métier', style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: TtSpace.s2),
        AnimatedSize(
          duration: TtMotion.fast,
          alignment: Alignment.topCenter,
          child: TratraCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _Family(
                  trade: visible[i].$1,
                  prestations: visible[i].$2,
                  tradeChosen: _has(visible[i].$1),
                  wholeTradeOnly: visible[i].$2.isEmpty && _c.prestationsOf(visible[i].$1.id).isNotEmpty,
                  onAdd: _add,
                ),
              ],
            ]),
          ),
        ),
        if (groups.length > widget.initialGroups)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('skills-more'),
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(_showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(_showAll ? 'Réduire la liste' : 'Voir les ${groups.length - widget.initialGroups} autres métiers'),
            ),
          ),
      ],
    ]);
  }
}

/// Un métier (famille) : ajout direct s'il n'a pas de prestation, sinon dépliable pour choisir le métier entier ou ses prestations.
class _Family extends StatelessWidget {
  const _Family({required this.trade, required this.prestations, required this.tradeChosen, required this.onAdd, this.wholeTradeOnly = false});
  final Category trade;
  final List<Category> prestations;
  final bool tradeChosen;
  final ValueChanged<Category> onAdd;

  /// Toutes les prestations du métier sont déjà choisies : il ne reste qu'à ajouter le métier entier.
  final bool wholeTradeOnly;

  @override
  Widget build(BuildContext context) {
    if (prestations.isEmpty) {
      return ListTile(
        key: ValueKey('family-${trade.id}'),
        dense: true,
        title: Text(trade.name, style: TratraTheme.style(TtType.bodySm)),
        subtitle: wholeTradeOnly ? Text('Ajouter le métier entier', style: TratraTheme.style(TtType.caption, color: TtColors.ash)) : null,
        trailing: const Icon(Icons.add_circle_outline_rounded, color: TtColors.primary),
        onTap: () => onAdd(trade),
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('family-${trade.id}'),
        dense: true,
        title: Text(trade.name, style: TratraTheme.style(TtType.bodySm)),
        subtitle: Text('${prestations.length} prestation${prestations.length > 1 ? 's' : ''} à choisir',
            style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        childrenPadding: const EdgeInsets.fromLTRB(TtSpace.s4, 0, TtSpace.s4, TtSpace.s3),
        expandedAlignment: Alignment.centerLeft,
        children: [
          Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
            if (!tradeChosen)
              ActionChip(
                key: ValueKey('family-all-${trade.id}'),
                avatar: const Icon(Icons.add_rounded, size: 18, color: TtColors.primary),
                label: const Text('Tout le métier'),
                onPressed: () => onAdd(trade),
              ),
            for (final p in prestations)
              ActionChip(
                key: ValueKey('family-item-${p.id}'),
                avatar: const Icon(Icons.add_rounded, size: 18, color: TtColors.primary),
                label: Text(p.name),
                onPressed: () => onAdd(p),
              ),
          ]),
        ],
      ),
    );
  }
}
