// lib/screens/home/home_motion.dart
//
// Micro-animations de l'accueil : discrètes (≤ 420 ms, courbe `emphasized`) et neutralisées
// quand l'utilisateur réduit les animations.
import 'package:flutter/material.dart';
import 'package:flutter_tratra/design/design.dart';

bool homeReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Durée effective : nulle si les animations sont réduites.
Duration homeDuration(BuildContext context, [Duration d = TtMotion.base]) =>
    homeReduceMotion(context) ? Duration.zero : d;

/// Hauteur d'une rangée horizontale, agrandie (jusqu'à +30 %) avec la taille de texte
/// du système pour éviter tout débordement.
double homeRowHeight(BuildContext context, double base) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return base * scale.clamp(1.0, 1.3);
}

/// Apparition en fondu + légère montée, avec un décalage optionnel (effet d'escalier).
class HomeReveal extends StatefulWidget {
  const HomeReveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<HomeReveal> createState() => _HomeRevealState();
}

class _HomeRevealState extends State<HomeReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TtMotion.slow + widget.delay,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMilliseconds / (TtMotion.slow + widget.delay).inMilliseconds,
      1,
      curve: TtMotion.emphasized,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (homeReduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_t),
        child: widget.child,
      ),
    );
  }
}
