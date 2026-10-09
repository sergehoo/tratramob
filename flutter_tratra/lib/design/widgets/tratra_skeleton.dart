import 'package:flutter/material.dart';

import '../tokens.dart';

/// Balayage lumineux partagé par tout un sous-arbre de squelettes (une seule animation).
/// Neutralisé quand l'utilisateur réduit les animations.
class TratraShimmer extends StatefulWidget {
  const TratraShimmer({super.key, required this.child});
  final Widget child;

  @override
  State<TratraShimmer> createState() => _TratraShimmerState();
}

class _TratraShimmerState extends State<TratraShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = (_c.value * 2.4 - 0.7) * rect.width;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.65), Colors.white.withValues(alpha: 0)],
            stops: const [0.0, 0.5, 1.0],
            transform: _SlideTransform(dx),
          ).createShader(rect);
        },
        child: child,
      ),
    );
  }
}

class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.dx);
  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx - bounds.width / 2, 0, 0);
}

/// Bloc squelette statique (à envelopper dans un `TratraShimmer`).
class TratraSkeletonBox extends StatelessWidget {
  const TratraSkeletonBox({super.key, this.width, this.height = 14, this.radius = TtRadius.control, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: TtColors.line.withValues(alpha: 0.7),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// Squelette autonome (bloc + balayage) pour un usage ponctuel.
class TratraSkeleton extends StatelessWidget {
  const TratraSkeleton({super.key, this.width, this.height = 14, this.radius = TtRadius.control, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: TratraShimmer(child: TratraSkeletonBox(width: width, height: height, radius: radius, circle: circle)),
      );
}

/// Quelques lignes de texte ; la dernière est plus courte.
class TratraSkeletonText extends StatelessWidget {
  const TratraSkeletonText({super.key, this.lines = 3});
  final int lines;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: TratraShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines; i++) ...[
                FractionallySizedBox(
                  widthFactor: i == lines - 1 && lines > 1 ? 0.6 : 1,
                  child: const TratraSkeletonBox(height: 13),
                ),
                if (i != lines - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      );
}

/// Carte de liste en chargement (pastille, deux lignes, badge).
class TratraSkeletonCard extends StatelessWidget {
  const TratraSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TtColors.surface,
          borderRadius: TtRadius.cardAll,
          border: Border.all(color: TtColors.lineSoft),
          boxShadow: TtShadows.soft,
        ),
        child: const Row(
          children: [
            TratraSkeletonBox(width: 48, height: 48, radius: TtRadius.panel),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TratraSkeletonBox(width: 150, height: 14),
                  SizedBox(height: 10),
                  TratraSkeletonBox(width: 100, height: 12),
                ],
              ),
            ),
            SizedBox(width: 12),
            TratraSkeletonBox(width: 64, height: 24, radius: TtRadius.pill),
          ],
        ),
      );
}

/// Liste de cartes en chargement, annoncée une seule fois aux lecteurs d'écran.
class TratraSkeletonList extends StatelessWidget {
  const TratraSkeletonList({super.key, this.count = 3, this.padding = const EdgeInsets.all(16)});
  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Chargement en cours',
        liveRegion: true,
        child: ExcludeSemantics(
          child: TratraShimmer(
            child: Padding(
              padding: padding,
              child: Column(
                children: [
                  for (var i = 0; i < count; i++) ...[
                    const TratraSkeletonCard(),
                    if (i != count - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
