// lib/screens/home/home_icons.dart
//
// Pictogrammes des catégories : icône renvoyée par l'API (Font Awesome) en priorité,
// sinon pictogramme Material déduit du slug.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/models/category.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

const Map<String, IconData> _slugToMaterial = {
  'plomberie': Icons.plumbing,
  'electricite': Icons.electrical_services,
  'électricité': Icons.electrical_services,
  'peinture': Icons.format_paint,
  'menuiserie': Icons.carpenter,
  'nettoyage': Icons.cleaning_services,
  'demenagement': Icons.local_shipping,
  'déménagement': Icons.local_shipping,
  'jardinage': Icons.yard_outlined,
  'bricolage': Icons.build,
  'informatique': Icons.computer,
  'carrelage': Icons.grid_on,
};

const Map<String, IconData> _faMap = {
  'fa-road': FontAwesomeIcons.road,
  'fa-music': FontAwesomeIcons.music,
  'fa-laptop-code': FontAwesomeIcons.laptopCode,
  'fa-tools': FontAwesomeIcons.screwdriverWrench,
  'fa-border-style': FontAwesomeIcons.borderAll,
  'fa-wrench': FontAwesomeIcons.wrench,
  'fa-hammer': FontAwesomeIcons.hammer,
  'fa-broom': FontAwesomeIcons.broom,
  'fa-truck': FontAwesomeIcons.truck,
  'fa-brush': FontAwesomeIcons.brush,
  'fa-leaf': FontAwesomeIcons.leaf,
  'fa-bolt': FontAwesomeIcons.boltLightning,
  'fa-tree': FontAwesomeIcons.tree,
  'fa-paint-roller': FontAwesomeIcons.paintRoller,
  'fa-screwdriver-wrench': FontAwesomeIcons.screwdriverWrench,
  'fa-house': FontAwesomeIcons.house,
};

/// Pictogramme d'une catégorie (Font Awesome si l'API en fournit un connu, sinon Material).
Widget homeCategoryIcon(Category c, {required Color color, double size = 22}) {
  final apiIcon = c.icon;
  if (apiIcon != null && apiIcon.trim().isNotEmpty) {
    final parts = apiIcon.trim().split(RegExp(r'\s+'));
    final fa = _faMap[parts.isNotEmpty ? parts.last : ''];
    if (fa != null) return FaIcon(fa, color: color, size: size);
  }
  final material = _slugToMaterial[c.slug.toLowerCase()] ?? Icons.category_outlined;
  return Icon(material, color: color, size: size);
}
