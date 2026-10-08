// lib/screens/service_detail_screen.dart
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/screens/artisan_profile_screen.dart';

class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({super.key, required this.service});

  final Service service;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  // UI
  static const _bg = Color(0xFFF8F9FA);
  static const _card = Color(0xFFFFFFFF);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);
  static const _danger = Color(0xFFFF5252);
  static const _placeholder =
      'https://via.placeholder.com/1000x600?text=Service';

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

  // ---------- helpers modèle / sécurité ----------
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
        _errorRecos = e.toString();
        _loadingRecos = false;
      });
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final cover = _safeUrl(s.imageUrl, _placeholder);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
          title: const Text('Détail du service'), backgroundColor: _card),
      body: RefreshIndicator(
        onRefresh: _loadSimilar,
        color: _accent,
        child: ListView(
          children: [
            // Image principale
            CachedNetworkImage(
              imageUrl: cover,
              height: 220,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(height: 220, color: Colors.black12),
              errorWidget: (_, __, ___) => Container(
                  height: 220,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined,
                      color: Colors.grey)),
            ),

            // Titre + prix
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      s.title,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.priceDisplay.replaceAll('F', 'FCFA'),
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Métas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined,
                      size: 16, color: _textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.categoryName,
                      style: const TextStyle(color: _textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if ((s.rating ?? 0) > 0) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      s.rating!.toStringAsFixed(1),
                      style: const TextStyle(color: _textSecondary),
                    ),
                  ],
                  if ((s.reviewCount ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    Text('(${s.reviewCount})',
                        style: const TextStyle(color: _textSecondary)),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Description
            if (s.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  s.description,
                  style: const TextStyle(color: _textPrimary, height: 1.35),
                ),
              ),

            if (s.duration != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 16, color: _textSecondary),
                    const SizedBox(width: 6),
                    Text(s.durationDisplay,
                        style: const TextStyle(color: _textSecondary)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // À raccorder à ton flow de réservation
                        // Navigator.pushNamed(context, RouteNames.booking, arguments: BookingArgs(s));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.event_available),
                      label: const Text('Réserver'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: s.handymanId.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ArtisanProfileScreen(
                                    artisanId: s.handymanId,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Voir l’artisan'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Recommandations
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: const [
                  Text('Vous pourriez aussi aimer',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
            if (_loadingRecos)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorRecos != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Erreur: $_errorRecos',
                    style: const TextStyle(color: _danger)),
              )
            else if (_similar.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: Text('Aucune recommandation')),
              )
            else
              SizedBox(
                height: 210,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) {
                    final x = _similar[i];
                    return _SimilarCard(
                      service: x,
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServiceDetailScreen(service: x),
                          ),
                        );
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemCount: _similar.length,
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({
    required this.service,
    required this.onTap,
  });

  final Service service;
  final VoidCallback onTap;

  static const _card = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE5E5E5);
  static const _textPrimary = Color(0xFF1E272E);
  static const _textSecondary = Color(0xFF636E72);
  static const _accent = Color(0xFF00B14F);
  static const _placeholder =
      'https://via.placeholder.com/600x400?text=Service';

  String _safe(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return _placeholder;
    final p = Uri.tryParse(u);
    if (p == null ||
        !p.hasScheme ||
        !(p.isScheme('http') || p.isScheme('https'))) {
      return _placeholder;
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
        width: 180,
        decoration: BoxDecoration(
          color: _card,
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(12),
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
