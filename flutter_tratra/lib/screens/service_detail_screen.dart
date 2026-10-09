// lib/screens/service_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/artisan_profile_screen.dart';
import 'package:flutter_tratra/screens/detail_shared/detail_helpers.dart';
import 'package:flutter_tratra/screens/detail_shared/service_mini_card.dart';

class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.service});

  final Service service;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late final BaseApi _api;

  // Recommandations
  bool _loadingRecos = true;
  String? _errorRecos;
  List<Service> _similar = [];

  @override
  void initState() {
    super.initState();
    _api = context.read<BaseApi>();
    _loadSimilar();
  }

  // ---------- helpers réseau ----------
  Future<http.Response> _getPublic(Uri uri) async {
    final c = _api.client;
    var r = await c.get(uri, headers: await _api.getHeaders(withAuth: true));
    if (r.statusCode == 401) {
      r = await c.get(uri, headers: await _api.getHeaders(withAuth: false));
    }
    return r;
  }

  Service _serviceFromBackend(dynamic json) => Service.fromJson(
        Map<String, dynamic>.from(json as Map),
      );

  Future<void> _loadSimilar() async {
    setState(() {
      _loadingRecos = true;
      _errorRecos = null;
    });

    try {
      final qp = <String, String>{
        'is_active': 'true',
        'page_size': '10',
        'ordering': '-created_at',
        if (widget.service.categoryId.isNotEmpty)
          'category': widget.service.categoryId
        else if (widget.service.categoryName.isNotEmpty)
          'category__name': widget.service.categoryName,
        // si ton API supporte ?exclude=<id> tu peux l'ajouter ici
      };

      final uri = Uri.parse('${_api.baseUrl}${AppConstants.servicesEndpoint}/')
          .replace(queryParameters: qp);

      final r = await _getPublic(uri);
      if (r.statusCode != 200) _api.handleError(r);

      final decoded = _api.decodeBody(r);
      final results = _api.extractResults(decoded);
      final items = results.map<Service>(_serviceFromBackend).toList();

      if (!mounted) return;
      setState(() {
        _similar = items.where((s) => s.id != widget.service.id).toList();
        _loadingRecos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorRecos = friendlyError(e);
        _loadingRecos = false;
      });
    }
  }

  // ---------- navigation ----------
  void _book() {
    Navigator.pushNamed(
      context,
      RouteNames.booking,
      arguments: BookingArgs(widget.service),
    );
  }

  void _openArtisan() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtisanProfileScreen(
          artisanId: widget.service.handymanId,
        ),
      ),
    );
  }

  void _openSimilar(Service x) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceDetailScreen(service: x),
      ),
    );
  }

  // ---------- libellés ----------
  String? _pricingLabel(Service s) {
    if (s.isHourly) return 'Tarif horaire';
    if (s.isFixed) return 'Prix fixe';
    if (s.isQuoteBased) return 'Sur devis';
    return null;
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final s = widget.service;

    final cover = realImageUrl(s.imageUrl);
    final images = <String>{
      if (cover != null) cover,
      ...s.imageUrls.map(realImageUrl).whereType<String>(),
    }.toList();

    final pricing = _pricingLabel(s);
    final hasRating = (s.rating ?? 0) > 0;

    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Détail du service'),
      bottomNavigationBar: _BookingBar(price: formatServicePrice(s), onBook: _book),
      body: RefreshIndicator(
        onRefresh: _loadSimilar,
        color: TtColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: TtSpace.s6),
          children: [
            // Image principale (ou galerie) avec dégradé night discret
            _Hero(images: images, urgent: s.isUrgent),

            // Titre + note
            Padding(
              padding: const EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s5, TtSpace.s5, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.categoryName.isNotEmpty) ...[
                    _Eyebrow(label: s.categoryName),
                    const SizedBox(height: TtSpace.s3),
                  ],
                  Semantics(
                    header: true,
                    child: Text(s.title, style: TratraTheme.style(TtType.h1)),
                  ),
                  if (hasRating) ...[
                    const SizedBox(height: TtSpace.s3),
                    RatingStars(rating: s.rating!, reviewCount: s.reviewCount),
                  ],
                ],
              ),
            ),

            // Tarification + durée (uniquement les informations réellement connues)
            if (pricing != null || s.duration != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s5, TtSpace.s5, 0),
                // IntrinsicHeight : les deux tuiles gardent la même hauteur dans une
                // liste verticale (hauteur non bornée).
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (pricing != null)
                        Expanded(
                          child: _FactTile(
                            icon: Icons.payments_outlined,
                            label: 'Tarification',
                            value: pricing,
                          ),
                        ),
                      if (pricing != null && s.duration != null) const SizedBox(width: TtSpace.s3),
                      if (s.duration != null)
                        Expanded(
                          child: _FactTile(
                            icon: Icons.timer_outlined,
                            label: 'Durée',
                            value: s.durationDisplay,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Description
            if (s.description.trim().isNotEmpty) ...[
              const TratraSectionHeader(
                title: 'À propos de ce service',
                padding: EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s8, TtSpace.s5, TtSpace.s3),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: TtSpace.s5),
                child: Text(
                  s.description,
                  style: TratraTheme.style(TtType.body, color: TtColors.inkSoft),
                ),
              ),
            ],

            // Ce qui est inclus (liste fournie par le service)
            if (s.includedServices.isNotEmpty) ...[
              const TratraSectionHeader(
                title: 'Ce qui est inclus',
                padding: EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s8, TtSpace.s5, TtSpace.s3),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: TtSpace.s5),
                child: TratraCard(
                  padding: const EdgeInsets.all(TtSpace.s4),
                  child: Column(
                    children: [
                      for (final item in s.includedServices)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _Tick(),
                              const SizedBox(width: TtSpace.s3),
                              Expanded(
                                child: Text(item, style: TratraTheme.style(TtType.body)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            // L'artisan (uniquement si le service est rattaché à un artisan)
            if (s.handymanId.isNotEmpty) ...[
              const TratraSectionHeader(
                title: 'L’artisan',
                padding: EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s8, TtSpace.s5, TtSpace.s3),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: TtSpace.s5),
                child: TratraCard(
                  variant: TratraCardVariant.soft,
                  padding: const EdgeInsets.all(TtSpace.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Découvrez qui réalise ce service',
                        style: TratraTheme.style(TtType.title),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Présentation, spécialités et autres services de l’artisan.',
                        style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft),
                      ),
                      const SizedBox(height: TtSpace.s4),
                      TratraButton(
                        label: 'Voir l’artisan',
                        variant: TratraButtonVariant.outline,
                        block: true,
                        leading: const Icon(Icons.person_outline),
                        onPressed: _openArtisan,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Recommandations
            const TratraSectionHeader(
              title: 'Vous pourriez aussi aimer',
              padding: EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s8, TtSpace.s5, TtSpace.s3),
            ),
            _buildRecommendations(context),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    if (_loadingRecos) return const _SimilarSkeleton();

    if (_errorRecos != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s5),
        child: TratraAlert(
          tone: TratraAlertTone.danger,
          title: 'Services similaires indisponibles',
          message: _errorRecos!,
          action: TratraButton(
            label: 'Réessayer',
            size: TratraButtonSize.sm,
            variant: TratraButtonVariant.outline,
            onPressed: _loadSimilar,
          ),
        ),
      );
    }

    if (_similar.isEmpty) {
      return TratraEmptyState(
        compact: true,
        icon: Icons.explore_outlined,
        title: 'Aucun autre service pour le moment',
        description: 'Nous n’avons pas d’autre service à vous suggérer ici.',
        actions: [
          TratraButton(
            label: 'Parcourir les services',
            variant: TratraButtonVariant.soft,
            onPressed: () => Navigator.pushNamed(context, RouteNames.allServices),
          ),
        ],
      );
    }

    return SizedBox(
      height: ServiceMiniCard.extentFor(context),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: TtSpace.s5),
        scrollDirection: Axis.horizontal,
        itemCount: _similar.length,
        separatorBuilder: (_, __) => const SizedBox(width: TtSpace.s3),
        itemBuilder: (_, i) {
          final x = _similar[i];
          return SizedBox(
            width: 188,
            child: ServiceMiniCard(service: x, onTap: () => _openSimilar(x)),
          );
        },
      ),
    );
  }
}

/// En-tête image : photo(s) réelle(s) ou panneau de marque, dégradé night discret
/// en bas, pastille « Urgent » uniquement si le service l'indique.
class _Hero extends StatefulWidget {
  const _Hero({required this.images, required this.urgent});

  final List<String> images;
  final bool urgent;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final multi = images.length > 1;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(TtRadius.sheet)),
      child: SizedBox(
        height: 260,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const ServiceCover(url: null, iconSize: 56, dark: true)
            else
              Semantics(
                label: multi
                    ? 'Photos du service, ${_page + 1} sur ${images.length}'
                    : 'Photo du service',
                child: PageView.builder(
                  controller: _controller,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => ServiceCover(url: images[i]),
                ),
              ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1],
                    colors: [
                      TtColors.night.withValues(alpha: 0),
                      TtColors.night.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.urgent || multi)
              Positioned(
                left: TtSpace.s5,
                right: TtSpace.s5,
                bottom: TtSpace.s4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.urgent)
                      const TratraBadge('Urgent', tone: TratraTone.accent, icon: Icons.bolt_rounded),
                    const Spacer(),
                    if (multi)
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            for (var i = 0; i < images.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: AnimatedContainer(
                                  duration: reduceMotion ? Duration.zero : TtMotion.base,
                                  curve: TtMotion.emphasized,
                                  width: i == _page ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: i == _page
                                        ? TtColors.accent
                                        : Colors.white.withValues(alpha: 0.55),
                                    borderRadius: TtRadius.pillAll,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sur-titre : pastille majuscule 11 px à fort interlettrage.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: TtColors.primarySoft, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TratraTheme.style(TtType.eyebrow, color: TtColors.primaryDark),
        ),
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
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: TtColors.primarySoft, borderRadius: TtRadius.controlAll),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 20, color: TtColors.primaryDark),
            ),
          ),
          const SizedBox(width: TtSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.title).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Coche jaune des listes « inclus ».
class _Tick extends StatelessWidget {
  const _Tick();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: TtColors.accent, shape: BoxShape.circle),
      child: SizedBox(
        width: 22,
        height: 22,
        child: Icon(Icons.check_rounded, size: 14, color: TtColors.ink),
      ),
    );
  }
}

/// Chargement des recommandations (une seule animation partagée).
class _SimilarSkeleton extends StatelessWidget {
  const _SimilarSkeleton();

  @override
  Widget build(BuildContext context) {
    final extent = ServiceMiniCard.extentFor(context);
    return Semantics(
      label: 'Chargement en cours',
      liveRegion: true,
      child: ExcludeSemantics(
        child: TratraShimmer(
          child: SizedBox(
            height: extent,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: TtSpace.s5),
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: TtSpace.s3),
                    child: SizedBox(
                      width: 188,
                      child: TratraSkeletonBox(height: extent, radius: TtRadius.panel),
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

/// Barre d'action collante : tarif + CTA principal vers la réservation.
class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.price, required this.onBook});

  final String price;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TtColors.surface,
        border: Border(top: BorderSide(color: TtColors.lineSoft)),
        boxShadow: TtShadows.hair,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TtSpace.s5, TtSpace.s3, TtSpace.s5, TtSpace.s3),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tarif', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        price,
                        maxLines: 1,
                        style: TratraTheme.style(TtType.h3, color: TtColors.primaryDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TtSpace.s4),
              Expanded(
                child: TratraButton(
                  label: 'Réserver',
                  size: TratraButtonSize.lg,
                  block: true,
                  leading: const Icon(Icons.event_available_rounded),
                  onPressed: onBook,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
