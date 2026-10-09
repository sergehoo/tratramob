import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// État vide honnête : explique la situation réelle et propose une action utile
/// (miroir de `EmptyState` côté web). Jamais de donnée fictive.
class TratraEmptyState extends StatelessWidget {
  const TratraEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.actions = const [],
    this.compact = false,
    this.onNight = false,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final List<Widget> actions;
  final bool compact;
  final bool onNight;

  @override
  Widget build(BuildContext context) {
    final titleColor = onNight ? Colors.white : TtColors.ink;
    final bodyColor = onNight ? Colors.white70 : TtColors.ash;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 20 : 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: onNight ? Colors.white.withValues(alpha: 0.1) : TtColors.primarySoft,
                    borderRadius: BorderRadius.circular(TtRadius.panel),
                  ),
                  child: Icon(icon, size: 28, color: onNight ? TtColors.accent : TtColors.primary),
                ),
                const SizedBox(height: 18),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: TratraTheme.style(TtType.h3, color: titleColor),
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: TratraTheme.style(TtType.body, color: bodyColor).copyWith(fontSize: 14),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
