// lib/screens/service_link_screen.dart
//
// Offre ouverte depuis un lien (annonce, notification) : `tratra://service/40`. L'offre est rechargée auprès du serveur — seule une
// offre PUBLIÉE est renvoyée (active, artisan vérifié) — puis l'écran habituel de l'offre la remplace. Offre retirée ou introuvable :
// message clair et accès à toutes les offres, jamais d'écran vide.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/core/constants.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/screens/all_services_screen.dart';
import 'package:flutter_tratra/screens/service_detail_screen.dart';

class ServiceLinkScreen extends StatefulWidget {
  const ServiceLinkScreen({super.key, required this.serviceId});
  final int serviceId;

  @override
  State<ServiceLinkScreen> createState() => _ServiceLinkScreenState();
}

class _ServiceLinkScreenState extends State<ServiceLinkScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final api = context.read<BaseApi>();
    try {
      final uri = Uri.parse('${api.baseUrl}${AppConstants.servicesEndpoint}/${widget.serviceId}/');
      final r = await api.client.get(uri, headers: await api.getHeaders(withAuth: true));
      if (r.statusCode != 200) throw StateError('${r.statusCode}');
      final service = Service.fromJson(Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)) as Map));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ServiceDetailScreen(service: service)));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offre')),
      body: Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.search_off_rounded, size: 48),
                  const SizedBox(height: 12),
                  const Text('Cette offre n’est plus disponible.', textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .pushReplacement(MaterialPageRoute<void>(builder: (_) => const AllServicesScreen())),
                    child: const Text('Voir toutes les offres'),
                  ),
                  TextButton(onPressed: _load, child: const Text('Réessayer')),
                ]),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
