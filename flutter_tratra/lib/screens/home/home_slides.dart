// lib/screens/home/home_slides.dart
//
// Carrousel « À la une » : les diapositives viennent de l'API (/slides/) ; rien n'est codé
// en dur ici. L'image est facultative (repli sur le dégradé night de la marque).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tratra/design/design.dart';

import 'home_motion.dart';

class HomeSlide {
  const HomeSlide({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.ctaLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String image;
  final String ctaLabel;
  final VoidCallback onTap;
}

class HomeSlides extends StatefulWidget {
  const HomeSlides({super.key, required this.slides});

  final List<HomeSlide> slides;

  @override
  State<HomeSlides> createState() => _HomeSlidesState();
}

class _HomeSlidesState extends State<HomeSlides> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    final reduce = homeReduceMotion(context);
    final height = homeRowHeight(context, 196);

    return Column(
      children: [
        CarouselSlider.builder(
          itemCount: slides.length,
          options: CarouselOptions(
            height: height,
            viewportFraction: 0.92,
            enlargeCenterPage: true,
            enlargeFactor: 0.12,
            enableInfiniteScroll: slides.length > 1,
            autoPlay: !reduce && slides.length > 1,
            autoPlayInterval: const Duration(seconds: 5),
            autoPlayAnimationDuration: TtMotion.slow,
            autoPlayCurve: TtMotion.emphasized,
            onPageChanged: (i, _) => setState(() => _index = i),
          ),
          itemBuilder: (_, i, __) => _SlideCard(slide: slides[i]),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: TtSpace.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < slides.length; i++)
                AnimatedContainer(
                  duration: homeDuration(context),
                  curve: TtMotion.emphasized,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: i == _index ? 22 : 8,
                  decoration: BoxDecoration(
                    color: i == _index ? TtColors.accent : TtColors.line,
                    borderRadius: TtRadius.pillAll,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide});
  final HomeSlide slide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: slide.title.isEmpty ? slide.ctaLabel : '${slide.title}. ${slide.ctaLabel}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: TtRadius.cardAll, boxShadow: TtShadows.soft),
        child: Material(
          color: TtColors.night,
          shape: RoundedRectangleBorder(borderRadius: TtRadius.cardAll),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              slide.onTap();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(decoration: BoxDecoration(gradient: TtGradients.night)),
                if (slide.image.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: slide.image,
                    fit: BoxFit.cover,
                    fadeInDuration: TtMotion.base,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        TtColors.night.withValues(alpha: 0.92),
                        TtColors.night.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(TtSpace.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slide.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TratraTheme.style(TtType.h2, color: Colors.white),
                      ),
                      if (slide.subtitle.isNotEmpty) ...[
                        const SizedBox(height: TtSpace.s2),
                        Text(
                          slide.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TratraTheme.style(TtType.bodySm, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TratraButton(
                          label: slide.ctaLabel,
                          variant: TratraButtonVariant.accent,
                          trailing: const Icon(Icons.arrow_forward_rounded),
                          onPressed: slide.onTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
