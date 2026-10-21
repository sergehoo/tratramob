// lib/widgets/address_autocomplete.dart
//
// Adresse d'intervention avec autocomplétion : mes adresses enregistrées d'abord, puis les suggestions du service d'adresses du serveur
// (`GET /geo/search/` — communes, quartiers, rues ; fournisseur configurable côté serveur : OpenStreetMap, ou Google Maps avec une clé),
// et « Ma position actuelle » (lecture unique du GPS à la demande, puis `GET /geo/reverse/`). Aucune clé de fournisseur dans l'application.
// Fournisseur indisponible : la saisie libre reste possible (jamais de blocage).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/services/location_service.dart';

/// Adresse retenue : texte affiché, commune ou quartier, ville, position (si connue) et origine (enregistrée, suggestion, appareil, saisie).
class AddressPick {
  const AddressPick({required this.label, this.commune = '', this.city = '', this.lat, this.lng, this.source = 'manual'});
  final String label;
  final String commune;
  final String city;
  final double? lat;
  final double? lng;
  final String source;

  static AddressPick fromSuggestion(Map<String, dynamic> s, String source) {
    final street = '${s['street'] ?? ''}'.trim();
    final commune = '${s['commune'] ?? ''}'.trim();
    final city = '${s['city'] ?? ''}'.trim();
    final label = [if (street.isNotEmpty) street, if (commune.isNotEmpty) commune, if (city.isNotEmpty) city].join(', ');
    return AddressPick(label: label.isNotEmpty ? label : '${s['label'] ?? ''}', commune: commune, city: city,
        lat: (s['latitude'] as num?)?.toDouble(), lng: (s['longitude'] as num?)?.toDouble(), source: source);
  }
}

class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({super.key, required this.onChanged, this.label = 'Adresse de l’intervention', this.helper});
  final ValueChanged<AddressPick?> onChanged;
  final String label;
  final String? helper;

  @override
  State<AddressAutocompleteField> createState() => _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  List<Map<String, dynamic>> _saved = const [];
  List<Map<String, dynamic>> _suggestions = const [];
  AddressPick? _picked;
  bool _locating = false;
  bool _searching = false;
  String? _notice;

  BaseApi get _api => context.read<BaseApi>();

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await _api.client.get(Uri.parse('${_api.baseUrl}$path'), headers: await _api.headers);
    final body = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode < 200 || r.statusCode >= 300) throw StateError('${r.statusCode}');
    return body is Map ? body.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> _loadSaved() async {
    try {
      final r = await _get('/me/addresses/');
      final rows = ((r['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      if (mounted) setState(() => _saved = rows);
    } catch (_) {
      // pas d'adresse enregistrée ou hors ligne : suggestions seules
    }
  }

  void _onChanged(String value) {
    _picked = null;
    widget.onChanged(value.trim().isEmpty ? null : AddressPick(label: value.trim()));   // saisie libre acceptée
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    final mine = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final r = await _get('/geo/search/?q=${Uri.encodeQueryComponent(q)}');
        if (!mounted || mine != _seq) return;
        setState(() {
          _suggestions = ((r['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          _notice = null;
        });
      } catch (_) {
        if (mounted && mine == _seq) setState(() => _notice = 'Suggestions indisponibles : saisissez l’adresse et la commune.');
      } finally {
        if (mounted && mine == _seq) setState(() => _searching = false);
      }
    });
  }

  void _choose(AddressPick pick) {
    FocusScope.of(context).unfocus();
    setState(() {
      _picked = pick;
      _controller.text = pick.label;
      _suggestions = const [];
      _notice = null;
    });
    widget.onChanged(pick);
  }

  Future<void> _useMyPosition() async {
    setState(() {
      _locating = true;
      _notice = null;
    });
    try {
      final p = await context.read<LocationService>().getCurrentLocation();   // une seule lecture, à la demande de l'utilisateur
      Map<String, dynamic>? found;
      try {
        final r = await _get('/geo/reverse/?lat=${p.latitude}&lng=${p.longitude}&consent=true');
        found = (r['result'] as Map?)?.cast<String, dynamic>();
      } catch (_) {
        found = null;
      }
      if (!mounted) return;
      if (found != null) {
        _choose(AddressPick.fromSuggestion(found, 'device'));
      } else {
        _choose(AddressPick(label: _controller.text.trim().isEmpty ? 'Ma position actuelle' : _controller.text.trim(),
            lat: p.latitude, lng: p.longitude, source: 'device'));
        setState(() => _notice = 'Position enregistrée ; précisez la rue ou un repère si besoin.');
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Position indisponible ou refusée : saisissez l’adresse.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _controller.text.trim().toLowerCase();
    final saved = _picked != null
        ? const <Map<String, dynamic>>[]
        : _saved.where((a) => q.isEmpty || '${a['label']} ${a['street']} ${a['commune']}'.toLowerCase().contains(q)).take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TratraInput(
        key: const ValueKey('address-input'),
        controller: _controller,
        label: widget.label,
        hint: 'Commune, quartier, rue…',
        helper: widget.helper,
        required: true,
        leadingIcon: Icons.place_outlined,
        suffix: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
        onChanged: _onChanged,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('address-my-position'),
          onPressed: _locating ? null : _useMyPosition,
          icon: Icon(_picked?.source == 'device' ? Icons.check_circle : Icons.my_location_rounded, size: 18),
          label: Text(_locating ? 'Localisation…' : 'Utiliser ma position actuelle'),
        ),
      ),
      if (saved.isNotEmpty || _suggestions.isNotEmpty)
        TratraCard(
          key: const ValueKey('address-suggestions'),
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final a in saved)
              ListTile(
                key: ValueKey('address-saved-${a['id']}'),
                dense: true,
                leading: const Icon(Icons.bookmark_border, color: TtColors.primary),
                title: Text('${a['label'] ?? 'Adresse'}'.isEmpty ? '${a['street']}' : '${a['label']}'),
                subtitle: Text(['${a['street'] ?? ''}', '${a['commune'] ?? ''}'].where((x) => x.isNotEmpty).join(', ')),
                onTap: () => _choose(AddressPick.fromSuggestion(a, 'saved')),
              ),
            for (final (i, sug) in _suggestions.indexed)
              ListTile(
                key: ValueKey('address-suggestion-$i'),
                dense: true,
                leading: const Icon(Icons.place_outlined, color: TtColors.ash),
                title: Text([sug['street'], sug['commune']].where((x) => '${x ?? ''}'.isNotEmpty).join(', ').isEmpty
                    ? '${sug['label']}'
                    : [sug['street'], sug['commune']].where((x) => '${x ?? ''}'.isNotEmpty).join(', ')),
                subtitle: Text('${sug['city'] ?? ''}'),
                onTap: () => _choose(AddressPick.fromSuggestion(sug, 'geocoder')),
              ),
          ]),
        ),
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.only(top: TtSpace.s1),
          child: Text(_notice!, style: TratraTheme.style(TtType.caption, color: TtColors.warningInk)),
        ),
    ]);
  }
}
