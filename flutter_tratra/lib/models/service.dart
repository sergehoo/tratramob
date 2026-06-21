// models/service.dart
class Service {
  final String id;
  final String title;
  final String description;

  /// 'hourly', 'fixed', 'quote'
  final String priceType;

  /// Peut être null pour les services "quote"
  final double? price;

  final String handymanId;

  /// Identifiant et nom de la catégorie
  final String categoryId;
  final String categoryName;

  /// Durée en minutes → Duration
  final Duration? duration;

  /// Image principale (URL absolue, sinon placeholder)
  final String imageUrl;

  /// Images additionnelles (URLs absolues uniquement)
  final List<String> imageUrls;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Note moyenne éventuelle
  final double? rating;

  /// Nombre d’avis éventuel
  final int? reviewCount;

  /// Champs souvent utilisés ailleurs dans l’app
  final bool isUrgent;
  final double? discountedPrice;
  final List<String> includedServices;
  final List<String> requiredTools;

  Service({
    required this.id,
    required this.title,
    required this.description,
    required this.priceType,
    this.price,
    required this.handymanId,
    required this.categoryId,
    required this.categoryName,
    this.duration,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.rating,
    this.reviewCount,
    this.isUrgent = false,
    this.discountedPrice,
    this.includedServices = const [],
    this.requiredTools = const [],
    required String category,
  });

  // ----- Helpers d’affichage -----

  bool get hasDiscount =>
      discountedPrice != null &&
      price != null &&
      discountedPrice! > 0 &&
      discountedPrice! < price!;

  bool get isQuoteBased => priceType == 'quote';
  bool get isHourly => priceType == 'hourly';
  bool get isFixed => priceType == 'fixed';

  String get priceDisplay {
    if (isQuoteBased) return 'Sur devis';
    if (price == null) return 'Prix non spécifié';
    if (isHourly) return '${price!.toStringAsFixed(0)}F/h';
    return '${price!.toStringAsFixed(0)}F';
  }

  String get durationDisplay {
    if (duration == null) return 'Durée non spécifiée';
    final hours = duration!.inHours;
    final minutes = duration!.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}min';
    if (hours > 0) return '${hours}h';
    return '${minutes}min';
  }

  // ----- Parsing robuste depuis l’API -----

  factory Service.fromJson(Map<String, dynamic> json) {
    // Conversions tolérantes
    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    int? _toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    bool _toBool(dynamic v, {bool fallback = false}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase().trim();
        if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
        if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
      }
      return fallback;
    }

    Duration? _durationFromMinutes(dynamic v) {
      final m = _toInt(v);
      return (m == null) ? null : Duration(minutes: m);
    }

    String _safeAbsUrl(dynamic v) {
      final raw = (v ?? '').toString().trim();
      if (raw.isEmpty) return '';
      final u = Uri.tryParse(raw);
      if (u == null ||
          !u.hasScheme ||
          !(u.isScheme('http') || u.isScheme('https'))) {
        return '';
      }
      return raw;
    }

    // Catégorie (nom)
    String categoryName = '';
    if (json['category_detail'] is Map) {
      categoryName = (json['category_detail']['name'] ?? '').toString();
    } else if (json['category_name'] != null) {
      categoryName = json['category_name'].toString();
    }

    // Images : on NE CONSTRUIT PAS d’URL locale → on ne conserve que les URLs absolues
    String mainImageUrl = _safeAbsUrl(json['image_url']) // priorité image_url
            .isNotEmpty
        ? _safeAbsUrl(json['image_url'])
        : _safeAbsUrl(json['banner']);

    // Images supplémentaires (si la liste est fournie)
    List<String> additionalImages = [];
    if (json['images'] is List) {
      additionalImages = (json['images'] as List)
          .map((e) => (e is Map ? _safeAbsUrl(e['image'] ?? e['url']) : ''))
          .where((u) => u.isNotEmpty)
          .toList();
    }

    // Fallback sur la première image additionnelle si pas d’image principale
    if (mainImageUrl.isEmpty && additionalImages.isNotEmpty) {
      mainImageUrl = additionalImages.first;
      additionalImages = additionalImages.sublist(1);
    }

    // Fallback final
    if (mainImageUrl.isEmpty) {
      mainImageUrl =
          'https://via.placeholder.com/1000x600?text=Service'; // placeholder sûr
    }

    final price = _toDouble(json['price']);
    final discounted =
        _toDouble(json['discounted_price'] ?? json['promo_price']);
    final rating = _toDouble(json['rating_avg'] ?? json['rating']);
    final reviewCount = _toInt(json['review_count']);
    final duration = _durationFromMinutes(json['duration']);

    // Listes optionnelles
    List<String> included = const [];
    if (json['included_services'] is List) {
      included = (json['included_services'] as List)
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    List<String> tools = const [];
    if (json['required_tools'] is List) {
      tools = (json['required_tools'] as List)
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }

    return Service(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Service sans titre').toString(),
      description: (json['description'] ?? '').toString(),
      priceType: (json['price_type'] ?? 'hourly').toString(),
      price: price,
      handymanId: (json['handyman'] ?? '').toString(),
      categoryId: (json['category'] ?? '').toString(),
      categoryName: categoryName,
      duration: duration,
      imageUrl: mainImageUrl,
      imageUrls: additionalImages,
      isActive: _toBool(json['is_active'], fallback: true),
      createdAt: (json['created_at'] != null)
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: (json['updated_at'] != null)
          ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      rating: rating,
      reviewCount: reviewCount,
      isUrgent: _toBool(json['is_urgent']),
      discountedPrice: discounted,
      includedServices: included,
      requiredTools: tools,
      category: '',
    );
  }

  /// NE PAS préfixer avec un domaine interne : garder la valeur telle quelle si absolue,
  /// sinon laisser vide/placeholder (géré côté fromJson).
  static String _buildImageUrl(String imagePath) {
    final raw = imagePath.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '';
  }

  // ----- Sérialisation minimale -----
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price_type': priceType,
      'price': price,
      'handyman': handymanId,
      'category': categoryId,
      'duration': duration?.inMinutes,
      'banner': imageUrl,
      'is_active': isActive,
      'discounted_price': discountedPrice,
      'is_urgent': isUrgent,
      'included_services': includedServices,
      'required_tools': requiredTools,
    };
  }

  // ----- Factory pour des mocks -----
  factory Service.minimal({
    required String id,
    required String title,
    required String categoryName,
    required double price,
    required String imageUrl,
  }) {
    return Service(
      id: id,
      title: title,
      description: 'Description du service $title',
      priceType: 'hourly',
      price: price,
      handymanId: '1',
      categoryId: '1',
      categoryName: categoryName,
      duration: const Duration(hours: 2),
      imageUrl: imageUrl,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      rating: 4.5,
      reviewCount: 10,
      isUrgent: false,
      discountedPrice: null,
      includedServices: const [],
      requiredTools: const [],
      category: '',
    );
  }
}

// Modèle pour la catégorie de service
class ServiceCategory {
  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? icon;
  final bool isActive;
  final String? parentId;
  final List<ServiceCategory>? children;

  ServiceCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.icon,
    required this.isActive,
    this.parentId,
    this.children,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    bool _toBool(dynamic v, {bool fallback = false}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase().trim();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return fallback;
    }

    return ServiceCategory(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      description: json['description']?.toString(),
      icon: json['icon']?.toString(),
      isActive: _toBool(json['is_active'], fallback: true),
      parentId: json['parent']?.toString(),
      children: (json['children'] is List)
          ? (json['children'] as List)
              .map<ServiceCategory>((child) => ServiceCategory.fromJson(
                    Map<String, dynamic>.from(child as Map),
                  ))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'icon': icon,
      'is_active': isActive,
      'parent': parentId,
    };
  }
}

// Modèle pour les images de service
class ServiceImage {
  final String id;
  final String serviceId;
  final String imageUrl;
  final String? altText;
  final DateTime uploadedAt;

  ServiceImage({
    required this.id,
    required this.serviceId,
    required this.imageUrl,
    this.altText,
    required this.uploadedAt,
  });

  factory ServiceImage.fromJson(Map<String, dynamic> json) {
    String _safeAbsUrl(dynamic v) {
      final raw = (v ?? '').toString().trim();
      if (raw.isEmpty) return '';
      final u = Uri.tryParse(raw);
      if (u == null ||
          !u.hasScheme ||
          !(u.isScheme('http') || u.isScheme('https'))) {
        return '';
      }
      return raw;
    }

    return ServiceImage(
      id: (json['id'] ?? '').toString(),
      serviceId: (json['service'] ?? '').toString(),
      imageUrl: _safeAbsUrl(json['image'] ?? json['url']),
      altText: json['alt_text']?.toString(),
      uploadedAt: (json['uploaded_at'] != null)
          ? (DateTime.tryParse(json['uploaded_at'].toString()) ??
              DateTime.now())
          : DateTime.now(),
    );
  }
}

// ----- Extensions utilitaires -----
extension ServiceListExtensions on List<Service> {
  List<Service> get activeServices =>
      where((service) => service.isActive).toList();

  List<Service> get quoteBasedServices =>
      where((service) => service.isQuoteBased).toList();

  List<Service> get pricedServices =>
      where((service) => !service.isQuoteBased && service.price != null)
          .toList();

  List<Service> byCategory(String categoryId) =>
      where((service) => service.categoryId == categoryId).toList();

  List<Service> sortedByPrice({bool ascending = true}) {
    final list = List<Service>.from(this);
    list.sort((a, b) {
      final ap = a.price;
      final bp = b.price;
      if (ap == null && bp == null) return 0;
      if (ap == null) return 1;
      if (bp == null) return -1;
      return ascending ? ap.compareTo(bp) : bp.compareTo(ap);
    });
    return list;
  }

  List<Service> sortedByRating({bool ascending = false}) {
    final list = List<Service>.from(this);
    list.sort((a, b) {
      final ar = a.rating ?? double.negativeInfinity;
      final br = b.rating ?? double.negativeInfinity;
      return ascending ? ar.compareTo(br) : br.compareTo(ar);
    });
    return list;
  }
}

// ----- Données mock pour le développement -----
class MockServices {
  static final List<Service> services = [
    Service.minimal(
      id: '1',
      title: 'Réparation de fuite d\'eau',
      categoryName: 'Plomberie',
      price: 15000,
      imageUrl:
          'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?q=80&w=1000',
    ),
    Service.minimal(
      id: '2',
      title: 'Installation électrique',
      categoryName: 'Électricité',
      price: 20000,
      imageUrl:
          'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?q=80&w=1000',
    ),
    Service.minimal(
      id: '3',
      title: 'Peinture intérieure',
      categoryName: 'Peinture',
      price: 12000,
      imageUrl:
          'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?q=80&w=1000',
    ),
    Service.minimal(
      id: '4',
      title: 'Nettoyage profond',
      categoryName: 'Nettoyage',
      price: 8000,
      imageUrl:
          'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?q=80&w=1000',
    ),
  ];

  static final List<ServiceCategory> categories = [
    ServiceCategory(
      id: '1',
      name: 'Plomberie',
      slug: 'plomberie',
      description: 'Services de plomberie et réparation',
      icon: 'fa-wrench',
      isActive: true,
    ),
    ServiceCategory(
      id: '2',
      name: 'Électricité',
      slug: 'electricite',
      description: 'Installation et réparation électrique',
      icon: 'fa-bolt',
      isActive: true,
    ),
    ServiceCategory(
      id: '3',
      name: 'Peinture',
      slug: 'peinture',
      description: 'Services de peinture intérieure et extérieure',
      icon: 'fa-paint-roller',
      isActive: true,
    ),
    ServiceCategory(
      id: '4',
      name: 'Nettoyage',
      slug: 'nettoyage',
      description: 'Services de nettoyage et entretien',
      icon: 'fa-broom',
      isActive: true,
    ),
  ];
}
