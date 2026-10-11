// lib/screens/dashboard/recommended_card.dart
//
// « Recommandés pour vous » (miroir de frontend/src/components/recommendations/Recommended.tsx) : classement DÉTERMINISTE fait par le serveur
// (besoin, lieu, disponibilité, réputation vérifiable, prix) ; jamais de prestataire non éligible. Aucun bloc en cas d'échec : l'aide ne bloque rien.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';
import 'package:flutter_tratra/screens/dashboard/dash_ui.dart';
import 'package:flutter_tratra/screens/dashboard/dashboard_core.dart';
import 'package:flutter_tratra/services/api_service.dart';

class RecommendedCard extends StatefulWidget {
  const RecommendedCard({super.key});
  @override
  State<RecommendedCard> createState() => _RecommendedCardState();
}

class _RecommendedCardState extends State<RecommendedCard> {
  late final Future<Map<String, dynamic>?> _future = _load();

  Future<Map<String, dynamic>?> _load() async {
    try {
      return await context.read<DashboardApi>().post('/recommendations/', {'limit': 4});
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(int serviceId) async {
    try {
      final service = await context.read<ApiService>().getServiceById('$serviceId');
      if (mounted) await Navigator.pushNamed(context, RouteNames.serviceDetail, arguments: ServiceDetailArgs(service));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e, 'Ce service n’a pas pu être ouvert.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        final rows = ((snap.data?['results'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        if (rows.isEmpty) return const SizedBox.shrink();
        final located = snap.data?['located'] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: TtSpace.s4),
          child: TratraCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Recommandés pour vous', style: TratraTheme.style(TtType.h3)),
              Text(located ? 'Classés selon votre besoin, la distance, la disponibilité, la réputation et le prix.' : 'Ajoutez votre adresse principale pour tenir compte de la distance.',
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.inkSoft)),
              for (final r in rows)
                InkWell(
                  onTap: () => _open((r['service_id'] as num).toInt()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: TtSpace.s2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TratraTheme.style(TtType.title)),
                          Text('${r['provider_name']}${r['category'] != null ? ' · ${r['category']}' : ''}', style: TratraTheme.style(TtType.caption, color: TtColors.ash)),
                          Text(
                            [
                              if (r['rating'] != null) 'Note ${r['rating']} · ${r['reviews']} avis' else 'Peu d’avis',
                              if (r['distance_km'] != null) '≈ ${r['distance_km']} km',
                              if (r['available'] == true) 'Disponible' else if (r['available'] == false) 'Indisponible à ce moment',
                            ].join(' · '),
                            style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft),
                          ),
                          if ((r['transport'] as Map?)?['applicable'] == true)
                            Text('Déplacement ${formatFcfa((((r['transport'] as Map)['amount']) as num?) ?? 0)}${(r['transport'] as Map)['fallback'] == true ? ' (forfait)' : ''}',
                                style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft)),
                        ]),
                      ),
                      Text(r['price'] != null ? formatFcfa((r['price'] as num)) : 'Sur devis', style: TratraTheme.style(TtType.bodySm).copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
