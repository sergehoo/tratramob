// lib/models/category.dart
/// Entrée du catalogue commun (`GET /handy/catalog/`) : un MÉTIER (catégorie racine, `parent == null`) ou une PRESTATION (sous-catégorie).
/// Les offres des professionnels se rattachent à une catégorie ; `offersTotal` compte les offres du métier ET de ses prestations.
class Category {
  final String id; // on force String pour éviter int/String mismatch
  final String name;
  final String slug;
  final String? description;
  final String? icon; // saisie dans l'administration (« fa-solid fa-utensils »)
  final String? iconKey; // clé normalisée par le serveur (« utensils ») : même icône que le site
  final bool isActive;
  final String? parent;
  final String imageUrl; // UI friendly (vide si pas d’image côté API)

  /// Identifiant du métier (racine) auquel appartient l'entrée ; son propre identifiant pour un métier.
  final String? trade;
  final int position;

  /// Rang dans l'arbre du catalogue (métier puis ses prestations) : l'ordre d'affichage commun au site et à l'application.
  final int? order;
  final bool isFeatured;
  final int? offersCount;
  final int? offersTotal;
  final int prestationsCount;

  Category({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    this.iconKey,
    required this.isActive,
    this.parent,
    this.imageUrl = '',
    this.trade,
    this.position = 100,
    this.order,
    this.isFeatured = false,
    this.offersCount,
    this.offersTotal,
    this.prestationsCount = 0,
  });

  /// Métier (catégorie racine) ou prestation (sous-catégorie).
  bool get isTrade => parent == null || parent!.isEmpty;

  factory Category.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
    return Category(
      id: (json['id'] ?? '')
          .toString(), // <— évite “int is not a subtype of String”
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'],
      icon: json['icon'],
      iconKey: json['icon_key']?.toString(),
      isActive: json['is_active'] ?? true,
      parent: json['parent']?.toString(),
      imageUrl: json['image'] ??
          json['image_url'] ??
          '', // si un jour tu ajoutes un champ image
      trade: json['trade']?.toString(),
      position: asInt(json['position']) ?? 100,
      order: asInt(json['order']),
      isFeatured: json['is_featured'] == true,
      offersCount: asInt(json['offers_count']),
      offersTotal: asInt(json['offers_total'] ?? json['services_count']),
      prestationsCount: asInt(json['prestations_count']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'icon': icon,
        'icon_key': iconKey,
        'is_active': isActive,
        'parent': parent,
        'image_url': imageUrl,
        'trade': trade,
        'position': position,
        'order': order,
        'is_featured': isFeatured,
        'offers_count': offersCount,
        'offers_total': offersTotal,
        'prestations_count': prestationsCount,
      };
}

// // lib/models/category.dart
// class Category {
//   final String id;
//   final String name;

//   // Champs optionnels côté UI
//   final String? description;
//   final String? icon; // ex: nom d’icône côté back
//   final String? image; // ex: chemin/nom brut renvoyé par le back

//   // Champs utilisés par l’app
//   final String slug; // requis par l’UI (filtrage/routage)
//   final String imageUrl; // URL absolue pour l’affichage
//   final int? serviceCount;
//   final bool isActive;

//   Category({
//     required this.id,
//     required this.name,
//     required this.slug,
//     required this.imageUrl,
//     this.description,
//     this.icon,
//     this.image,
//     this.serviceCount,
//     required this.isActive,
//   });

//   factory Category.fromJson(Map<String, dynamic> json) {
//     // Le back peut renvoyer: image_url, image ou rien.
//     // On priorise image_url; sinon image; sinon vide.
//     final String resolvedImageUrl =
//         (json['image_url'] ?? json['image'] ?? '').toString();

//     return Category(
//       id: (json['id'] ?? '').toString(),
//       name: (json['name'] ?? '').toString(),
//       slug: (json['slug'] ?? '').toString(), // <-- requis par l’UI
//       imageUrl: resolvedImageUrl, // <-- requis par l’UI
//       description: json['description']?.toString(),
//       icon: json['icon']?.toString(),
//       image: json['image']?.toString(),
//       serviceCount: json['service_count'] is int
//           ? json['service_count'] as int
//           : int.tryParse('${json['service_count'] ?? ''}'),
//       isActive: (json['is_active'] ?? true) == true,
//     );
//   }

//   Map<String, dynamic> toJson() => {
//         'id': id,
//         'name': name,
//         'slug': slug,
//         'image_url': imageUrl,
//         'description': description,
//         'icon': icon,
//         'image': image,
//         'service_count': serviceCount,
//         'is_active': isActive,
//       };
// }
