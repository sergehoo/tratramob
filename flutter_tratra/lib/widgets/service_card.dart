// widgets/service_card.dart
import 'package:flutter/material.dart';
import '../models/service.dart';
import '../core/constants.dart';
import 'badge_widget.dart';

class ServiceCard extends StatelessWidget {
  final Service service;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;

  const ServiceCard({
    super.key,
    required this.service,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = service.hasDiscount;
    final discountPercent = hasDiscount
        ? (((service.price ?? 0) - (service.discountedPrice ?? 0)) /
                (service.price ?? 1) *
                100)
            .round()
        : 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppConstants.borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image et badges
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(
                    service.imageUrl,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                if (hasDiscount)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: BadgeWidget(
                      icon: Icons.local_offer,
                      label: '-$discountPercent%',
                      backgroundColor: AppConstants.promoColor,
                      textColor: Colors.white,
                    ),
                  ),
                if (service.isUrgent)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: BadgeWidget(
                      icon: Icons.warning,
                      label: 'Urgent',
                      backgroundColor: AppConstants.urgentColor,
                      textColor: Colors.white,
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color:
                          isFavorite ? AppConstants.promoColor : Colors.white,
                    ),
                    onPressed: onFavoriteToggle,
                  ),
                ),
              ],
            ),
            // Informations
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.categoryId,
                    style: const TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: AppConstants.ratingColor),
                      const SizedBox(width: 4),
                      Text(
                        service.rating.toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const Spacer(),
                      if (hasDiscount)
                        Text(
                          '${service.price}€',
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: AppConstants.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      if (hasDiscount) const SizedBox(width: 4),
                      Text(
                        hasDiscount
                            ? '${service.discountedPrice}€'
                            : '${service.price}€',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ],
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
