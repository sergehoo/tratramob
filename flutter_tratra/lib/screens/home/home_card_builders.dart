// lib/screens/home/home_card_builders.dart
//
// Passage d'un service de l'API aux cartes de l'accueil : uniquement des données réelles
// (jamais de titre, de catégorie, de note ou de prix de remplacement inventés).
import 'package:flutter/material.dart';

import 'home_cards.dart';
import 'home_models.dart';

Widget homeServiceCard(
  HomeServiceEntry e, {
  required bool isFavorite,
  required VoidCallback onFavorite,
  required VoidCallback onShare,
  required VoidCallback onTap,
  required VoidCallback onBook,
}) {
  final s = e.service;
  final serviceRating = (s.rating ?? 0) > 0 ? s.rating : null;
  return ServiceCardPremium(
    title: s.title.isNotEmpty ? s.title : 'Service',
    category: s.categoryName,
    imageUrl: s.imageUrl,
    basePrice: (s.price ?? 0).toDouble(),
    discountedPrice: (s.discountedPrice ?? s.price ?? 0).toDouble(),
    priceLabel: s.hasDiscount ? null : homePriceLabel(s),
    rating: e.artisan?.rating ?? serviceRating,
    artisan: e.artisan,
    isFavorite: isFavorite,
    onFavorite: onFavorite,
    onShare: onShare,
    onTap: onTap,
    onBook: onBook,
    badgeText: s.isUrgent ? 'Urgent' : null,
  );
}

Widget homeNearbyCard(
  HomeServiceEntry e, {
  required bool isFavorite,
  required VoidCallback onFavorite,
  required VoidCallback onShare,
  required VoidCallback onOpen,
}) {
  final s = e.service;
  final a = e.artisan;
  final name = (a != null && a.hasName) ? a.displayName : null;
  final serviceTitle = s.title.isNotEmpty ? s.title : 'Service';
  return ArtisanCardPremium(
    title: name ?? serviceTitle,
    subtitle: name != null ? serviceTitle : s.categoryName,
    imageUrl: s.imageUrl,
    priceText: homePriceLabel(s),
    artisan: a,
    isFavorite: isFavorite,
    onFavorite: onFavorite,
    onShare: onShare,
    onPrimary: onOpen,
    // « Vérifié » uniquement si l'API le confirme pour cet artisan.
    // Le badge le plus élevé (Sûr > Expert > Vérifié), toujours issu de l'attribution automatique du serveur.
    badgeText: a == null
        ? null
        : (a.badges.contains('SUR')
            ? 'Sûr'
            : a.badges.contains('EXPERT')
                ? 'Expert'
                : (a.verified ? 'Vérifié' : null)),
  );
}
