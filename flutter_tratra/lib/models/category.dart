// lib/models/category.dart
class Category {
  final String id; // on force String pour éviter int/String mismatch
  final String name;
  final String slug;
  final String? description;
  final String? icon; // nul dans ton payload
  final bool isActive;
  final String? parent;
  final String imageUrl; // UI friendly (vide si pas d’image côté API)

  Category({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    required this.isActive,
    this.parent,
    this.imageUrl = '',
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: (json['id'] ?? '')
          .toString(), // <— évite “int is not a subtype of String”
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      description: json['description'],
      icon: json['icon'],
      isActive: json['is_active'] ?? true,
      parent: json['parent']?.toString(),
      imageUrl: json['image'] ??
          json['image_url'] ??
          '', // si un jour tu ajoutes un champ image
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'icon': icon,
        'is_active': isActive,
        'parent': parent,
        'image_url': imageUrl,
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
