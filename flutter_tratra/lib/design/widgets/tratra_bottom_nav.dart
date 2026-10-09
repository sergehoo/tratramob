import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

class TratraNavItem {
  const TratraNavItem({required this.icon, required this.label, this.activeIcon, this.badge});
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  /// Compteur réel (ex. messages non lus) — affiché seulement s'il est > 0.
  final int? badge;
}

/// Navigation basse de la marque (miroir de la barre basse mobile de l'AppShell web) :
/// pastille verte douce derrière l'icône active + liseré jaune en haut de l'onglet.
class TratraBottomNav extends StatelessWidget {
  const TratraBottomNav({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<TratraNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TtColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: TtColors.lineSoft))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: TtLayout.bottomNavHeight,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
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

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final TratraNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TtColors.primaryDark : TtColors.ash;
    final badge = item.badge ?? 0;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '${item.label}, $badge' : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            AnimatedContainer(
              duration: TtMotion.base,
              curve: TtMotion.emphasized,
              width: selected ? 36 : 0,
              height: 3,
              decoration: const BoxDecoration(
                color: TtColors.accent,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: TtMotion.base,
                        curve: TtMotion.emphasized,
                        width: 56,
                        height: 30,
                        decoration: BoxDecoration(
                          color: selected ? TtColors.primarySoft : Colors.transparent,
                          borderRadius: TtRadius.pillAll,
                        ),
                        child: Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, size: 22, color: color),
                      ),
                      if (badge > 0)
                        Positioned(
                          right: 6,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: TtColors.danger,
                              borderRadius: TtRadius.pillAll,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: TratraTheme.style(TtType.caption, color: Colors.white)
                                  .copyWith(fontSize: 10, fontWeight: FontWeight.w700, height: 1.2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TratraTheme.style(TtType.caption, color: color)
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w600, height: 1.1),
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
