// lib/screens/dashboard/provider_screens.dart
//
// Parcours artisan d'un compte unique : devenir artisan (profil lié au compte courant), « Mes offres » (offres + accès aux missions),
// nouvelle offre (métier → prestation du catalogue commun → description → tarif), profil pro. Publication, identité et blocages viennent
// du serveur (handy/eligibility.py) : aucune règle ici.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/dashboard/eligibility_panel.dart';
import 'package:flutter_tratra/screens/worker/worker_home_screen.dart';
import 'package:flutter_tratra/services/catalog_repository.dart';

// ------------------------------------------------------------------ devenir artisan

class ProvideScreen extends StatefulWidget {
  const ProvideScreen({super.key});
  @override
  State<ProvideScreen> createState() => _ProvideScreenState();
}

class _ProvideScreenState extends State<ProvideScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<DashboardApi>();
    final dash = context.read<DashboardController>();
    final nav = Navigator.of(context);
    try {
      // Profil lié au compte courant (idempotent) : jamais un second compte.
      await api.post('/me/handyman-profile/');
      await dash.load();
      if (!mounted) return;
      nav.pushReplacement(MaterialPageRoute(builder: (_) => const ProProfileScreen()));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'Le profil n’a pas pu être créé.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final already = context.watch<DashboardController>().data?.isProvider ?? false;
    const steps = [
      ('1', 'Complétez votre profil', 'Présentation, spécialités, expérience, zone d’intervention et photo.'),
      ('2', 'Faites vérifier votre identité', 'Déposez votre pièce d’identité : elle est contrôlée par l’équipe Tratra.'),
      ('3', 'Publiez vos services', 'Vos services deviennent visibles et vous recevez des missions une fois votre dossier validé.'),
    ];
    return DashPage(
      title: 'Proposer un service',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
        children: [
          Text('Devenez artisan avec votre compte actuel', style: TratraTheme.style(TtType.h1)),
          const SizedBox(height: TtSpace.s2),
          Text('Aucun nouveau compte : vous gardez vos réservations et vos messages.',
              style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: TtSpace.s5),
          for (final s in steps) ...[
            TratraCard(
              padding: TratraCard.compact,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 16, backgroundColor: TtColors.primarySoft, child: Text(s.$1, style: const TextStyle(color: TtColors.primaryDark, fontWeight: FontWeight.w700))),
                const SizedBox(width: TtSpace.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.$2, style: TratraTheme.style(TtType.title)),
                    Text(s.$3, style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: TtSpace.s2),
          ],
          if (_error != null) ...[const SizedBox(height: TtSpace.s2), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
          const SizedBox(height: TtSpace.s4),
          if (already)
            TratraButton(label: 'Gérer mes prestations', block: true, onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProviderHubScreen())))
          else
            TratraButton(label: 'Créer mon profil professionnel', block: true, loading: _busy, onPressed: _create),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Mes offres

class ProviderHubScreen extends StatefulWidget {
  const ProviderHubScreen({super.key});
  @override
  State<ProviderHubScreen> createState() => _ProviderHubScreenState();
}

class _ProviderHubScreenState extends State<ProviderHubScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;
  int? _toggling;

  void _refresh() {
    context.read<DashboardController>().load();
    setState(() => _version++);
  }

  Future<void> _toggle(Map<String, dynamic> s) async {
    final id = (s['id'] as num).toInt();
    setState(() => _toggling = id);
    try {
      await _api.patch('/services/$id/', {'is_active': s['is_active'] != true});
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'L’offre n’a pas pu être modifiée.'), error: true);
    } finally {
      if (mounted) setState(() => _toggling = null);
    }
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewServiceScreen()));
    if (added == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DashboardController>().data?.provider;
    return DashPage(
      title: 'Mes offres',
      body: ApiView<Map<String, dynamic>>(
        key: ValueKey('hub-$_version'),
        errorTitle: 'Offres indisponibles',
        load: () => _api.getMap('/me/services/'),
        builder: (context, data, reload) {
          final services = ((data['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          final eligibility = data['eligibility'] is Map ? DashEligibility((data['eligibility'] as Map).cast<String, dynamic>()) : null;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (p != null) ...[
                DashKpi(icon: Icons.handyman_outlined, tone: TratraTone.accent, label: 'Missions à traiter', value: '${p.pending}', hint: '${p.confirmed + p.inProgress} à venir'),
                if (AppConstants.financialFeaturesEnabled) ...[
                  const SizedBox(height: TtSpace.s2),
                  DashKpi(icon: Icons.account_balance_wallet_outlined, tone: TratraTone.night, label: 'Gains disponibles', value: fcfaOrZero(p.earnings), onTap: () => openWallet(context)),
                ],
                const SizedBox(height: TtSpace.s3),
              ],
              TratraCard(
                padding: TratraCard.compact,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkerHomeScreen())),
                child: Row(children: [
                  const Icon(Icons.assignment_outlined, color: TtColors.primary),
                  const SizedBox(width: TtSpace.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Mes missions', style: TratraTheme.style(TtType.title)),
                      Text('Acceptez vos missions, gérez votre disponibilité.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
                ]),
              ),
              if (eligibility != null) ...[
                const SizedBox(height: TtSpace.s3),
                _PublicationBanner(eligibility: eligibility, onChanged: _refresh),
              ],
              TratraSectionHeader(
                title: 'Mes offres',
                subtitle: eligibility?.offersLabel,
                actionLabel: 'Ajouter',
                onAction: _add,
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
              ),
              if (services.isEmpty)
                TratraCard(
                  child: TratraEmptyState(
                    compact: true,
                    icon: Icons.add_business_outlined,
                    title: 'Aucune offre pour le moment',
                    description: 'Choisissez un métier et une prestation du catalogue, décrivez votre offre et votre tarif.',
                    actions: [TratraButton(key: const ValueKey('hub-add-first'), label: 'Créer ma première offre', leading: const Icon(Icons.add_rounded), onPressed: _add)],
                  ),
                )
              else
                for (final s in services) ...[
                  _ServiceRow(service: s, busy: _toggling == (s['id'] as num).toInt(), onToggle: () => _toggle(s)),
                  const SizedBox(height: TtSpace.s2),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// Publication autorisée ou non, avec les blocages réels (serveur) et l'action qui lève le premier.
class _PublicationBanner extends StatelessWidget {
  const _PublicationBanner({required this.eligibility, required this.onChanged});
  final DashEligibility eligibility;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final e = eligibility;
    if (e.authorized) {
      return const TratraAlert(key: ValueKey('hub-authorized'), tone: TratraAlertTone.success, title: 'Publication autorisée',
          message: 'Vos offres actives sont visibles des clients.');
    }
    final action = e.blockers.map((b) => b.action).whereType<DashActionRef>().firstOrNull;
    return TratraAlert(
      key: const ValueKey('hub-blocked'),
      tone: TratraAlertTone.info,
      title: 'Vos offres ne sont pas encore visibles',
      message: e.blockers.map((b) => '• ${b.label}').join('\n'),
      action: Wrap(spacing: TtSpace.s2, children: [
        if (action != null) TextButton(onPressed: () => runEligibilityAction(context, action, onChanged: onChanged), child: Text(action.label)),
        TextButton(onPressed: () => openProProfile(context), child: const Text('Voir le détail')),
      ]),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.busy, required this.onToggle});
  final Map<String, dynamic> service;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = service['is_active'] == true;
    final pub = service['publication'] is Map ? (service['publication'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final state = '${pub['state'] ?? (service['published'] == true ? 'published' : active ? 'waiting' : 'inactive')}';
    final price = num.tryParse('${service['price']}');
    final priceLabel = switch (service['price_type']) {
      'quote' => 'Sur devis',
      'hourly' => price == null ? 'Sur devis' : '${formatFcfa(price)} / h',
      _ => price == null ? 'Sur devis' : formatFcfa(price),
    };
    final n = ((service['bookings_count'] ?? 0) as num).toInt();
    final where = [if (service['trade'] != null) '${service['trade']}', '${service['category'] ?? '—'}'].join(' › ');
    final (label, tone) = switch (state) {
      'published' => ('${pub['label'] ?? 'Publiée'}', TratraTone.success),
      'waiting' => ('${pub['label'] ?? 'En attente d’autorisation'}', TratraTone.accent),
      _ => ('${pub['label'] ?? 'Désactivée'}', TratraTone.gray),
    };
    return TratraCard(
      key: ValueKey('service-${service['id']}'),
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${service['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
        const SizedBox(height: 2),
        Text('$where · $priceLabel · $n réservation${n > 1 ? 's' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s3),
        Wrap(
          spacing: TtSpace.s2,
          runSpacing: TtSpace.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            TratraBadge(label, tone: tone, dot: true),
            TratraButton(
              label: active ? 'Désactiver' : 'Activer',
              size: TratraButtonSize.sm,
              variant: TratraButtonVariant.outline,
              loading: busy,
              onPressed: onToggle,
            ),
          ],
        ),
        if (pub['hint'] != null) ...[
          const SizedBox(height: TtSpace.s2),
          Text('${pub['hint']}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------------ nouvelle offre : métier → prestation → description → tarif

class NewServiceScreen extends StatefulWidget {
  const NewServiceScreen({super.key});
  @override
  State<NewServiceScreen> createState() => _NewServiceScreenState();
}

class _NewServiceScreenState extends State<NewServiceScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _duration = TextEditingController();
  Catalog? _catalog;
  String? _trade;
  String? _prestation;
  String _priceType = 'fixed';
  bool _busy = false;
  bool _titleTouched = false;
  String? _error;
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() => _error = null);
    try {
      final c = await CatalogRepository.shared(context.read<BaseApi>()).load();
      if (mounted) setState(() => _catalog = c);
    } catch (_) {
      if (mounted) setState(() => _error = 'Le catalogue des métiers n’a pas pu être chargé. Vérifiez votre connexion.');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  /// Catégorie enregistrée : la prestation choisie, sinon le métier lui-même (métier sans prestation).
  String? get _categoryId => _prestation ?? _trade;

  void _onPrestation(String? id) {
    setState(() {
      _prestation = id;
      final name = id == null ? null : _catalog?.byId(id)?.name;
      if (!_titleTouched && name != null) _title.text = name;   // titre proposé, modifiable
    });
  }

  Future<void> _submit() async {
    final prestations = _trade == null ? const <Category>[] : _catalog!.prestationsOf(_trade!);
    final errs = <String, String>{
      if (_trade == null) 'trade': 'Choisissez votre métier.',
      if (_trade != null && prestations.isNotEmpty && _prestation == null) 'prestation': 'Choisissez la prestation proposée.',
      if (_title.text.trim().isEmpty) 'title': 'Donnez un titre à votre offre.',
      if (_description.text.trim().length < 10) 'description': 'Décrivez votre offre (au moins 10 caractères).',
      if (_priceType != 'quote' && !((num.tryParse(_price.text) ?? 0) > 0)) 'price': 'Indiquez un tarif supérieur à 0.',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errs);
    });
    if (errs.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final dash = context.read<DashboardController>();
    try {
      final duration = int.tryParse(_duration.text) ?? 0;
      await _api.post('/services/', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'category': int.parse(_categoryId!),
        'price_type': _priceType,
        if (_priceType != 'quote') 'price': _price.text.trim(),
        if (duration > 0) 'duration': duration,
      });
      await dash.load();
      if (!mounted) return;
      final published = dash.data?.provider?.eligibility?.authorized ?? dash.data?.provider?.publishable ?? false;
      showMessage(context, published ? 'Offre créée et publiée.' : 'Offre créée : elle sera publiée dès que votre publication sera autorisée.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'L’offre n’a pas pu être créée.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final e = context.watch<DashboardController>().data?.provider?.eligibility;
    final prestations = catalog == null || _trade == null ? const <Category>[] : catalog.prestationsOf(_trade!);
    return DashPage(
      title: 'Nouvelle offre',
      body: catalog == null && _error == null
          ? const TratraSkeletonList(count: 3)
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (e != null && !e.authorized)
                  const Padding(
                    padding: EdgeInsets.only(bottom: TtSpace.s3),
                    child: TratraAlert(
                      key: ValueKey('new-waiting'),
                      tone: TratraAlertTone.info,
                      message: 'Votre offre sera enregistrée tout de suite et publiée automatiquement dès que votre publication sera autorisée.',
                    ),
                  ),
                if (catalog == null) ...[
                  TratraAlert(tone: TratraAlertTone.danger, message: _error!),
                  const SizedBox(height: TtSpace.s3),
                  TratraButton(label: 'Réessayer', variant: TratraButtonVariant.outline, onPressed: _loadCatalog),
                ] else ...[
                  _StepLabel(n: 1, text: 'Votre métier'),
                  _LabeledDropdown<String>(
                    key: const ValueKey('new-trade'),
                    label: 'Métier',
                    required: true,
                    value: _trade,
                    error: _errors['trade'],
                    items: [for (final t in catalog.trades) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() {
                      _trade = v;
                      _prestation = null;
                    }),
                  ),
                  if (_trade != null && prestations.isNotEmpty) ...[
                    const SizedBox(height: TtSpace.s4),
                    _StepLabel(n: 2, text: 'La prestation proposée'),
                    _LabeledDropdown<String>(
                      key: ValueKey('new-prestation-$_trade'),
                      label: 'Prestation',
                      required: true,
                      value: _prestation,
                      error: _errors['prestation'],
                      items: [for (final c in prestations) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                      onChanged: _onPrestation,
                    ),
                  ],
                  const SizedBox(height: TtSpace.s4),
                  _StepLabel(n: prestations.isEmpty ? 2 : 3, text: 'Description'),
                  TratraInput(
                    controller: _title,
                    label: 'Titre de l’offre',
                    required: true,
                    maxLength: 120,
                    errorText: _errors['title'],
                    onChanged: (_) => _titleTouched = true,
                  ),
                  const SizedBox(height: TtSpace.s3),
                  TratraInput(
                    controller: _description,
                    label: 'Description',
                    hint: 'Ce que comprend l’offre, votre matériel, vos délais…',
                    required: true,
                    maxLines: 5,
                    minLines: 3,
                    errorText: _errors['description'],
                  ),
                  const SizedBox(height: TtSpace.s4),
                  _StepLabel(n: prestations.isEmpty ? 3 : 4, text: 'Tarif'),
                  _LabeledDropdown<String>(
                    label: 'Type de tarif',
                    value: _priceType,
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('Forfait')),
                      DropdownMenuItem(value: 'hourly', child: Text('À l’heure')),
                      DropdownMenuItem(value: 'quote', child: Text('Sur devis')),
                    ],
                    onChanged: (v) => setState(() => _priceType = v ?? 'fixed'),
                  ),
                  if (_priceType != 'quote') ...[
                    const SizedBox(height: TtSpace.s3),
                    TratraInput(
                      controller: _price,
                      label: _priceType == 'hourly' ? 'Tarif horaire (FCFA)' : 'Tarif (FCFA)',
                      required: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      errorText: _errors['price'],
                    ),
                  ],
                  const SizedBox(height: TtSpace.s3),
                  TratraInput(controller: _duration, label: 'Durée estimée (minutes)', optional: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                  if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
                  const SizedBox(height: TtSpace.s5),
                  TratraButton(key: const ValueKey('new-submit'), label: 'Créer l’offre', block: true, loading: _busy, onPressed: _submit),
                ],
              ],
            ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: TtSpace.s2),
        child: Row(children: [
          CircleAvatar(radius: 11, backgroundColor: TtColors.primarySoft, child: Text('$n', style: const TextStyle(fontSize: 12, color: TtColors.primaryDark, fontWeight: FontWeight.w700))),
          const SizedBox(width: TtSpace.s2),
          Expanded(child: Text(text, style: TratraTheme.style(TtType.title))),
        ]),
      );
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.error, this.required = false});
  final String label;
  final bool required;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: label),
        if (required) const TextSpan(text: ' *', style: TextStyle(color: TtColors.danger)),
      ]), style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        isExpanded: true,
        onChanged: onChanged,
        decoration: InputDecoration(
          errorText: error,
          filled: true,
          fillColor: TtColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(TtRadius.control), borderSide: const BorderSide(color: TtColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(TtRadius.control), borderSide: const BorderSide(color: TtColors.line)),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ profil pro + KYC

class ProProfileScreen extends StatefulWidget {
  const ProProfileScreen({super.key});
  @override
  State<ProProfileScreen> createState() => _ProProfileScreenState();
}

class _ProProfileScreenState extends State<ProProfileScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  final _bio = TextEditingController();
  final _experience = TextEditingController();
  final _commune = TextEditingController();
  final _quartier = TextEditingController();
  final _rate = TextEditingController();
  List<Category> _trades = const [];
  final _skills = <int>{};
  final _formKey = GlobalKey();
  String? _photoUrl;
  XFile? _photo;
  bool _loading = true;
  bool _busy = false;
  bool _saved = false;
  String? _error;
  int? _profileId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_bio, _experience, _commune, _quartier, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dash = context.read<DashboardController>();
      final catalog = CatalogRepository.shared(context.read<BaseApi>());
      if (dash.data == null) await dash.load();
      final id = dash.data?.provider?.profileId;
      if (id == null) throw StateError('no profile');
      final results = await Future.wait<Object>([_api.getMap('/handymen/$id/'), catalog.load()]);
      final p = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _profileId = id;
        // Spécialités = métiers du catalogue commun (mêmes noms que le site) ; une spécialité déjà choisie hors de cette liste reste affichée.
        final c = results[1] as Catalog;
        final skillIds = ((p['skills'] as List?) ?? const []).whereType<num>().map((e) => '${e.toInt()}').toSet();
        _trades = [...c.trades, for (final x in c.items) if (!x.isTrade && skillIds.contains(x.id)) x];
        _bio.text = '${p['bio'] ?? ''}';
        _experience.text = (p['experience_years'] ?? 0) == 0 ? '' : '${p['experience_years']}';
        _commune.text = '${p['commune'] ?? ''}';
        _quartier.text = '${p['quartier'] ?? ''}';
        final rate = num.tryParse('${p['hourly_rate']}') ?? 0;
        _rate.text = rate > 0 ? '${rate.toInt()}' : '';
        _skills
          ..clear()
          ..addAll(((p['skills'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()));
        _photoUrl = p['photo'] == null ? null : '${p['photo']}';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'Votre profil professionnel ne peut pas être chargé.');
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (f != null && mounted) setState(() => _photo = f);
    } catch (_) {
      if (mounted) showMessage(context, 'La photo n’a pas pu être sélectionnée.', error: true);
    }
  }

  Future<void> _save() async {
    final id = _profileId;
    if (id == null) return;
    final dash = context.read<DashboardController>();
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await _api.patch('/handymen/$id/', {
        'bio': _bio.text.trim(),
        'experience_years': int.tryParse(_experience.text) ?? 0,
        'commune': _commune.text.trim(),
        'quartier': _quartier.text.trim(),
        'hourly_rate': _rate.text.isEmpty ? 0 : _rate.text,
        'skills': _skills.toList(),
      });
      if (_photo != null) {
        await _api.patchFile('/handymen/$id/', 'photo', _photo!.path);
        _photo = null;
      }
      await dash.load();
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, 'L’enregistrement a échoué. Vérifiez les champs et réessayez.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DashboardController>().data?.provider;
    return DashPage(
      title: 'Mon profil professionnel',
      body: _loading
          ? const TratraSkeletonList(count: 3)
          : _profileId == null
              ? TratraEmptyState(icon: Icons.person_off_outlined, title: 'Profil indisponible', description: _error)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
                  children: [
                    if (p?.eligibility != null)
                      EligibilityPanel(
                        eligibility: p!.eligibility!,
                        showOffers: true,
                        onEditProfile: () => Scrollable.ensureVisible(_formKey.currentContext!, duration: TtMotion.base),
                      ),
                    const SizedBox(height: TtSpace.s4),
                    Text('Mon profil', key: _formKey, style: TratraTheme.style(TtType.h3)),
                    const SizedBox(height: TtSpace.s3),
                    Row(children: [
                      TratraAvatar(name: context.read<DashboardController>().data?.displayName ?? 'Profil', photoUrl: _photoUrl, size: 64),
                      const SizedBox(width: TtSpace.s3),
                      Expanded(
                        child: TratraButton(
                          label: _photo == null ? 'Choisir une photo' : 'Photo sélectionnée ✓',
                          variant: TratraButtonVariant.outline,
                          leading: const Icon(Icons.photo_camera_outlined, size: 18),
                          onPressed: _pickPhoto,
                        ),
                      ),
                    ]),
                    const SizedBox(height: TtSpace.s4),
                    TratraInput(controller: _bio, label: 'Présentation', helper: 'Votre activité, votre expérience, ce qui vous distingue.', maxLines: 5, minLines: 4),
                    const SizedBox(height: TtSpace.s3),
                    Text('Spécialités', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: TtSpace.s2, runSpacing: TtSpace.s2, children: [
                      for (final c in _trades)
                        TratraChip(
                          label: c.name,
                          selected: _skills.contains(int.parse(c.id)),
                          onTap: () => setState(() {
                            final id = int.parse(c.id);
                            _skills.contains(id) ? _skills.remove(id) : _skills.add(id);
                            _saved = false;
                          }),
                        ),
                    ]),
                    const SizedBox(height: TtSpace.s3),
                    TratraInput(controller: _experience, label: 'Années d’expérience', keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                    const SizedBox(height: TtSpace.s3),
                    TratraInput(controller: _rate, label: 'Tarif horaire indicatif (FCFA)', optional: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                    const SizedBox(height: TtSpace.s3),
                    TratraInput(controller: _commune, label: 'Commune', hint: 'Ex. Cocody'),
                    const SizedBox(height: TtSpace.s3),
                    TratraInput(controller: _quartier, label: 'Quartier', optional: true),
                    if (_error != null) ...[const SizedBox(height: TtSpace.s3), TratraAlert(tone: TratraAlertTone.danger, message: _error!)],
                    if (_saved) ...[const SizedBox(height: TtSpace.s3), const TratraAlert(tone: TratraAlertTone.success, message: 'Profil enregistré.')],
                    const SizedBox(height: TtSpace.s4),
                    TratraButton(label: 'Enregistrer', block: true, loading: _busy, onPressed: _save),
                  ],
                ),
    );
  }
}
