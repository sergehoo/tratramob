// widgets/category_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Tuile de catégorie : pastille d'icône verte sur fond doux + libellé (2 lignes max).
class CategoryCard extends StatelessWidget {
  final IconData icon;
  final String name;

  /// Conservé pour compatibilité d'API : la couleur des catégories vient du Design System
  /// (vert de marque), pas de l'appelant.
  const CategoryCard({super.key, required this.icon, required this.name, required color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: TtSpace.s3),
      child: SizedBox(
        width: 80,
        child: TratraCard(
          radius: TtRadius.panel,
          padding: const EdgeInsets.symmetric(horizontal: TtSpace.s2, vertical: TtSpace.s2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: TtColors.primarySoft, shape: BoxShape.circle),
                child: Icon(icon, color: TtColors.primaryDark, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.caption, color: TtColors.ink)
                    .copyWith(fontWeight: FontWeight.w600, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
