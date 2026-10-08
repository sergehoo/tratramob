// lib/screens/artisan_profile_screen.dart
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/artisan.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/screens/service_detail_screen.dart';

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
  // UI
  static const _bg = Color(0xFFF8F9FA);
  static const _card = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE5E5E5);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);

  static const _phAvatar = 'https://via.placeholder.com/300x300?text=Artisan';

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
  String _safeUrl(String raw, String fallback) {
    final u = raw.trim();
    if (u.isEmpty) return fallback;
    final p = Uri.tryParse(u);
    if (p == null ||
        !p.hasScheme ||
        !(p.isScheme('http') || p.isScheme('https'))) {
      return fallback;
    }
    return u;
  }

  Future<http.Response> _getPublic(Uri uri) async {
    final c = _api.client;
    var r = await c.get(uri, headers: await _api.getHeaders(withAuth: true));
    if (r.statusCode == 401) {
      r = await c.get(uri, headers: await _api.getHeaders(withAuth: false));
    }
    return r;
  }

  Artisan _artisanFromBackend(Map<String, dynamic> j) {
    // Mapping tolérant
    return Artisan(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? j['full_name'] ?? '').toString(),
      profession: (j['profession'] ?? j['specialty'] ?? '').toString(),
      rating: (j['rating'] ?? j['rating_avg'] ?? 0).toDouble(),
      reviews: (j['reviews'] ?? j['review_count'] ?? 0) as int,
      imageUrl:
          (j['imageUrl'] ?? j['image_url'] ?? j['avatar'] ?? '').toString(),
      distance: (j['distance'] ?? 0).toDouble(),
      isAvailable: (j['isAvailable'] ?? j['is_available'] ?? false) == true,
      hourlyRate: (j['hourlyRate'] ?? j['hourly_rate'] ?? 0).toDouble(),
      isCertified: (j['isCertified'] ?? j['is_certified'] ?? false) == true,
      responseTime: (j['responseTime'] ?? j['response_time'])?.toString(),
      yearsExperience:
          (j['yearsExperience'] ?? j['years_experience'] ?? 0) as int,
      specialties: (j['specialties'] is List)
          ? List<String>.from(j['specialties'])
          : <String>[],
      description: (j['description'] ?? j['bio'] ?? '').toString(),
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
        _errorInfo = e.toString();
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
        _errorServices = e.toString();
        _loadingServices = false;
      });
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final a = _artisan;

    final name = (a?.name ?? '').isNotEmpty ? a!.name : 'Artisan';
    final avatar = _safeUrl(a?.imageUrl ?? '', _phAvatar);
    final ratingVal = a?.rating ?? 0;
    final reviews = a?.reviews ?? 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Profil artisan'),
        backgroundColor: _card,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: _accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Si aucun ID disponible : info
            if (_artisanId == null || _artisanId!.isEmpty) ...[
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  "Impossible d’afficher le profil : identifiant manquant.",
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(60),
                  child: CachedNetworkImage(
                    imageUrl: avatar,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(width: 72, height: 72, color: Colors.black12),
                    errorWidget: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: Colors.black12,
                      child:
                          const Icon(Icons.person_outline, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: (_loadingInfo && a == null)
                      ? const LinearProgressIndicator(minHeight: 10)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (ratingVal > 0) ...[
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    ratingVal.toStringAsFixed(1),
                                    style: const TextStyle(
                                        color: _textSecondary,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (reviews > 0) ...[
                                    const SizedBox(width: 6),
                                    Text('($reviews)',
                                        style: const TextStyle(
                                            color: _textSecondary)),
                                  ],
                                  const SizedBox(width: 8),
                                ],
                                if ((a?.profession ?? '').isNotEmpty)
                                  Text(
                                    a!.profession,
                                    style:
                                        const TextStyle(color: _textSecondary),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (a?.isAvailable == true)
                                  const _ChipInfo(
                                    icon: Icons.check_circle_outline,
                                    label: 'Disponible',
                                  ),
                                if (a?.isCertified == true)
                                  const _ChipInfo(
                                    icon: Icons.verified_outlined,
                                    label: 'Certifié',
                                  ),
                                if ((a?.hourlyRate ?? 0) > 0)
                                  _ChipInfo(
                                    icon: Icons.attach_money,
                                    label:
                                        '${a!.hourlyRate.toStringAsFixed(0)} FCFA/h',
                                  ),
                                if ((a?.yearsExperience ?? 0) > 0)
                                  _ChipInfo(
                                    icon: Icons.badge_outlined,
                                    label:
                                        '${a!.yearsExperience} an${(a.yearsExperience) > 1 ? "s" : ""} exp.',
                                  ),
                                if ((a?.responseTime ?? '').isNotEmpty)
                                  _ChipInfo(
                                    icon: Icons.schedule_outlined,
                                    label: 'Réponse: ${a!.responseTime}',
                                  ),
                                if ((a?.distance ?? 0) > 0)
                                  _ChipInfo(
                                    icon: Icons.place_outlined,
                                    label:
                                        '${a!.distance.toStringAsFixed(1)} km',
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
                IconButton(
                  onPressed: () {
                    // Flow message éventuel
                  },
                  icon: const Icon(Icons.chat_bubble_outline),
                  tooltip: 'Contacter',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Spécialités
            if ((a?.specialties ?? []).isNotEmpty) ...[
              const Text('Spécialités',
                  style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (a?.specialties ?? [])
                    .map((s) => Chip(
                          label: Text(s),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: _border),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // À propos
            if ((a?.description ?? '').isNotEmpty) ...[
              const Text('À propos',
                  style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                a?.description ?? '',
                style: const TextStyle(color: _textPrimary, height: 1.35),
              ),
              const SizedBox(height: 16),
            ],

            // Services proposés
            Row(
              children: const [
                Text('Services proposés',
                    style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),

            if (_loadingServices)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorServices != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Erreur: $_errorServices',
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (_services.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: Text('Aucun service pour le moment')),
              )
            else
              GridView.builder(
                itemCount: _services.length,
                padding: const EdgeInsets.only(top: 6),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .78,
                ),
                itemBuilder: (_, i) {
                  final s = _services[i];
                  return _ServiceCardMini(
                    service: s,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceDetailScreen(service: s),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFFE5E5E5);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      side: const BorderSide(color: border),
      backgroundColor: Colors.white,
    );
  }
}

class _ServiceCardMini extends StatelessWidget {
  const _ServiceCardMini({required this.service, required this.onTap});
  final Service service;
  final VoidCallback onTap;

  static const _card = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE5E5E5);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);
  static const _phService = 'https://via.placeholder.com/600x400?text=Service';

  String _safe(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return _phService;
    final p = Uri.tryParse(u);
    if (p == null ||
        !p.hasScheme ||
        !(p.isScheme('http') || p.isScheme('https'))) {
      return _phService;
    }
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final image = _safe(service.imageUrl);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: image,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(height: 110, color: Colors.black12),
                errorWidget: (_, __, ___) => Container(
                  height: 110,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.grey),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(
                service.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _textPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      service.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: _textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Text(
                    service.priceDisplay.replaceAll('F', 'FCFA'),
                    style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 13),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: _textSecondary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
