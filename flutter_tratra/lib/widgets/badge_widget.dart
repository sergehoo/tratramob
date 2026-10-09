// widgets/badge_widget.dart
// Badges historiques posés sur le Design System. Préférer TratraBadge / TratraStatusBadge
// (lib/design) pour tout nouveau code : StatusBadge, PromotionBadge, AvailabilityBadge
// et CertificationBadge n'en sont plus que de fins adaptateurs. BadgeWidget, IconBadge et
// RatingBadge gardent des couleurs libres fournies par l'appelant (non couvertes par les
// tons du DS) mais utilisent ses jetons de forme, d'ombre et de typographie.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

/// Pastille icône + libellé aux couleurs fournies par l'appelant.
class BadgeWidget extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final double? size;

  const BadgeWidget({
    super.key,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = size ?? 14;
    final fontSize = size != null ? size! - 2 : 12.0;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: const StadiumBorder(),
        shadows: TtShadows.hair,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: textColor),
            const SizedBox(width: TtSpace.s1),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TratraTheme.style(TtType.caption, color: textColor)
                    .copyWith(fontSize: fontSize, fontWeight: FontWeight.w600, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Variante de badge avec seulement une icône
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: TtShadows.hair,
      ),
      child: Icon(icon, size: size * 0.6, color: iconColor),
    );
  }
}

// Badge pour statuts — adaptateur : préférer TratraBadge / TratraStatusBadge.
class StatusBadge extends StatelessWidget {
  final String status;
  final StatusType type;

  const StatusBadge({
    super.key,
    required this.status,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final (tone, icon) = switch (type) {
      StatusType.success => (TratraTone.success, Icons.check_circle_outline),
      StatusType.warning => (TratraTone.warning, Icons.warning_amber_rounded),
      StatusType.error => (TratraTone.danger, Icons.error_outline),
      StatusType.info => (TratraTone.info, Icons.info_outline),
      StatusType.pending => (TratraTone.accent, Icons.schedule),
    };
    return TratraBadge(status, tone: tone, icon: icon);
  }
}

enum StatusType {
  success,
  warning,
  error,
  info,
  pending,
}

// Badge pour promotions — adaptateur : préférer TratraBadge.
// Le pourcentage affiché vient du paramètre `discount` fourni par l'appelant.
class PromotionBadge extends StatelessWidget {
  final double discount;
  final bool isUrgent;

  const PromotionBadge({
    super.key,
    required this.discount,
    this.isUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    return isUrgent
        ? const TratraBadge('Urgent', tone: TratraTone.danger, icon: Icons.bolt_rounded)
        : TratraBadge('-${discount.round()}%', tone: TratraTone.accent);
  }
}

// Badge pour disponibilité — adaptateur : préférer TratraBadge.
class AvailabilityBadge extends StatelessWidget {
  final bool isAvailable;
  final String? customText;

  const AvailabilityBadge({
    super.key,
    required this.isAvailable,
    this.customText,
  });

  @override
  Widget build(BuildContext context) {
    return TratraBadge(
      customText ?? (isAvailable ? 'Disponible' : 'Occupé'),
      tone: isAvailable ? TratraTone.success : TratraTone.gray,
      dot: true,
    );
  }
}

// Badge pour rating
class RatingBadge extends StatelessWidget {
  final double rating;
  final int reviews;
  final bool showReviews;

  const RatingBadge({
    super.key,
    required this.rating,
    this.reviews = 0,
    this.showReviews = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TratraTheme.style(TtType.caption, color: TtColors.ink)
        .copyWith(fontWeight: FontWeight.w600, height: 1.1);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: TtColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: TtColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 14, color: TtColors.accent),
            const SizedBox(width: TtSpace.s1),
            Text(rating.toStringAsFixed(1).replaceAll('.', ','), style: style),
            if (showReviews && reviews > 0) ...[
              const SizedBox(width: TtSpace.s1),
              Text('($reviews)', style: style.copyWith(color: TtColors.ash, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

// Badge pour certification — adaptateur : préférer TratraBadge.
class CertificationBadge extends StatelessWidget {
  final bool isCertified;

  const CertificationBadge({
    super.key,
    required this.isCertified,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCertified) return const SizedBox.shrink();
    return const TratraBadge('Certifié', tone: TratraTone.primary, icon: Icons.verified);
  }
}
