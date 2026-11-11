// lib/notifications/screen_presence.dart
//
// Écrans « objet » actuellement ouverts (une conversation, une demande Tratra Flash). Sert à deux choses :
//  * ne pas afficher de ruban pour ce que l'utilisateur regarde déjà ;
//  * une notification touchée ramène sur l'écran déjà ouvert au lieu d'en empiler un second.
import 'package:flutter/widgets.dart';

import 'package:flutter_tratra/core/deep_links.dart';

abstract final class ScreenPresence {
  static final Map<String, List<ModalRoute<dynamic>>> _open = {};

  /// Cible d'un lien profond, quand son écran s'annonce ici.
  static String? targetOf(DeepLink link) => switch (link.kind) {
        DeepLinkKind.conversation when link.id != null => 'conversation:${link.id}',
        DeepLinkKind.flashRequest when link.id != null => 'flash_request:${link.id}',
        _ => null,
      };

  static void enter(String target, ModalRoute<dynamic> route) => (_open[target] ??= []).add(route);

  static void leave(String target, ModalRoute<dynamic> route) {
    final routes = _open[target];
    if (routes == null) return;
    routes.remove(route);
    if (routes.isEmpty) _open.remove(target);
  }

  static ModalRoute<dynamic>? _route(String? target) {
    final routes = target == null ? null : _open[target];
    if (routes == null) return null;
    for (final r in routes.reversed) {
      if (r.isActive) return r;
    }
    return null;
  }

  /// L'écran de cette cible est celui que l'utilisateur a sous les yeux.
  static bool isVisible(String? target) => _route(target)?.isCurrent ?? false;

  /// Ramène sur l'écran déjà ouvert de cette cible. Faux s'il ne l'est pas : à l'appelant de l'ouvrir.
  static bool reveal(String? target) {
    final route = _route(target);
    final nav = route?.navigator;
    if (route == null || nav == null) return false;
    if (!route.isCurrent) nav.popUntil((r) => r == route || r.isFirst);
    return route.isCurrent;
  }

  @visibleForTesting
  static void reset() => _open.clear();
}

/// À mêler à l'état d'un écran « objet » : il s'annonce tant qu'il est dans la pile.
mixin ScreenPresenceMixin<T extends StatefulWidget> on State<T> {
  String get presenceTarget;

  String? _target;
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _route)) return;
    _unregister();
    _target = presenceTarget;
    _route = route;
    ScreenPresence.enter(_target!, route);
  }

  void _unregister() {
    final target = _target, route = _route;
    if (target != null && route != null) ScreenPresence.leave(target, route);
    _target = null;
    _route = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }
}
