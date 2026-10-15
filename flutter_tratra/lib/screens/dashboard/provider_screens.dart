// lib/screens/dashboard/provider_screens.dart
//
// Parcours artisan d'un compte unique : devenir artisan (profil lié au compte courant),
// « Mes prestations » (services + accès aux missions/gains), nouveau service, profil pro.
// La publication reste soumise aux règles d'éligibilité du backend (KYC validé + profil complet).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/screens/dashboard/dash_nav.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/screens/worker/worker_home_screen.dart';

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

// ------------------------------------------------------------------ Mes prestations

class ProviderHubScreen extends StatefulWidget {
  const ProviderHubScreen({super.key});
  @override
  State<ProviderHubScreen> createState() => _ProviderHubScreenState();
}

class _ProviderHubScreenState extends State<ProviderHubScreen> {
  late final DashboardApi _api = context.read<DashboardApi>();
  int _version = 0;
  int? _toggling;

  Future<void> _toggle(Map<String, dynamic> s) async {
    final id = (s['id'] as num).toInt();
    setState(() => _toggling = id);
    try {
      await _api.patch('/services/$id/', {'is_active': s['is_active'] != true});
      if (!mounted) return;
      context.read<DashboardController>().load();
      setState(() => _version++);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Le service n’a pas pu être modifié.'), error: true);
    } finally {
      if (mounted) setState(() => _toggling = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DashboardController>().data?.provider;
    return DashPage(
      title: 'Mes prestations',
      body: ApiView<Map<String, dynamic>>(
        key: ValueKey('hub-$_version'),
        errorTitle: 'Prestations indisponibles',
        load: () => _api.getMap('/me/services/'),
        builder: (context, data, reload) {
          final services = ((data['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
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
                      Text('Missions, gains et abonnement', style: TratraTheme.style(TtType.title)),
                      Text('Acceptez vos missions, gérez votre disponibilité.', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
                ]),
              ),
              if (data['publishable'] != true) ...[
                const SizedBox(height: TtSpace.s3),
                TratraAlert(
                  tone: TratraAlertTone.info,
                  title: 'Vos services ne sont pas encore visibles',
                  message: 'Ils sont publiés dès que votre identité est vérifiée et votre profil complet.',
                  action: TextButton(onPressed: () => openProProfile(context), child: const Text('Voir ma progression')),
                ),
              ],
              TratraSectionHeader(
                title: 'Mes services',
                actionLabel: 'Ajouter',
                onAction: () async {
                  final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const NewServiceScreen()));
                  if (added == true && context.mounted) {
                    context.read<DashboardController>().load();
                    setState(() => _version++);
                  }
                },
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
              ),
              if (services.isEmpty)
                const SizedBox(
                  height: 220,
                  child: TratraEmptyState(
                    icon: Icons.add_business_outlined,
                    title: 'Aucun service pour le moment',
                    description: 'Ajoutez votre premier service pour être visible des clients.',
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

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.busy, required this.onToggle});
  final Map<String, dynamic> service;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = service['is_active'] == true;
    final published = service['published'] == true;
    final price = num.tryParse('${service['price']}');
    final priceLabel = switch (service['price_type']) {
      'quote' => 'Sur devis',
      'hourly' => price == null ? 'Sur devis' : '${formatFcfa(price)} / h',
      _ => price == null ? 'Sur devis' : formatFcfa(price),
    };
    final n = ((service['bookings_count'] ?? 0) as num).toInt();
    return TratraCard(
      padding: TratraCard.compact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${service['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
        const SizedBox(height: 2),
        Text('${service['category'] ?? '—'} · $priceLabel · $n réservation${n > 1 ? 's' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
        const SizedBox(height: TtSpace.s3),
        Row(children: [
          if (published)
            const TratraBadge('Publié', tone: TratraTone.success, dot: true)
          else if (active)
            const TratraBadge('En attente de validation', tone: TratraTone.accent, dot: true)
          else
            const TratraBadge('Désactivé', tone: TratraTone.gray, dot: true),
          const Spacer(),
          TratraButton(
            label: active ? 'Désactiver' : 'Activer',
            size: TratraButtonSize.sm,
            variant: TratraButtonVariant.outline,
            loading: busy,
            onPressed: onToggle,
          ),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ nouveau service

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
  List<Map<String, dynamic>> _categories = const [];
  String? _category;
  String _priceType = 'fixed';
  bool _busy = false;
  String? _error;
  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    _api.getList('/categories/?page_size=100&ordering=name').then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'La liste des métiers n’a pas pu être chargée.');
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final errs = <String, String>{};
    if (_title.text.trim().isEmpty) errs['title'] = 'Donnez un titre au service.';
    if (_category == null) errs['category'] = 'Choisissez un métier.';
    if (_description.text.trim().isEmpty) errs['description'] = 'Décrivez le service proposé.';
    if (_priceType != 'quote' && !((num.tryParse(_price.text) ?? 0) > 0)) errs['price'] = 'Indiquez un tarif supérieur à 0.';
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
    try {
      final duration = int.tryParse(_duration.text) ?? 0;
      await _api.post('/services/', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'category': int.parse(_category!),
        'price_type': _priceType,
        if (_priceType != 'quote') 'price': _price.text.trim(),
        if (duration > 0) 'duration': duration,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, 'Le service n’a pas pu être créé.');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DashPage(
      title: 'Nouveau service',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
        children: [
          Text('Il sera visible des clients dès que votre profil est complet et validé.', style: TratraTheme.style(TtType.bodySm, color: TtColors.ash)),
          const SizedBox(height: TtSpace.s4),
          TratraInput(controller: _title, label: 'Titre du service', required: true, maxLength: 120, errorText: _errors['title']),
          const SizedBox(height: TtSpace.s3),
          _LabeledDropdown<String>(
            label: 'Métier',
            required: true,
            value: _category,
            error: _errors['category'],
            items: [for (final c in _categories) DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: TtSpace.s3),
          TratraInput(controller: _description, label: 'Description', required: true, maxLines: 5, minLines: 4, errorText: _errors['description']),
          const SizedBox(height: TtSpace.s3),
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
          TratraButton(label: 'Créer le service', block: true, loading: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({required this.label, required this.value, required this.items, required this.onChanged, this.error, this.required = false});
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
  List<Map<String, dynamic>> _categories = const [];
  final _skills = <int>{};
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
      if (dash.data == null) await dash.load();
      final id = dash.data?.provider?.profileId;
      if (id == null) throw StateError('no profile');
      final results = await Future.wait([_api.getMap('/handymen/$id/'), _api.getList('/categories/?page_size=100&ordering=name')]);
      final p = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _profileId = id;
        _categories = results[1] as List<Map<String, dynamic>>;
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
                    if (p != null) _Progress(p: p, onKyc: () => openKyc(context)),
                    const SizedBox(height: TtSpace.s4),
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
                      for (final c in _categories)
                        TratraChip(
                          label: '${c['name']}',
                          selected: _skills.contains((c['id'] as num).toInt()),
                          onTap: () => setState(() {
                            final id = (c['id'] as num).toInt();
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

class _Progress extends StatelessWidget {
  const _Progress({required this.p, required this.onKyc});
  final DashProvider p;
  final VoidCallback onKyc;

  @override
  Widget build(BuildContext context) {
    final kyc = switch (p.kycStatus) {
      'approved' => ('Identité vérifiée', TratraTone.success),
      'pending' => ('Vérification en cours', TratraTone.accent),
      'rejected' => ('Document refusé', TratraTone.danger),
      _ => ('Aucun document déposé', TratraTone.gray),
    };
    return TratraCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Progression du dossier', style: TratraTheme.style(TtType.h3))),
          Text('${p.done}/${p.total}', style: TratraTheme.style(TtType.title, color: TtColors.primaryDark)),
        ]),
        const SizedBox(height: TtSpace.s2),
        ClipRRect(
          borderRadius: BorderRadius.circular(TtRadius.pill),
          child: LinearProgressIndicator(value: p.total == 0 ? 0 : p.done / p.total, minHeight: 8, backgroundColor: TtColors.lineSoft, color: TtColors.primary),
        ),
        const SizedBox(height: TtSpace.s3),
        for (final i in p.checklist)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(i.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 18, color: i.done ? TtColors.success : TtColors.fog),
              const SizedBox(width: TtSpace.s2),
              Expanded(child: Text(i.label, style: TratraTheme.style(TtType.bodySm, color: i.done ? TtColors.inkSoft : TtColors.ink))),
            ]),
          ),
        const SizedBox(height: TtSpace.s3),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TratraBadge(kyc.$1, tone: kyc.$2, dot: true),
            TextButton(onPressed: onKyc, child: const Text('Vérifier mon identité')),
          ],
        ),
        if (p.kycStatus == 'rejected' && p.kycReason != null)
          Text(p.kycReason!, style: TratraTheme.style(TtType.caption, color: TtColors.dangerInk)),
      ]),
    );
  }
}
