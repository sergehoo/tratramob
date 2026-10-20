// lib/design/widgets/tratra_phone_field.dart
//
// Champ téléphone commun : [drapeau +indicatif ▼] [numéro national]. L'utilisateur ne tape jamais l'indicatif : il choisit le pays dans
// une liste avec recherche (nom sans accents, code, indicatif). Un numéro collé ou tapé avec son indicatif (« +33 6… ») change le pays tout
// seul. Clavier téléphonique, mise en forme pendant la saisie, messages d'erreur clairs (voir `PhoneValue.error`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart' show IsoCode;

import 'package:flutter_tratra/core/phone/phone_value.dart';
import 'package:flutter_tratra/design/theme.dart';
import 'package:flutter_tratra/design/tokens.dart';

class TratraPhoneField extends StatefulWidget {
  const TratraPhoneField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Téléphone',
    this.helper = 'Choisissez le pays, puis saisissez votre numéro sans l’indicatif.',
    this.errorText,
    this.required = false,
    this.optional = false,
    this.autoCountry = true,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.validator,
    this.autofillHints = const [AutofillHints.telephoneNumberNational],
    this.ipRegion,
  });

  final PhoneValue value;
  final ValueChanged<PhoneValue> onChanged;
  final String label;
  final String? helper;
  final String? errorText;
  final bool required;
  final bool optional;

  /// Pays de départ déduit (préférence, SIM, région, IP connue, Côte d'Ivoire) tant que rien n'a été saisi.
  final bool autoCountry;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final Iterable<String> autofillHints;

  /// Pays de l'adresse IP déjà connu du serveur (GET /phone/defaults/), si disponible.
  final Future<String?> Function()? ipRegion;

  @override
  State<TratraPhoneField> createState() => _TratraPhoneFieldState();
}

class _TratraPhoneFieldState extends State<TratraPhoneField> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.value.national);
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoCountry && widget.value.isEmpty) {
      resolveDefaultPhoneCountry(ipRegion: widget.ipRegion).then((iso) {
        if (mounted && !_touched && widget.value.isEmpty && iso != widget.value.iso) widget.onChanged(widget.value.copyWith(iso: iso));
      });
    }
  }

  @override
  void didUpdateWidget(TratraPhoneField old) {
    super.didUpdateWidget(old);
    // Valeur changée par le parent : le texte est resynchronisé APRÈS la construction (un Form ne doit pas être notifié pendant).
    if (widget.value.national != _ctrl.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _setText(widget.value.national);
      });
    }
  }

  void _setText(String text) {
    if (_ctrl.text == text) return;
    _ctrl.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _emit(PhoneValue next) {
    _setText(next.national);
    widget.onChanged(next);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onText(String raw) {
    _touched = true;
    final pasted = PhoneValue.splitInternational(raw);
    if (pasted != null) {
      rememberPhoneCountry(pasted.iso);
      _emit(pasted);
      return;
    }
    if (RegExp(r'^\s*(\+|00)').hasMatch(raw)) {
      // Indicatif en cours de saisie (« +3… ») : gardé tel quel jusqu'à ce que le pays soit reconnu.
      _emit(widget.value.copyWith(national: raw.replaceAll(RegExp(r'[^\d+ ]'), '')));
      return;
    }
    _emit(widget.value.copyWith(national: formatNational(raw, widget.value.iso)));
  }

  Future<void> _pickCountry() async {
    final iso = await showModalBottomSheet<IsoCode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: TtColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(TtRadius.sheet))),
      builder: (_) => _CountrySheet(current: widget.value.iso),
    );
    if (iso == null || !mounted) return;
    _touched = true;
    rememberPhoneCountry(iso);
    _emit(PhoneValue(iso, formatNational(widget.value.national, iso)));
  }

  @override
  Widget build(BuildContext context) {
    final iso = widget.value.iso;
    final name = countryNameFr(iso);
    final dial = dialOf(iso);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600, fontSize: 14),
            children: [
              TextSpan(text: widget.label),
              if (widget.required) const TextSpan(text: ' *', style: TextStyle(color: TtColors.danger)),
              if (widget.optional)
                TextSpan(text: '  (facultatif)', style: TratraTheme.style(TtType.caption, color: TtColors.ash).copyWith(fontWeight: FontWeight.w400)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: const ValueKey('phone-national'),
          controller: _ctrl,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          keyboardType: TextInputType.phone,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ().\-]'))],
          onChanged: _onText,
          onFieldSubmitted: widget.onSubmitted,
          validator: widget.validator,
          style: TratraTheme.style(TtType.body).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          cursorColor: TtColors.primaryDark,
          decoration: InputDecoration(
            hintText: exampleNational(iso),
            helperText: widget.helper,
            helperMaxLines: 3,
            errorText: widget.errorText,
            errorMaxLines: 3,
            filled: true,
            fillColor: widget.enabled ? TtColors.surface : TtColors.canvas,
            prefixIconConstraints: const BoxConstraints(minHeight: 48),
            prefixIcon: Semantics(
              button: true,
              label: 'Pays : $name, indicatif +$dial. Changer de pays',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('phone-country'),
                onTap: widget.enabled ? _pickCountry : null,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(TtRadius.control)),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: TtColors.line))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(flagOf(iso.name), style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text('+$dial', style: TratraTheme.style(TtType.body).copyWith(fontWeight: FontWeight.w600)),
                    const Icon(Icons.arrow_drop_down_rounded, color: TtColors.ash),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Liste des pays avec recherche (nom sans accents, code ISO, indicatif). Le pays actuel et la Côte d'Ivoire sont en tête.
class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.current});
  final IsoCode current;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final found = searchPhoneCountries(_query);
    final results = _query.isNotEmpty
        ? found
        : [
            ...found.where((c) => c.iso == widget.current || c.iso == IsoCode.CI),
            ...found.where((c) => c.iso != widget.current && c.iso != IsoCode.CI),
          ];
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: TtColors.line, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s2, 0),
            child: Row(children: [
              Expanded(child: Text('Choisir le pays', style: TratraTheme.style(TtType.h3))),
              IconButton(tooltip: 'Fermer', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
            child: Text('L’indicatif est ajouté automatiquement : saisissez ensuite votre numéro sans lui.',
                style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s2),
            child: TextField(
              key: const ValueKey('country-search'),
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Pays ou indicatif (ex. Sénégal, +221)',
                prefixIcon: Icon(Icons.search_rounded),
                filled: true,
                fillColor: TtColors.surface,
              ),
            ),
          ),
          Semantics(liveRegion: true, child: Text('${results.length} pays', style: TratraTheme.style(TtType.caption, color: TtColors.ash))),
          Expanded(
            child: results.isEmpty
                ? Center(child: Text('Aucun pays ne correspond à « $_query ».', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(TtSpace.s2, TtSpace.s1, TtSpace.s2, TtSpace.s4),
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final c = results[i];
                      final selected = c.iso == widget.current;
                      return Semantics(
                        selected: selected,
                        child: ListTile(
                          key: ValueKey('country-${c.code}'),
                          minTileHeight: 48,
                          leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('+${c.dial}', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                            if (selected) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_rounded, color: TtColors.primary, size: 20)),
                          ]),
                          selected: selected,
                          selectedTileColor: TtColors.primarySoft,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TtRadius.control)),
                          onTap: () => Navigator.of(context).pop(c.iso),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
