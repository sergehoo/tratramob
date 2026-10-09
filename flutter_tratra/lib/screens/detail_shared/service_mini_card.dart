// Carte compacte d'un service (recommandations, services d'un artisan).
// Affichage uniquement : la navigation est fournie par l'écran appelant.
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/service.dart';
import 'package:flutter_tratra/screens/detail_shared/detail_helpers.dart';

class ServiceMiniCard extends StatelessWidget {
  const ServiceMiniCard({super.key, required this.service, required this.onTap});

  final Service service;
  final VoidCallback onTap;

  static const double _imageHeight = 108;

  /// Hauteur imposée à la carte par l'écran parent ; suit le facteur d'échelle du
  /// texte pour éviter tout débordement quand l'utilisateur agrandit les polices.
  static double extentFor(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.8);
    return _imageHeight + 118 * scale;
  }

  @override
  Widget build(BuildContext context) {
    final s = service;
    return TratraCard(
      variant: TratraCardVariant.flat,
      radius: TtRadius.panel,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _imageHeight,
            width: double.infinity,
            child: ServiceCover(url: realImageUrl(s.imageUrl)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(TtSpace.s3, 10, TtSpace.s3, TtSpace.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.title).copyWith(fontSize: 14, height: 1.3),
                  ),
                  if (s.categoryName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      s.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TratraTheme.style(TtType.caption, color: TtColors.ash),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatServicePrice(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.bodySm, color: TtColors.primaryDark)
                              .copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: TtColors.ash),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
