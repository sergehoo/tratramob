import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// Pastille sélectionnable (filtres, métiers) — miroir des chips de la recherche web.
class TratraChip extends StatelessWidget {
  const TratraChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? TtColors.primaryDark : TtColors.inkSoft;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: TtMotion.base,
        curve: TtMotion.emphasized,
        decoration: ShapeDecoration(
          color: selected ? TtColors.primarySoft : TtColors.surface,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? TtColors.primary.withValues(alpha: 0.5) : TtColors.line),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                    Text(
                      label,
                      style: TratraTheme.style(TtType.bodySm, color: fg).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
