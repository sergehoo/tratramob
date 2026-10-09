// screens/search_screen.dart
import 'package:flutter/material.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/routes.dart';

/// Écran « Recherche ». Il ne lance aucune requête par lui-même : la recherche par
/// mots-clés vit dans les listes du catalogue (catégories, services, services
/// urgents). L'écran y mène par des raccourcis vers des routes existantes et ne
/// présente aucun résultat ni aucune catégorie qu'il n'a pas réellement.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TtColors.canvas,
      appBar: const TratraAppBar(title: 'Recherche'),
      body: Column(
        children: [
          // Barre de recherche
          DecoratedBox(
            decoration: const BoxDecoration(
              color: TtColors.surface,
              border: Border(bottom: BorderSide(color: TtColors.lineSoft)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  TtSpace.s4, TtSpace.s3, TtSpace.s4, TtSpace.s4),
              // La recherche réelle (texte, filtres, tri) vit dans le catalogue : le champ l'ouvre.
              child: TratraInput(
                hint: 'Rechercher un service ou un artisan…',
                leadingIcon: Icons.search_rounded,
                readOnly: true,
                onTap: () => Navigator.pushNamed(context, RouteNames.allServices),
              ),
            ),
          ),

          // Raccourcis vers le catalogue
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                TtSpace.s4,
                TtSpace.s2,
                TtSpace.s4,
                TtSpace.s6 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                TratraSectionHeader(
                  title: 'Où chercher ?',
                  subtitle: 'Choisissez une rubrique du catalogue.',
                  padding: const EdgeInsets.fromLTRB(
                      0, TtSpace.s6, 0, TtSpace.s3),
                ),
                for (final shortcut in _shortcuts) ...[
                  _ShortcutCard(
                    shortcut: shortcut,
                    onTap: () => Navigator.pushNamed(context, shortcut.route),
                  ),
                  const SizedBox(height: TtSpace.s3),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Raccourcis =====

class _Shortcut {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.description,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String description;
  final String route;
}

/// Chaque raccourci pointe vers une route enregistrée dans `main.dart`.
const List<_Shortcut> _shortcuts = [
  _Shortcut(
    icon: Icons.category_outlined,
    title: 'Toutes les catégories',
    description: 'Parcourez les métiers et recherchez par nom.',
    route: RouteNames.allCategories,
  ),
  _Shortcut(
    icon: Icons.home_repair_service_outlined,
    title: 'Tous les services',
    description: 'Recherchez un service, filtrez par prix, catégorie et tri.',
    route: RouteNames.allServices,
  ),
  _Shortcut(
    icon: Icons.bolt_rounded,
    title: 'Services urgents',
    description: 'Les interventions proposées en urgence.',
    route: RouteNames.allUrgentServices,
  ),
  _Shortcut(
    icon: Icons.near_me_outlined,
    title: 'Artisans à proximité',
    description: 'Les services proposés autour de votre position.',
    route: RouteNames.allNearbyArtisans,
  ),
];

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.shortcut, required this.onTap});

  final _Shortcut shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      radius: TtRadius.panel,
      padding: const EdgeInsets.all(TtSpace.s4),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: TtColors.primarySoft,
              borderRadius: TtRadius.controlAll,
            ),
            child: Icon(shortcut.icon, color: TtColors.primary),
          ),
          const SizedBox(width: TtSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortcut.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.h3)
                      .copyWith(fontSize: 15, height: 1.25),
                ),
                const SizedBox(height: TtSpace.s1),
                Text(
                  shortcut.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TratraTheme.style(TtType.bodySm, color: TtColors.ash),
                ),
              ],
            ),
          ),
          const SizedBox(width: TtSpace.s2),
          const Icon(Icons.chevron_right_rounded, color: TtColors.fog),
        ],
      ),
    );
  }
}
