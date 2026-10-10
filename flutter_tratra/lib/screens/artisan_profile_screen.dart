// lib/screens/artisan_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/artisan.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/detail_shared/detail_helpers.dart';
import 'package:flutter_tratra/screens/detail_shared/service_mini_card.dart';
import 'package:flutter_tratra/screens/service_detail_screen.dart';
import 'package:flutter_tratra/screens/trust/passport_screen.dart';

class ArtisanProfileScreen extends StatefulWidget {
  const ArtisanProfileScreen({
    super.key,
    this.artisanId,
    this.artisan, // alias pratique
  });

  /// Id de l’artisan. Peut être null/empty si on fournit directement [artisan].
  final String? artisanId;

  /// Artisan déjà chargé (optionnel). Si fourni, on l’utilise d’abord.
  final Artisan? artisan;

  @override
  State<ArtisanProfileScreen> createState() => _ArtisanProfileScreenState();
}

class _ArtisanProfileScreenState extends State<ArtisanProfileScreen> {
  late final BaseApi _api;

  String?
      _artisanId; // résolu à partir de widget.artisanId ou widget.artisan?.id
  Artisan? _artisan;

  // chargement artisan
  bool _loadingInfo = true;
  String? _errorInfo;

  // services
  bool _loadingServices = true;
  String? _errorServices;
  List<Service> _services = [];

  bool get _missingId => _artisanId == null || _artisanId!.isEmpty;

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();

    _artisan = widget.artisan;
    _artisanId = (widget.artisanId != null &&
            widget.artisanId!.trim().isNotEmpty)
        ? widget.artisanId!.trim()
        : (widget.artisan?.id.isNotEmpty == true ? widget.artisan!.id : null);

    _loadAll();
  }

  Future<void> _loadAll() async {
    // Si pas d’id, on ne tente pas l’appel.
    if (_artisanId == null || _artisanId!.isEmpty) {
      setState(() {
        _loadingInfo = false;
        _loadingServices = false;
        _errorInfo ??= "Identifiant artisan manquant";
      });
      return;
    }
    await Future.wait([_loadInfo(), _loadServices()]);
  }

  // ---------- helpers ----------
  Future<http.Response> _getPublic(Uri uri) async {
    final c = _api.client;
    var r = await c.get(uri, headers: await _api.getHeaders(withAuth: true));
    if (r.statusCode == 401) {
      r = await c.get(uri, headers: await _api.getHeaders(withAuth: false));
    }
    return r;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Artisan _artisanFromBackend(Map<String, dynamic> j) {
    // Mapping tolérant : accepte les clés historiques de l'écran ET celles de la
    // carte publique du backend (display_name, photo, online, is_verified, skills…).
    final rawSpecialties = j['specialties'] ?? j['skills'];
    return Artisan(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? j['full_name'] ?? j['display_name'] ?? '').toString(),
      profession: (j['profession'] ?? j['specialty'] ?? '').toString(),
      rating: _toDouble(j['rating'] ?? j['rating_avg']),
      reviews: _toInt(j['reviews'] ?? j['review_count']),
      imageUrl: (j['imageUrl'] ??
              j['image_url'] ??
              j['avatar'] ??
              j['photo'] ??
              '')
          .toString(),
      distance: _toDouble(j['distance']),
      isAvailable:
          (j['isAvailable'] ?? j['is_available'] ?? j['online'] ?? false) ==
              true,
      hourlyRate: _toDouble(j['hourlyRate'] ?? j['hourly_rate']),
      isCertified: (j['isCertified'] ??
              j['is_certified'] ??
              j['is_verified'] ??
              false) ==
          true,
      responseTime: (j['responseTime'] ?? j['response_time'])?.toString(),
      yearsExperience: _toInt(
          j['yearsExperience'] ?? j['years_experience'] ?? j['experience_years']),
      specialties: (rawSpecialties is List)
          ? rawSpecialties
              .map((e) => e is Map ? (e['name'] ?? '').toString() : '$e')
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[],
      description: (j['description'] ?? j['bio'] ?? '').toString(),
      trustBadges: trustBadgeCodes(j['badges']),
      trustScore: j['trust_score'] is num ? (j['trust_score'] as num).round() : null,
    );
  }

  Future<void> _loadInfo() async {
    setState(() {
      _loadingInfo = true;
      _errorInfo = null;
    });

    try {
      final uri = Uri.parse(
        '${_api.baseUrl}${AppConstants.artisansEndpoint}/$_artisanId/',
      );

      final r = await _getPublic(uri);
      if (r.statusCode != 200) _api.handleError(r);

      final body = _api.decodeBody(r);
      final m =
          (body is Map) ? Map<String, dynamic>.from(body) : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _artisan = _artisanFromBackend(m);
        _loadingInfo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorInfo = friendlyError(e);
        _loadingInfo = false;
      });
    }
  }

  Service _serviceFromBackend(dynamic json) =>
      Service.fromJson(Map<String, dynamic>.from(json as Map));

  Future<void> _loadServices() async {
    setState(() {
      _loadingServices = true;
      _errorServices = null;
    });

    try {
      final qp = <String, String>{
        'is_active': 'true',
        'page_size': '30',
        if (_artisanId != null && _artisanId!.isNotEmpty)
          'handyman': _artisanId!,
        'ordering': '-created_at',
      };
      final uri = Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/')
          .replace(queryParameters: qp);

      final r = await _getPublic(uri);
      if (r.statusCode != 200) _api.handleError(r);

      final decoded = _api.decodeBody(r);
      final list = _api.extractResults(decoded);
      final items = list.map<Service>(_serviceFromBackend).toList();

      if (!mounted) return;
      setState(() {
        _services = items;
        _loadingServices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorServices = friendlyError(e);
        _loadingServices = false;
      });
    }
  }

  // ---------- navigation ----------
  void _contact(Artisan a, String name) {
    Navigator.pushNamed(
      context,
      RouteNames.messaging,
      arguments: MessagingArgs(artisanName: name, artisanImage: a.imageUrl),
    );
  }

  void _openService(Service s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceDetailScreen(service: s),
      ),
    );
  }

  void _browseServices() {
    Navigator.pushNamed(context, RouteNames.allServices);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final a = _artisan;
    final name = (a?.name ?? '').isNotEmpty ? a!.name : 'Artisan';

    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Profil artisan'),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: TtColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s4, TtSpace.s4, TtSpace.s8),
          children: [
            // Profil déjà affiché mais non actualisable : on le dit clairement.
            if (a != null && (_missingId || _errorInfo != null)) ...[
              TratraAlert(
                tone: TratraAlertTone.danger,
                title: _missingId ? 'Profil non actualisable' : 'Profil non actualisé',
                message: _missingId
                    ? 'Identifiant artisan manquant : ce profil ne peut pas être mis à jour.'
                    : _errorInfo!,
                action: _missingId
                    ? null
                    : TratraButton(
                        label: 'Réessayer',
                        size: TratraButtonSize.sm,
                        variant: TratraButtonVariant.outline,
                        onPressed: _loadInfo,
                      ),
              ),
              const SizedBox(height: TtSpace.s4),
            ],

            // En-tête
            if (a != null)
              _ProfileHeader(
                artisan: a,
                name: name,
                onContact: () => _contact(a, name),
              )
            else if (_loadingInfo)
              const _HeaderSkeleton()
            else
              TratraCard(
                variant: TratraCardVariant.flat,
                padding: EdgeInsets.zero,
                child: TratraEmptyState(
                  compact: true,
                  icon: Icons.person_off_outlined,
                  title: 'Profil indisponible',
                  description: _missingId
                      ? 'Identifiant artisan manquant : impossible d’afficher ce profil.'
                      : (_errorInfo ?? 'Les informations de cet artisan n’ont pas pu être chargées.'),
                  actions: [
                    if (!_missingId)
                      TratraButton(
                        label: 'Réessayer',
                        variant: TratraButtonVariant.soft,
                        onPressed: _loadInfo,
                      ),
                    TratraButton(
                      label: 'Parcourir les services',
                      variant: TratraButtonVariant.outline,
                      onPressed: _browseServices,
                    ),
                  ],
                ),
              ),

            if (a != null) ..._buildDetails(a),

            // Services proposés
            if (!_missingId) ...[
              const TratraSectionHeader(
                title: 'Services proposés',
                padding: EdgeInsets.fromLTRB(0, TtSpace.s8, 0, TtSpace.s3),
              ),
              _buildServices(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDetails(Artisan a) {
    final facts = <({IconData icon, String label, String value})>[
      if (a.hourlyRate > 0)
        (
          icon: Icons.payments_outlined,
          label: 'Tarif horaire',
          value: '${groupDigits(a.hourlyRate.toStringAsFixed(0))} FCFA/h',
        ),
      if (a.yearsExperience > 0)
        (
          icon: Icons.workspace_premium_outlined,
          label: 'Expérience',
          value: '${a.yearsExperience} an${a.yearsExperience > 1 ? "s" : ""}',
        ),
      if ((a.responseTime ?? '').isNotEmpty)
        (
          icon: Icons.schedule_outlined,
          label: 'Temps de réponse',
          value: a.responseTime!,
        ),
      if (a.distance > 0)
        (
          icon: Icons.place_outlined,
          label: 'Distance',
          value: '${a.distance.toStringAsFixed(1).replaceAll('.', ',')} km',
        ),
    ];

    return [
      if (facts.isNotEmpty) ...[
        const SizedBox(height: TtSpace.s4),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = (constraints.maxWidth - TtSpace.s3) / 2;
            return Wrap(
              spacing: TtSpace.s3,
              runSpacing: TtSpace.s3,
              children: [
                for (final f in facts)
                  SizedBox(
                    width: w,
                    child: _FactTile(icon: f.icon, label: f.label, value: f.value),
                  ),
              ],
            );
          },
        ),
      ],

      // Passeport de confiance (Tratra Trust) : badges, score expliqué, avis, historique.
      if (!_missingId) ...[
        const SizedBox(height: TtSpace.s4),
        TratraCard(
          padding: TratraCard.compact,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PassportScreen(profileId: _artisanId!)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: BorderRadius.circular(TtRadius.control)),
              child: const Icon(Icons.badge_outlined, color: TtColors.primary),
            ),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Passeport de confiance', style: TratraTheme.style(TtType.title)),
                Text(
                  a.trustScore != null ? 'Score ${a.trustScore}/100 · badges, compétences et avis' : 'Identité, badges, compétences et avis réels',
                  style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
          ]),
        ),
      ],

      // Spécialités
      if (a.specialties.isNotEmpty) ...[
        const TratraSectionHeader(
          title: 'Spécialités',
          padding: EdgeInsets.fromLTRB(0, TtSpace.s8, 0, TtSpace.s3),
        ),
        Wrap(
          spacing: TtSpace.s2,
          runSpacing: TtSpace.s2,
          children: [
            for (final s in a.specialties) TratraBadge(s, tone: TratraTone.primary),
          ],
        ),
      ],

      // À propos
      if (a.description.isNotEmpty) ...[
        const TratraSectionHeader(
          title: 'À propos',
          padding: EdgeInsets.fromLTRB(0, TtSpace.s8, 0, TtSpace.s3),
        ),
        TratraCard(
          padding: const EdgeInsets.all(TtSpace.s5),
          child: Text(
            a.description,
            style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
          ),
        ),
      ],
    ];
  }

  Widget _buildServices(BuildContext context) {
    if (_loadingServices) {
      return const TratraSkeletonList(count: 2, padding: EdgeInsets.zero);
    }

    if (_errorServices != null) {
      return TratraAlert(
        tone: TratraAlertTone.danger,
        title: 'Services indisponibles',
        message: _errorServices!,
        action: TratraButton(
          label: 'Réessayer',
          size: TratraButtonSize.sm,
          variant: TratraButtonVariant.outline,
          onPressed: _loadServices,
        ),
      );
    }

    if (_services.isEmpty) {
      return TratraCard(
        variant: TratraCardVariant.flat,
        padding: EdgeInsets.zero,
        child: TratraEmptyState(
          compact: true,
          icon: Icons.handyman_outlined,
          title: 'Aucun service pour le moment',
          description: 'Cet artisan n’a pas de service actif actuellement.',
          actions: [
            TratraButton(
              label: 'Parcourir les services',
              variant: TratraButtonVariant.soft,
              onPressed: _browseServices,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      itemCount: _services.length,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: TtSpace.s3,
        crossAxisSpacing: TtSpace.s3,
        mainAxisExtent: ServiceMiniCard.extentFor(context),
      ),
      itemBuilder: (_, i) {
        final s = _services[i];
        return ServiceMiniCard(service: s, onTap: () => _openService(s));
      },
    );
  }
}

/// Carte d'identité sur fond night : photo réelle ou initiales, note si elle existe,
/// pastilles « Vérifié » / « Disponible » uniquement quand le modèle les indique.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.artisan, required this.name, required this.onContact});

  final Artisan artisan;
  final String name;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final a = artisan;
    final hasBadges = a.isCertified || a.isAvailable || a.trustBadges.isNotEmpty;

    return TratraCard(
      variant: TratraCardVariant.night,
      padding: const EdgeInsets.all(TtSpace.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TratraAvatar(name: name, photoUrl: realImageUrl(a.imageUrl), size: 76),
              const SizedBox(width: TtSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.h2, color: Colors.white),
                      ),
                    ),
                    if (a.profession.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          a.profession,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.bodySm, color: Colors.white70),
                        ),
                      ),
                    if (a.rating > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: TtSpace.s2),
                        child: RatingStars(rating: a.rating, reviewCount: a.reviews, onDark: true),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (hasBadges) ...[
            const SizedBox(height: TtSpace.s4),
            Wrap(
              spacing: TtSpace.s2,
              runSpacing: TtSpace.s2,
              children: [
                if (a.trustBadges.isNotEmpty)
                  TratraTrustBadges(a.trustBadges, onNight: true)
                else if (a.isCertified)
                  const TratraBadge('Vérifié', tone: TratraTone.success, icon: Icons.verified_rounded),
                if (a.isAvailable)
                  const TratraBadge('Disponible', tone: TratraTone.primary, dot: true),
              ],
            ),
          ],
          const SizedBox(height: TtSpace.s5),
          TratraButton(
            label: 'Contacter',
            variant: TratraButtonVariant.accent,
            block: true,
            leading: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: onContact,
          ),
        ],
      ),
    );
  }
}

/// Tuile d'information (libellé + valeur).
class _FactTile extends StatelessWidget {
  const _FactTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      variant: TratraCardVariant.flat,
      radius: TtRadius.panel,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: TtColors.primary),
          const SizedBox(height: TtSpace.s2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TratraTheme.style(TtType.caption, color: TtColors.ash),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TratraTheme.style(TtType.title).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Chargement de l'en-tête (une seule animation partagée).
class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement du profil',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraCard(
          variant: TratraCardVariant.flat,
          padding: const EdgeInsets.all(TtSpace.s5),
          child: TratraShimmer(
            child: Row(
              children: [
                const TratraSkeletonBox(height: 76, circle: true),
                const SizedBox(width: TtSpace.s4),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TratraSkeletonBox(height: 18),
                      SizedBox(height: 10),
                      TratraSkeletonBox(width: 120, height: 14),
                      SizedBox(height: 10),
                      TratraSkeletonBox(width: 90, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
