// lib/screens/home/home_filters.dart
//
// Filtres de l'accueil : catégories, proximité et tri (pastilles du Design System).
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';

class HomeFilterPanel extends StatelessWidget {
  const HomeFilterPanel({
    super.key,
    required this.categories,
    required this.selected,
    required this.onlyNearby,
    required this.canNearby,
    required this.ordering,
    required this.onSelectCategory,
    required this.onToggleNearby,
    required this.onChangeOrdering,
    required this.onRetryLocation,
  });

  final List<Category> categories;
  final Category? selected;
  final bool onlyNearby;
  final bool canNearby;
  final String ordering;

  final ValueChanged<Category?> onSelectCategory;
  final ValueChanged<bool> onToggleNearby;
  final ValueChanged<String> onChangeOrdering;

  /// Relance la localisation (action existante de l'écran).
  final VoidCallback onRetryLocation;

  static const _orderings = <(String, String)>[
    ('-created_at', 'Plus récents'),
    ('price', 'Prix croissant'),
    ('-price', 'Prix décroissant'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
            itemCount: categories.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: TtSpace.s2),
            itemBuilder: (_, idx) {
              if (idx == 0) {
                return TratraChip(
                  label: 'Toutes',
                  selected: selected == null,
                  onTap: () => onSelectCategory(null),
                );
              }
              final c = categories[idx - 1];
              return TratraChip(
                label: c.name,
                selected: selected?.id == c.id,
                onTap: () => onSelectCategory(c),
              );
            },
          ),
        ),
        const SizedBox(height: TtSpace.s2),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4),
            children: [
              TratraChip(
                label: 'Proximité',
                icon: Icons.near_me_rounded,
                selected: onlyNearby,
                onTap: () => onToggleNearby(!onlyNearby),
              ),
              Center(
                child: Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: TtSpace.s3),
                  color: TtColors.line,
                ),
              ),
              for (final (value, label) in _orderings) ...[
                TratraChip(
                  label: label,
                  selected: ordering == value,
                  onTap: () => onChangeOrdering(value),
                ),
                const SizedBox(width: TtSpace.s2),
              ],
            ],
          ),
        ),
        if (onlyNearby && !canNearby)
          Padding(
            padding: const EdgeInsets.fromLTRB(TtSpace.s4, TtSpace.s3, TtSpace.s4, 0),
            child: TratraAlert(
              tone: TratraAlertTone.info,
              icon: Icons.location_off_outlined,
              message: 'Votre position n’est pas disponible : les services ne sont pas filtrés par distance.',
              action: Align(
                alignment: Alignment.centerLeft,
                child: TratraButton(
                  label: 'Réessayer la localisation',
                  variant: TratraButtonVariant.soft,
                  onPressed: onRetryLocation,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
