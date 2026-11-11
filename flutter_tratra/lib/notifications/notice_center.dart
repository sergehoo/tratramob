// lib/notifications/notice_center.dart
//
// Rubans de notification, application OUVERTE. Une seule source : le message FCM reçu au premier plan (la WebSocket ne fait que
// synchroniser les écrans, elle n'affiche jamais de ruban) — donc jamais deux rubans pour un même évènement.
//  * un ruban à la fois, les suivants attendent (file bornée) : jamais de superposition ;
//  * dédoublonnage par identifiant d'évènement (numéro de la notification côté serveur, sinon identifiant du message FCM) ;
//  * Tratra Flash passe devant les autres et remplace le ruban ordinaire en cours ;
//  * disparition automatique après 5 secondes ; un ruban resté trop longtemps en attente n'est plus affiché (il reste dans le
//    centre de notifications, qui est la référence) ;
//  * rien n'est affiché pour un objet déjà à l'écran (conversation ouverte, demande suivie), ni par-dessus l'écran Tratra Flash.
import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_tratra/core/deep_links.dart';
import 'package:flutter_tratra/services/push_service.dart';

/// Identifiant d'évènement d'un message : le même évènement reçu deux fois (remise en double, reprise réseau) porte la même clé.
String? noticeKey(PushMessage m) {
  String? of(String field) {
    final v = '${m.data[field] ?? ''}'.trim();
    return v.isEmpty || v == '0' ? null : v;
  }

  final eid = of('eid');
  if (eid != null) return 'e:$eid';
  final nid = of('nid');
  if (nid != null) return 'n:$nid';
  if ('${m.data['t'] ?? ''}' == 'announcement' && of('id') != null) return 'a:${of('id')}';
  final mid = m.messageId;
  return mid == null || mid.isEmpty ? null : 'm:$mid';
}

/// Catégories discrètes : ruban sans signal sonore (annonces, conseils, informations, avis).
const Set<String> kQuietNoticeCategories = {'announcement', 'tips', 'system', 'review'};

@immutable
class AppNotice {
  const AppNotice({
    required this.message,
    required this.key,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.at,
  });

  final PushMessage message;
  final String? key;
  final String title;
  final String body;
  final String category;
  /// Tratra Flash (mission, proposition, contre-offre, désistement, annulation) : passe devant les autres.
  final bool priority;
  final DateTime at;

  DeepLink get link => parseDeepLink(message.data);
  bool get quiet => !priority && kQuietNoticeCategories.contains(category);

  /// Nul quand le message ne porte aucun texte à afficher (message de synchronisation).
  static AppNotice? fromPush(PushMessage m) {
    var title = (m.title ?? '').trim();
    var body = (m.body ?? '').trim();
    if (title.isEmpty && body.isEmpty) return null;
    if (title.isEmpty) {
      title = body;
      body = '';
    }
    final cat = '${m.data['cat'] ?? ''}'.trim();
    final category = cat.isNotEmpty ? cat : ('${m.data['t'] ?? ''}' == 'announcement' ? 'announcement' : 'system');
    final kind = parseDeepLink(m.data).kind;
    return AppNotice(
      message: m,
      key: noticeKey(m),
      title: title,
      body: body,
      category: category,
      priority: category == 'flash' || kind == DeepLinkKind.flashOffer || kind == DeepLinkKind.flashRequest,
      at: m.sentTime ?? clock.now(),
    );
  }
}

class _Waiting {
  _Waiting(this.notice, this.since, {this.replay = false});
  final AppNotice notice;
  final DateTime since;
  final bool replay;      // déjà montré une fois (remis en file par un ruban prioritaire) : pas de second signal sonore
}

class NoticeCenter extends ChangeNotifier {
  NoticeCenter({
    this.showFor = const Duration(seconds: 5),
    this.gap = const Duration(milliseconds: 350),
    this.maxQueue = 5,
    this.maxAge = const Duration(minutes: 2),
    this.minShown = const Duration(seconds: 2),
  });

  /// Durée d'affichage d'un ruban.
  final Duration showFor;
  /// Pause entre deux rubans (le premier a fini de sortir avant que le suivant n'entre).
  final Duration gap;
  final int maxQueue;
  /// Au-delà, un ruban en attente n'est plus affiché (le centre de notifications le garde).
  final Duration maxAge;
  /// Un ruban ordinaire remplacé par Tratra Flash avant ce délai est représenté ensuite.
  final Duration minShown;

  /// Ruban touché : ouvrir l'objet concerné.
  void Function(AppNotice notice)? onOpen;
  /// Ruban devenu visible (`replay` : il l'avait déjà été) : signal sonore.
  void Function(AppNotice notice, bool replay)? onShow;
  /// Vrai quand l'objet du ruban est déjà à l'écran : le ruban n'est pas affiché.
  bool Function(AppNotice notice)? suppress;

  /// Incrémenté à chaque message reçu application ouverte : le centre de notifications affiché se recharge.
  final ValueNotifier<int> arrivals = ValueNotifier<int>(0);

  final List<_Waiting> _queue = [];
  final LinkedHashSet<String> _shown = LinkedHashSet<String>();
  final LinkedHashSet<String> _opened = LinkedHashSet<String>();
  AppNotice? _current;
  DateTime? _currentSince;
  Timer? _hide;
  Timer? _next;
  int _hosts = 0;
  bool _held = false;
  bool _disposed = false;

  AppNotice? get current => _current;
  int get waiting => _queue.length;

  static void _remember(LinkedHashSet<String> set, String key) {
    set.add(key);
    while (set.length > 200) {
      set.remove(set.first);
    }
  }

  /// Message reçu application ouverte. Faux s'il n'est pas affiché (sans texte, déjà vu, objet déjà à l'écran).
  bool offer(PushMessage m) {
    if (_disposed) return false;
    final notice = AppNotice.fromPush(m);
    if (notice == null) return false;
    final key = notice.key;
    if (key != null) {
      if (_shown.contains(key)) return false;
      _remember(_shown, key);
    }
    if (suppress?.call(notice) ?? false) return false;
    _enqueue(_Waiting(notice, clock.now()));
    final shown = _current;
    if (notice.priority && shown != null && !shown.priority) {
      _end(requeue: clock.now().difference(_currentSince ?? clock.now()) < minShown);
    } else {
      _pump();
    }
    return true;
  }

  void _enqueue(_Waiting w, {bool front = false}) {
    // Tratra Flash d'abord (dans l'ordre d'arrivée), puis les autres.
    var at = w.notice.priority ? _queue.indexWhere((e) => !e.notice.priority) : _queue.length;
    if (at < 0) at = _queue.length;
    if (front) at = w.notice.priority ? 0 : _queue.where((e) => e.notice.priority).length;
    _queue.insert(at, w);
    while (_queue.length > maxQueue) {
      final drop = _queue.indexWhere((e) => !e.notice.priority);
      _queue.removeAt(drop < 0 ? 0 : drop);   // le plus ancien ruban ordinaire ; à défaut, le plus ancien
    }
  }

  void _pump() {
    if (_disposed || _current != null || _next != null || _held || _hosts == 0) return;
    final now = clock.now();
    while (_queue.isNotEmpty) {
      final w = _queue.removeAt(0);
      if (now.difference(w.since) > maxAge) continue;
      if (suppress?.call(w.notice) ?? false) continue;
      _current = w.notice;
      _currentSince = now;
      _hide = Timer(showFor, _end);
      notifyListeners();
      onShow?.call(w.notice, w.replay);
      return;
    }
  }

  void _end({bool requeue = false}) {
    final notice = _current;
    if (notice == null) return;
    _hide?.cancel();
    _hide = null;
    _current = null;
    if (requeue) _enqueue(_Waiting(notice, _currentSince ?? clock.now(), replay: true), front: true);
    _currentSince = null;
    notifyListeners();
    _next?.cancel();
    _next = Timer(gap, () {
      _next = null;
      _pump();
    });
  }

  /// Ferme le ruban affiché (bouton, glissement vers le haut).
  void dismiss() => _end();

  /// Ruban touché : il se ferme et l'objet concerné s'ouvre.
  void open() {
    final notice = _current;
    if (notice == null) return;
    if (notice.key != null) _remember(_opened, notice.key!);
    _end();
    onOpen?.call(notice);
  }

  /// Vrai la première fois qu'une notification touchée est ouverte : la même notification remise deux fois par le système
  /// (reprise, lancement à froid) n'ouvre qu'un écran.
  bool firstOpen(PushMessage m) {
    final key = noticeKey(m);
    if (key == null) return true;
    if (_opened.contains(key)) return false;
    _remember(_opened, key);
    _remember(_shown, key);     // déjà vue dans la barre du système : pas de ruban en plus si le message est remis ensuite
    return true;
  }

  /// Évènement dont l'objet est déjà à l'écran : retenu comme vu, sans ruban. Vrai la première fois seulement.
  bool markSeen(PushMessage m) {
    final key = noticeKey(m);
    if (key == null) return true;
    if (_shown.contains(key)) return false;
    _remember(_shown, key);
    return true;
  }

  /// L'écran Tratra Flash est affiché (sonnerie, décision à prendre) : aucun ruban par-dessus ; ils reprennent ensuite.
  void hold(bool value) {
    if (_held == value) return;
    _held = value;
    if (value) {
      if (_current != null) _end(requeue: true);
    } else {
      _pump();
    }
  }

  /// La zone d'affichage des rubans est en place (ou ne l'est plus) : sans elle, les rubans attendent.
  void attach() {
    _hosts++;
    _pump();
  }

  void detach() {
    if (_hosts > 0) _hosts--;
  }

  /// Déconnexion : plus aucun ruban du compte précédent.
  Future<void> clear() async {
    _hide?.cancel();
    _next?.cancel();
    _hide = null;
    _next = null;
    _queue.clear();
    _shown.clear();
    _opened.clear();
    final had = _current != null;
    _current = null;
    _currentSince = null;
    if (had && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _hide?.cancel();
    _next?.cancel();
    arrivals.dispose();
    super.dispose();
  }
}
