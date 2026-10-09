// lib/screens/home/home_sheets.dart
//
// Feuilles basses de l'accueil. Chaque entrée déclenche une action existante de l'écran
// (filtrer par catégorie, ouvrir une liste, relancer la localisation) : aucune entrée factice.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/models/category.dart';

import 'home_icons.dart';

/// Nombre maximal de catégories proposées dans la feuille « Trouver un pro ».
const int _maxSheetCategories = 6;

Future<void> showHomeQuickRequestSheet(
  BuildContext context, {
  required List<Category> categories,
  required ValueChanged<Category> onCategory,
  required VoidCallback onUrgent,
  required VoidCallback onAllServices,
}) {
  return showTratraSheet<void>(
    context,
    title: 'Trouver un pro',
    description: 'Choisissez un métier pour afficher les services et les pros correspondants.',
    child: Builder(
      builder: (sheetContext) {
        void run(VoidCallback action) {
          HapticFeedback.selectionClick();
          Navigator.of(sheetContext).pop();
          action();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in categories.take(_maxSheetCategories)) ...[
              _SheetTile(
                leading: homeCategoryIcon(c, color: TtColors.primaryDark),
                title: c.name,
                onTap: () => run(() => onCategory(c)),
              ),
              const SizedBox(height: TtSpace.s2),
            ],
            _SheetTile(
              leading: const Icon(Icons.bolt_rounded, color: TtColors.ink, size: 22),
              title: 'Dépannage urgent',
              subtitle: 'Liste des services d’urgence',
              accent: true,
              onTap: () => run(onUrgent),
            ),
            const SizedBox(height: TtSpace.s4),
            TratraButton(
              label: 'Voir tous les services',
              variant: TratraButtonVariant.outline,
              block: true,
              trailing: const Icon(Icons.arrow_forward_rounded),
              onPressed: () => run(onAllServices),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showHomeLocationSheet(
  BuildContext context, {
  required bool hasPosition,
  required VoidCallback onRefresh,
}) {
  return showTratraSheet<void>(
    context,
    title: 'Votre position',
    child: Builder(
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TratraAlert(
            tone: hasPosition ? TratraAlertTone.success : TratraAlertTone.warning,
            icon: hasPosition ? Icons.near_me_rounded : Icons.location_off_outlined,
            message: hasPosition
                ? 'Les pros proches sont recherchés autour de votre position actuelle.'
                : 'La localisation est désactivée ou refusée. Autorisez-la dans les réglages de votre téléphone, puis actualisez.',
          ),
          const SizedBox(height: TtSpace.s4),
          TratraButton(
            label: 'Actualiser ma position',
            block: true,
            leading: const Icon(Icons.my_location_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(sheetContext).pop();
              onRefresh();
            },
          ),
        ],
      ),
    ),
  );
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.accent = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TratraCard(
      variant: accent ? TratraCardVariant.accent : TratraCardVariant.flat,
      radius: TtRadius.panel,
      padding: const EdgeInsets.symmetric(horizontal: TtSpace.s4, vertical: TtSpace.s3),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent ? TtColors.accent : TtColors.primarySoft,
                borderRadius: TtRadius.controlAll,
              ),
              child: Center(child: leading),
            ),
            const SizedBox(width: TtSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.title),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TratraTheme.style(TtType.caption, color: TtColors.inkSoft),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: TtColors.ash),
          ],
        ),
      ),
    );
  }
}
