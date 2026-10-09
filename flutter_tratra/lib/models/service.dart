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

  /// Durée réellement renseignée (une durée nulle ou 0 min n'est pas affichée).
  bool get hasDuration => duration != null && duration!.inMinutes > 0;

  String get durationDisplay {
    if (!hasDuration) return 'Durée non spécifiée';
    final hours = duration!.inHours;
    final minutes = duration!.inMinutes.remainder(60);
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}min';
    if (hours > 0) return '${hours}h';
    return '${minutes}min';
  }

  // ----- Parsing robuste depuis l’API -----

  factory Service.fromJson(Map<String, dynamic> json) {
    // Conversions tolérantes
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.'));
      return null;
    }

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    bool toBool(dynamic v, {bool fallback = false}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase().trim();
        if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
        if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
      }
      return fallback;
    }

    Duration? durationFromMinutes(dynamic v) {
      final m = toInt(v);
      return (m == null) ? null : Duration(minutes: m);
    }

    String safeAbsUrl(dynamic v) {
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
    String mainImageUrl = safeAbsUrl(json['image_url']) // priorité image_url
            .isNotEmpty
        ? safeAbsUrl(json['image_url'])
        : safeAbsUrl(json['banner']);

    // Images supplémentaires (si la liste est fournie)
    List<String> additionalImages = [];
    if (json['images'] is List) {
      additionalImages = (json['images'] as List)
          .map((e) => (e is Map ? safeAbsUrl(e['image'] ?? e['url']) : ''))
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

    final price = toDouble(json['price']);
    final discounted =
        toDouble(json['discounted_price'] ?? json['promo_price']);
    final rating = toDouble(json['rating_avg'] ?? json['rating']);
    final reviewCount = toInt(json['review_count']);
    final duration = durationFromMinutes(json['duration']);

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
      isActive: toBool(json['is_active'], fallback: true),
      createdAt: (json['created_at'] != null)
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: (json['updated_at'] != null)
          ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      rating: rating,
      reviewCount: reviewCount,
      isUrgent: toBool(json['is_urgent']),
      discountedPrice: discounted,
      includedServices: included,
      requiredTools: tools,
      category: '',
    );
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
    bool toBool(dynamic v, {bool fallback = false}) {
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
      isActive: toBool(json['is_active'], fallback: true),
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
    String safeAbsUrl(dynamic v) {
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
      imageUrl: safeAbsUrl(json['image'] ?? json['url']),
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

