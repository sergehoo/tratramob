// widgets/badge_widget.dart
import 'package:flutter/material.dart';
import '../core/constants.dart';

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: size ?? 14,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: size != null ? size! - 2 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: size * 0.6,
        color: iconColor,
      ),
    );
  }
}

// Badge pour statuts
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
    final (backgroundColor, textColor, icon) = _getStatusColors(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            status,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, IconData?) _getStatusColors(StatusType type) {
    switch (type) {
      case StatusType.success:
        return (
          AppConstants.primaryLight,
          AppConstants.primaryDark,
          Icons.check_circle
        );
      case StatusType.warning:
        return (
          const Color(0xFFFFF2CC),
          const Color(0xFFE6B800),
          Icons.warning
        );
      case StatusType.error:
        return (const Color(0xFFFFE6E6), const Color(0xFFD32F2F), Icons.error);
      case StatusType.info:
        return (const Color(0xFFE3F2FD), const Color(0xFF1976D2), Icons.info);
      case StatusType.pending:
        return (
          const Color(0xFFFFF3E0),
          const Color(0xFFF57C00),
          Icons.schedule
        );
    }
  }
}

enum StatusType {
  success,
  warning,
  error,
  info,
  pending,
}

// Badge pour promotions
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isUrgent ? AppConstants.urgentColor : AppConstants.promoColor,
        borderRadius: BorderRadius.circular(6),
        gradient: isUrgent
            ? const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFF5252)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: Text(
        isUrgent ? 'URGENT' : '-${discount.round()}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// Badge pour disponibilité
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            isAvailable ? AppConstants.primaryColor : const Color(0xFFFFE0E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        customText ?? (isAvailable ? 'DISPONIBLE' : 'OCCUPÉ'),
        style: TextStyle(
          color: isAvailable ? Colors.white : const Color(0xFFD32F2F),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: AppConstants.ratingColor),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showReviews && reviews > 0) ...[
            const SizedBox(width: 4),
            Text(
              '($reviews)',
              style: const TextStyle(
                fontSize: 12,
                color: AppConstants.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Badge pour certification
class CertificationBadge extends StatelessWidget {
  final bool isCertified;

  const CertificationBadge({
    super.key,
    required this.isCertified,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCertified) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppConstants.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppConstants.primaryColor.withOpacity(0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 14, color: AppConstants.primaryColor),
          SizedBox(width: 4),
          Text(
            'CERTIFIÉ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppConstants.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
