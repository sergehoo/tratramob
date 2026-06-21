// lib/models/hero_slide_model.dart
class HeroSlideModel {
  final String title;
  final String subtitle;
  final String image;
  final List<String> gradient; // ex: ["#00B14F", "#00D25F"]
  final String ctaLabel;
  final String
      ctaAction; // open_services | open_categories | open_category | open_artisans | open_url
  final Map<String, dynamic>
      ctaParams; // ex: { "category_id": 3 } ou { "url": "https://..." }

  HeroSlideModel({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.gradient,
    required this.ctaLabel,
    required this.ctaAction,
    required this.ctaParams,
  });

  factory HeroSlideModel.fromJson(Map<String, dynamic> j) {
    return HeroSlideModel(
      title: (j['title'] ?? '').toString(),
      subtitle: (j['subtitle'] ?? '').toString(),
      image: (j['image'] ?? '').toString(),
      gradient: ((j['gradient'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      ctaLabel: (j['cta_label'] ?? 'Découvrir').toString(),
      ctaAction: (j['cta_action'] ?? 'open_services').toString(),
      ctaParams: (j['ctaParams'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          ) ??
          const {},
    );
  }
}
