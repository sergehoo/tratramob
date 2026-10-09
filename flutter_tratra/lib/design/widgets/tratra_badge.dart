import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum TratraTone { primary, accent, night, gray, success, warning, danger, info }

({Color bg, Color fg, Color dot, Color? ring}) tratraToneColors(TratraTone tone) {
  switch (tone) {
    case TratraTone.primary:
      return (bg: TtColors.primarySoft, fg: TtColors.primaryDark, dot: TtColors.primary, ring: null);
    case TratraTone.accent:
      return (
        bg: TtColors.accentSoft,
        fg: TtColors.ink,
        dot: TtColors.accentDark,
        ring: TtColors.accent.withValues(alpha: 0.5),
      );
    case TratraTone.night:
      return (bg: TtColors.night, fg: Colors.white, dot: TtColors.accent, ring: null);
    case TratraTone.gray:
      return (bg: TtColors.lineSoft, fg: TtColors.inkSoft, dot: TtColors.fog, ring: null);
    case TratraTone.success:
      return (bg: TtColors.successSoft, fg: TtColors.successInk, dot: TtColors.success, ring: null);
    case TratraTone.warning:
      return (bg: TtColors.warningSoft, fg: TtColors.warningInk, dot: TtColors.warning, ring: null);
    case TratraTone.danger:
      return (bg: TtColors.dangerSoft, fg: TtColors.dangerInk, dot: TtColors.danger, ring: null);
    case TratraTone.info:
      return (bg: TtColors.infoSoft, fg: TtColors.infoInk, dot: TtColors.info, ring: null);
  }
}

/// Étiquette pilule (miroir de `Badge` côté web). `pulse` = pastille animée (« en direct »).
class TratraBadge extends StatefulWidget {
  const TratraBadge(
    this.label, {
    super.key,
    this.tone = TratraTone.primary,
    this.dot = false,
    this.pulse = false,
    this.icon,
  });

  final String label;
  final TratraTone tone;
  final bool dot;
  final bool pulse;
  final IconData? icon;

  @override
  State<TratraBadge> createState() => _TratraBadgeState();
}

class _TratraBadgeState extends State<TratraBadge> with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = tratraToneColors(widget.tone);
    final animate = _pulse != null && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.bg,
        shape: StadiumBorder(side: c.ring == null ? BorderSide.none : BorderSide(color: c.ring!)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.dot || widget.pulse) ...[
              animate
                  ? FadeTransition(
                      opacity: Tween<double>(begin: 1, end: 0.45).animate(_pulse!),
                      child: _Dot(color: c.dot),
                    )
                  : _Dot(color: c.dot),
              const SizedBox(width: 6),
            ],
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 14, color: c.fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.caption, color: c.fg).copyWith(fontWeight: FontWeight.w600, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
