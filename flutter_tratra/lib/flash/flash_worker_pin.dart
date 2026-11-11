// lib/flash/flash_worker_pin.dart
//
// Repère d'un professionnel sollicité sur la carte d'une recherche Tratra Flash : pictogramme « travailleuse » ou « travailleur » selon
// le genre que la personne a elle-même indiqué dans son profil, casque seul si elle n'a rien indiqué (jamais deviné d'après le prénom).
// L'anneau dit l'état de la proposition : sollicité (vert, onde), proposition reçue (jaune), retenu (vert plein), décliné ou sans
// réponse (estompé). Dessins vectoriels embarqués : aucune image réseau.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/flash/flash_search.dart';

const _helmet = '<path d="M13.2 19.6a10.8 10.8 0 0 1 21.6 0z" fill="#F6C90E"/>'
    '<rect x="22.3" y="7.4" width="3.4" height="7.6" rx="1.7" fill="#D4AA00"/>'
    '<rect x="10.6" y="18.4" width="26.8" height="3.6" rx="1.8" fill="#D4AA00"/>';
const _face = '<rect x="20.4" y="27" width="7.2" height="8" rx="2.4" fill="#8A5A3C"/>'
    '<path d="M16 20.5h16v3.4a8 8 0 0 1-16 0z" fill="#A9714B"/>';
const _collar = '<path d="M19.6 34.4l4.4 4.4 4.4-4.4" fill="none" stroke="#F6C90E" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>';

/// Travailleur : épaules larges, casque de chantier.
const kWorkerManSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
    '<path d="M7 47c0-9.4 7.4-14.4 17-14.4S41 37.600 41 47z" fill="#2E8B57"/>$_face$_collar$_helmet</svg>';

/// Travailleuse : cheveux longs sous le casque, épaules plus étroites.
const kWorkerWomanSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
    '<path d="M14.200 20h19.600c2.600 4.800 3.400 11.200 2 17.600H12.200c-1.400-6.400-.6-12.800 2-17.600z" fill="#0B1210"/>'
    '<path d="M9.600 47c0-8.800 6.400-13.600 14.400-13.600S38.400 38.200 38.400 47z" fill="#2E8B57"/>$_face$_collar$_helmet</svg>';

/// Genre non indiqué : le casque seul.
const kWorkerNeutralSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
    '<path d="M9.500 31a14.500 14.500 0 0 1 29 0z" fill="#F6C90E"/>'
    '<rect x="21.700" y="13.600" width="4.600" height="10.400" rx="2.300" fill="#D4AA00"/>'
    '<rect x="6" y="29.400" width="36" height="5.200" rx="2.600" fill="#D4AA00"/></svg>';

class FlashWorkerPin extends StatelessWidget {
  const FlashWorkerPin({super.key, required this.pro, this.pulse});
  final FlashProPoint pro;

  /// Onde des professionnels en attente de réponse (animation de la carte) ; absente : repère fixe.
  final Animation<double>? pulse;

  static const double size = 52;
  static const double _disc = 38;

  String get _svg => pro.gender == 'F' ? kWorkerWomanSvg : pro.gender == 'M' ? kWorkerManSvg : kWorkerNeutralSvg;

  @override
  Widget build(BuildContext context) {
    final ring = switch (pro.state) {
      'proposal' => TtColors.accentDark,
      'selected' => TtColors.primaryDark,
      'declined' || 'no_answer' => TtColors.fog,
      _ => TtColors.primary,
    };
    final badge = switch (pro.state) {
      'proposal' => (Icons.local_offer_rounded, TtColors.accent, TtColors.night),
      'selected' => (Icons.check_rounded, TtColors.primary, Colors.white),
      _ => null,
    };
    final disc = Container(
      width: _disc,
      height: _disc,
      decoration: BoxDecoration(
        color: pro.state == 'selected' ? TtColors.primarySoft : TtColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: pro.state == 'selected' ? 3 : 2.5),
        boxShadow: pro.out ? null : [BoxShadow(color: TtColors.night.withValues(alpha: 0.22), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.only(top: 2), child: SvgPicture.string(_svg, width: 30, height: 30)),
    );
    return Semantics(
      label: pro.label,
      image: true,
      excludeSemantics: true,
      // Apparition : le repère « pousse » quand sa vague sollicite le professionnel.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.3, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Opacity(
          opacity: pro.out ? 0.5 : 1,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(alignment: Alignment.center, children: [
              if (pulse != null && pro.state == 'contacted')
                AnimatedBuilder(
                  animation: pulse!,
                  builder: (_, __) {
                    final v = (pulse!.value * 2) % 1;
                    return Container(
                      width: _disc + (size - _disc) * v,
                      height: _disc + (size - _disc) * v,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: TtColors.primary.withValues(alpha: 0.28 * (1 - v))),
                    );
                  },
                ),
              disc,
              if (badge != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(color: badge.$2, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                    child: Icon(badge.$1, size: 10, color: badge.$3),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Place les repères à l'écran sans qu'ils se recouvrent — ni entre eux, ni avec le repère du lieu de l'intervention.
///
/// À grande échelle (rayon de 30 km et plus) un repère couvre plusieurs kilomètres : sans cela, les professionnels proches
/// disparaîtraient tous sous le repère central. La direction réelle est conservée ; seule la distance est portée au minimum
/// lisible. Les positions reçues sont déjà approximatives : rien de précis n'est perdu. Ordre stable (identifiant) : un repère
/// déjà affiché ne saute pas quand une nouvelle vague arrive.
Map<int, LatLng> spreadPros(LatLng center, List<FlashProPoint> pros, double metersPerPx, {double clearPx = 38, double gapPx = 36}) {
  if (!(metersPerPx > 0)) return {for (final p in pros) p.id: p.point};
  final kx = 111320 * math.cos(center.latitude * math.pi / 180), ky = 110540.0;
  final placed = <Offset>[];
  final out = <int, LatLng>{};
  bool free(Offset o) => o.distance >= clearPx - 0.5 && placed.every((q) => (q - o).distance >= gapPx);
  Offset px(FlashProPoint p) =>
      Offset((p.point.longitude - center.longitude) * kx / metersPerPx, (p.point.latitude - center.latitude) * ky / metersPerPx);
  final sorted = [...pros]..sort((a, b) => a.id.compareTo(b.id));
  // D'abord ceux qui sont lisibles à leur vraie place (ils la gardent), ensuite ceux qu'il faut écarter du centre.
  for (final p in [...sorted.where((p) => px(p).distance >= clearPx), ...sorted.where((p) => px(p).distance < clearPx)]) {
    var pos = px(p);
    // Confondu avec le centre : direction stable tirée de l'identifiant (angle d'or), jamais du hasard.
    final a = pos.distance < 1 ? p.id * 2.39996 : math.atan2(pos.dy, pos.dx);
    final moved = pos.distance < clearPx;
    if (moved) pos = Offset(math.cos(a), math.sin(a)) * clearPx;
    if (!free(pos)) {
      search:
      for (var ring = 1; ring <= 4; ring++) {
        for (final t in const [0.0, 1.05, -1.05, 2.1, -2.1, 3.14]) {
          final o = pos + Offset(math.cos(a + t), math.sin(a + t)) * (gapPx * ring);
          if (free(o)) {
            pos = o;
            break search;
          }
        }
      }
    }
    placed.add(pos);
    out[p.id] = moved || pos != px(p)
        ? LatLng(center.latitude + pos.dy * metersPerPx / ky, center.longitude + pos.dx * metersPerPx / kx)
        : p.point;
  }
  return out;
}
