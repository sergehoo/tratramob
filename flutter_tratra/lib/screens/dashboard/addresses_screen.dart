// lib/screens/dashboard/addresses_screen.dart
//
// Mes adresses (miroir de frontend/src/components/address/AddressesCard.tsx) : principale, secondaires, favorites ;
// autocomplétion via l'API Tratra (fournisseur configuré côté serveur, mis en cache), position actuelle APRÈS consentement
// explicite (une lecture, aucun suivi), sélection sur carte, saisie manuelle toujours possible. Le serveur valide et reste l'autorité.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/api_exception.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/live/live_map.dart' show kMapTiles;
import 'package:flutter_tratra/services/location_service.dart';

String addressLine(Map<String, dynamic> a) =>
    ['street', 'commune', 'city', 'country'].map((k) => '${a[k] ?? ''}'.trim()).where((s) => s.isNotEmpty).join(', ');

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});
  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, failure), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open([Map<String, dynamic>? address]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddressFormScreen(initial: address)));
    if (saved == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return DashPage(
      title: 'Mes adresses',
      body: ApiView<Map<String, dynamic>>(
        key: ValueKey('addresses-$_version'),
        errorTitle: 'Adresses indisponibles',
        load: () => _api.getMap('/me/addresses/'),
        builder: (context, data, reload) {
          final rows = ((data['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          final max = (data['max'] as num?)?.toInt() ?? 10;
          return ListView(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
            children: [
              Text(
                'Seul vous voyez vos adresses. L’adresse principale est demandée avant votre première demande ou prestation ; '
                'chaque réservation peut utiliser une adresse différente.',
                style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
              ),
              const SizedBox(height: TtSpace.s3),
              if (rows.isEmpty)
                const TratraAlert(tone: TratraAlertTone.info, message: 'Aucune adresse enregistrée. Ajoutez votre adresse principale.'),
              for (final a in rows) ...[
                TratraCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s1, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${a['label'] ?? ''}'.isEmpty ? 'Adresse' : '${a['label']}', style: TratraTheme.style(TtType.h3)),
                      if (a['is_primary'] == true) const TratraBadge('Principale', tone: TratraTone.success),
                      if (a['is_favorite'] == true) const TratraBadge('Favorite', tone: TratraTone.accent),
                    ]),
                    const SizedBox(height: TtSpace.s1),
                    Text(addressLine(a) + ('${a['complement'] ?? ''}'.isEmpty ? '' : ' — ${a['complement']}'),
                        style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
                    const SizedBox(height: TtSpace.s2),
                    Wrap(spacing: TtSpace.s2, children: [
                      if (a['is_primary'] != true)
                        TratraButton(
                            label: 'Principale',
                            size: TratraButtonSize.sm,
                            variant: TratraButtonVariant.outline,
                            onPressed: _busy ? null : () => _run(() async => _api.post('/me/addresses/${a['id']}/primary/'), 'L’adresse n’a pas pu être modifiée.')),
                      TratraButton(
                          label: a['is_favorite'] == true ? 'Retirer des favorites' : 'Favorite',
                          size: TratraButtonSize.sm,
                          variant: TratraButtonVariant.outline,
                          onPressed: _busy
                              ? null
                              : () => _run(() async => _api.patch('/me/addresses/${a['id']}/', {'is_favorite': a['is_favorite'] != true}), 'Le réglage n’a pas pu être enregistré.')),
                      TratraButton(label: 'Modifier', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, onPressed: _busy ? null : () => _open(a)),
                      TratraButton(
                          label: 'Supprimer',
                          size: TratraButtonSize.sm,
                          variant: TratraButtonVariant.outline,
                          onPressed: _busy
                              ? null
                              : () async {
                                  final ok = await showTratraConfirm(context, title: 'Supprimer cette adresse ?', message: addressLine(a), confirmLabel: 'Supprimer', danger: true);
                                  if (ok && mounted) await _run(() => _api.delete('/me/addresses/${a['id']}/'), 'L’adresse n’a pas pu être supprimée.');
                                }),
                    ]),
                  ]),
                ),
                const SizedBox(height: TtSpace.s3),
              ],
              if (rows.length < max) TratraButton(label: 'Ajouter une adresse', block: true, leading: const Icon(Icons.add), onPressed: _busy ? null : () => _open()),
            ],
          );
        },
      ),
    );
  }
}

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _label = TextEditingController();
  final _country = TextEditingController(text: 'Côte d’Ivoire');
  final _city = TextEditingController();
  final _commune = TextEditingController();
  final _street = TextEditingController();
  final _complement = TextEditingController();
  final _query = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  List<Map<String, dynamic>> _options = const [];
  bool _manual = false;
  bool _consent = false;
  bool _primary = false;
  bool _showMap = false;
  bool _busy = false;
  String? _info;
  String? _failure;
  Map<String, String> _errors = const {};
  double? _lat;
  double? _lng;
  String _source = '';

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _label.text = '${a['label'] ?? ''}';
      _country.text = '${a['country'] ?? ''}';
      _city.text = '${a['city'] ?? ''}';
      _commune.text = '${a['commune'] ?? ''}';
      _street.text = '${a['street'] ?? ''}';
      _complement.text = '${a['complement'] ?? ''}';
      _lat = (a['latitude'] as num?)?.toDouble();
      _lng = (a['longitude'] as num?)?.toDouble();
      _source = '${a['coords_source'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_label, _country, _city, _commune, _street, _complement, _query]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isManualFallback(Object e) => e is ApiException && (e.statusCode == 503 || e.statusCode == 429);

  void _onQuery(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() => _options = const []);
      return;
    }
    final mine = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final r = await _api.getMap('/geo/search/?q=${Uri.encodeQueryComponent(q)}');
        if (!mounted || mine != _seq) return;
        setState(() {
          _options = ((r['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          _manual = false;
        });
      } catch (e) {
        if (mounted && mine == _seq) setState(() => _manual = _isManualFallback(e) || true);
      }
    });
  }

  void _apply(Map<String, dynamic> s, String source) {
    setState(() {
      if ('${s['street'] ?? ''}'.isNotEmpty) _street.text = '${s['street']}';
      if ('${s['commune'] ?? ''}'.isNotEmpty) _commune.text = '${s['commune']}';
      if ('${s['city'] ?? ''}'.isNotEmpty) _city.text = '${s['city']}';
      if ('${s['country'] ?? ''}'.isNotEmpty) _country.text = '${s['country']}';
      _lat = (s['latitude'] as num?)?.toDouble();
      _lng = (s['longitude'] as num?)?.toDouble();
      _source = source;
      _options = const [];
      _query.clear();
    });
  }

  Future<Map<String, dynamic>?> _reverse(double lat, double lng) async {
    try {
      final r = await _api.getMap('/geo/reverse/?lat=$lat&lng=$lng&consent=true');
      return (r['result'] as Map?)?.cast<String, dynamic>();
    } catch (e) {
      if (_isManualFallback(e)) return null;
      rethrow;
    }
  }

  Future<void> _useMyPosition() async {
    setState(() {
      _failure = null;
      _info = null;
    });
    if (!_consent) {
      setState(() => _failure = 'Cochez la case pour autoriser l’utilisation ponctuelle de votre position.');
      return;
    }
    setState(() => _busy = true);
    try {
      final p = await LocationService().getCurrentLocation(); // une seule lecture, après consentement
      final found = await _reverse(p.latitude, p.longitude);
      if (found != null) {
        _apply(found, 'device');
      } else {
        setState(() {
          _lat = p.latitude;
          _lng = p.longitude;
          _source = 'device';
          _info = 'Position enregistrée ; complétez la rue et le quartier.';
        });
      }
    } catch (e) {
      setState(() => _failure = 'Position indisponible ou refusée : saisissez l’adresse manuellement.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onMapTap(LatLng p) async {
    final lat = double.parse(p.latitude.toStringAsFixed(6));
    final lng = double.parse(p.longitude.toStringAsFixed(6));
    setState(() {
      _lat = lat;
      _lng = lng;
      _source = 'map';
    });
    final found = await _reverse(lat, lng).catchError((_) => null);
    if (found != null && mounted) {
      setState(() {
        if ('${found['street'] ?? ''}'.isNotEmpty) _street.text = '${found['street']}';
        if ('${found['commune'] ?? ''}'.isNotEmpty) _commune.text = '${found['commune']}';
        if ('${found['city'] ?? ''}'.isNotEmpty) _city.text = '${found['city']}';
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failure = null;
      _errors = const {};
    });
    final body = <String, dynamic>{
      'label': _label.text, 'country': _country.text, 'city': _city.text, 'commune': _commune.text, 'street': _street.text, 'complement': _complement.text,
      'latitude': _lat, 'longitude': _lng, 'coords_source': _lat == null ? '' : _source,
      if (_source == 'device' && _lat != null) 'location_consent': true,
    };
    try {
      if (widget.initial != null) {
        await _api.patch('/me/addresses/${widget.initial!['id']}/', body);
      } else {
        await _api.post('/me/addresses/', {...body, 'is_primary': _primary});
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      Map<String, String> fields = const {};
      try {
        final d = json.decode(e.body);
        if (e.statusCode == 400 && d is Map) fields = d.map((k, v) => MapEntry('$k', '${v is List && v.isNotEmpty ? v.first : v}'));
      } catch (_) {}
      if (mounted) setState(() => fields.isEmpty ? _failure = e.message : _errors = fields);
    } catch (e) {
      if (mounted) setState(() => _failure = 'L’adresse n’a pas pu être enregistrée.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    return DashPage(
      title: widget.initial == null ? 'Nouvelle adresse' : 'Modifier l’adresse',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s8),
        children: [
          TratraInput(label: 'Rechercher une adresse', hint: 'Rue, quartier, repère…', controller: _query, onChanged: _onQuery, leadingIcon: Icons.search),
          if (_manual) Padding(padding: const EdgeInsets.only(top: TtSpace.s2), child: Text('Recherche indisponible : saisissez l’adresse dans les champs ci-dessous.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
          for (final s in _options)
            ListTile(dense: true, leading: const Icon(Icons.place_outlined, color: TtColors.primary), title: Text('${s['label']}', maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => _apply(s, 'geocoder')),
          const SizedBox(height: TtSpace.s3),
          TratraCard(
            variant: TratraCardVariant.soft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _consent,
                onChanged: _busy ? null : (v) => setState(() => _consent = v ?? false),
                title: const Text('J’autorise Tratra à utiliser ma position une seule fois pour renseigner cette adresse. Aucun suivi n’est activé.'),
              ),
              Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
                TratraButton(label: 'Utiliser ma position actuelle', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, leading: const Icon(Icons.my_location, size: 18), onPressed: _busy || !_consent ? null : _useMyPosition),
                TratraButton(label: _showMap ? 'Masquer la carte' : 'Choisir sur la carte', size: TratraButtonSize.sm, variant: TratraButtonVariant.outline, leading: const Icon(Icons.map_outlined, size: 18), onPressed: () => setState(() => _showMap = !_showMap)),
              ]),
            ]),
          ),
          if (_showMap) ...[
            const SizedBox(height: TtSpace.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(TtRadius.panel),
              child: SizedBox(
                height: 260,
                child: FlutterMap(
                  options: MapOptions(initialCenter: point ?? const LatLng(5.36, -4.0083), initialZoom: point == null ? 12 : 16, onTap: (_, p) => _onMapTap(p)),
                  children: [
                    TileLayer(urlTemplate: kMapTiles, userAgentPackageName: 'net.tratra.app'),
                    if (point != null)
                      MarkerLayer(markers: [
                        Marker(point: point, width: 24, height: 24, child: Container(decoration: BoxDecoration(color: TtColors.primary, shape: BoxShape.circle, border: Border.all(color: TtColors.accent, width: 4)))),
                      ]),
                    const RichAttributionWidget(attributions: [TextSourceAttribution('© contributeurs OpenStreetMap')]),
                  ],
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.only(top: TtSpace.s1), child: Text('Touchez le lieu exact.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft))),
          ],
          if (point != null)
            Padding(
              padding: const EdgeInsets.only(top: TtSpace.s2),
              child: Text('Point enregistré pour le calcul du déplacement. Il n’est jamais montré aux autres comptes.', style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
            ),
          const SizedBox(height: TtSpace.s3),
          TratraInput(label: 'Nom de l’adresse', hint: 'Maison, bureau…', controller: _label),
          const SizedBox(height: TtSpace.s3),
          TratraInput(label: 'Pays', controller: _country, errorText: _errors['country']),
          const SizedBox(height: TtSpace.s3),
          TratraInput(label: 'Ville', controller: _city, required: true, errorText: _errors['city']),
          const SizedBox(height: TtSpace.s3),
          TratraInput(label: 'Commune / quartier', controller: _commune, errorText: _errors['commune']),
          const SizedBox(height: TtSpace.s3),
          TratraInput(label: 'Rue / localisation', controller: _street, errorText: _errors['street']),
          const SizedBox(height: TtSpace.s3),
          TratraInput(label: 'Complément d’adresse', hint: 'Bâtiment, étage, porte…', controller: _complement),
          if (widget.initial == null)
            CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: _primary, onChanged: (v) => setState(() => _primary = v ?? false), title: const Text('Définir comme adresse principale')),
          if (_errors['location_consent'] != null) Padding(padding: const EdgeInsets.only(top: TtSpace.s2), child: TratraAlert(tone: TratraAlertTone.danger, message: _errors['location_consent']!)),
          if (_errors['detail'] != null) Padding(padding: const EdgeInsets.only(top: TtSpace.s2), child: TratraAlert(tone: TratraAlertTone.danger, message: _errors['detail']!)),
          if (_failure != null) Padding(padding: const EdgeInsets.only(top: TtSpace.s2), child: TratraAlert(tone: TratraAlertTone.danger, message: _failure!)),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: TtSpace.s2), child: TratraAlert(tone: TratraAlertTone.info, message: _info!)),
          const SizedBox(height: TtSpace.s4),
          TratraButton(label: 'Enregistrer', block: true, loading: _busy, onPressed: _busy ? null : _save),
        ],
      ),
    );
  }
}
