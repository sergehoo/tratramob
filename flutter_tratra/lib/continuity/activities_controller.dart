// lib/continuity/activities_controller.dart
//
// Reprise des activités : au démarrage, après une reconnexion, au retour au premier plan et après une coupure réseau,
// l'application interroge le serveur (source de vérité) et affiche d'abord le dernier état connu (coffre chiffré,
// cloisonné par compte) pour que l'utilisateur retrouve immédiatement sa mission, même hors ligne.
//
//  * en ligne : liste serveur (remplace l'état local), curseur `server_time` mémorisé pour `?since=` ;
//  * hors ligne / serveur injoignable : dernier état connu conservé, drapeau `offline` et heure de dernière synchro —
//    jamais présenté comme à jour ; nouvelles tentatives espacées (8 s → 60 s) jusqu'au retour du réseau ;
//  * changement fait ailleurs (autre téléphone, annulation par l'autre partie) : message « mise à jour » une fois ;
//  * changement de compte : tout est purgé avant de charger le nouveau compte ; déconnexion volontaire : [wipe].
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_tratra/continuity/activity.dart';
import 'package:flutter_tratra/continuity/vault.dart';

typedef ActivityFetch = Future<Map<String, dynamic>> Function(String path);

class ActivitiesController extends ChangeNotifier with WidgetsBindingObserver {
  ActivitiesController({
    required ActivityFetch fetch,
    ContinuityVault? vault,
    this.minInterval = const Duration(seconds: 5),
    this.retryBase = const Duration(seconds: 8),
    this.retryMax = const Duration(seconds: 60),
    this.poll = const Duration(seconds: 60),
    DateTime Function()? now,
  })  : _fetch = fetch,
        _vault = vault ?? ContinuityVault(),
        _now = now ?? DateTime.now;

  final ActivityFetch _fetch;
  final ContinuityVault _vault;
  final DateTime Function() _now;
  final Duration minInterval;
  final Duration retryBase;
  final Duration retryMax;
  final Duration poll;

  /// Appelé après chaque synchronisation réussie (ex. vidage de la file hors ligne).
  Future<void> Function()? onSynced;

  static const String _cacheName = 'activities';

  String? _userId;
  List<Activity> _items = const [];
  Activity? _primary;
  DateTime? _syncedAt;
  String? _cursor;
  bool _offline = false;
  bool _fromCache = false;
  bool _loading = false;
  String? _notice;
  bool _refreshing = false;
  DateTime? _lastAttempt;
  int _failures = 0;
  Timer? _retry;
  Timer? _poller;

  List<Activity> get items => _items;
  Activity? get primary => _primary;
  bool get hasActive => _items.isNotEmpty;
  DateTime? get syncedAt => _syncedAt;
  bool get offline => _offline;
  bool get fromCache => _fromCache;
  bool get loading => _loading;
  String? get notice => _notice;
  String? get userId => _userId;

  // ---- cycle de vie -----------------------------------------------------------------------------------------------

  /// Écoute le retour au premier plan et lance une relève régulière tant que l'application est ouverte.
  void startObserving() {
    WidgetsBinding.instance.addObserver(this);
    _poller?.cancel();
    _poller = Timer.periodic(poll, (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh(force: true));
  }

  /// Compte courant (null = déconnecté). Un nouveau compte repart d'un état vide avant toute lecture.
  Future<void> bindUser(String? userId) async {
    if (userId == _userId) return;
    _reset();
    _userId = userId;
    notifyListeners();
    if (userId == null) return;
    await _restore(userId);
    await refresh(force: true);
  }

  void _reset() {
    _retry?.cancel();
    _items = const [];
    _primary = null;
    _syncedAt = null;
    _cursor = null;
    _offline = false;
    _fromCache = false;
    _loading = false;
    _notice = null;
    _failures = 0;
    _lastAttempt = null;
  }

  /// Déconnexion volontaire : mémoire ET coffre sont vidés (aucune donnée sensible ne reste sur le téléphone).
  Future<void> wipe() async {
    _userId = null;
    _reset();
    await _vault.wipeAll();
    notifyListeners();
  }

  // ---- lecture ----------------------------------------------------------------------------------------------------

  Future<void> _restore(String userId) async {
    final cached = await _vault.read(userId, _cacheName);
    if (cached is! Map || userId != _userId) return;
    _items = _parse(cached['items']);
    _primary = _items.isEmpty ? null : _items.first;
    _syncedAt = DateTime.tryParse('${cached['synced_at'] ?? ''}');
    _cursor = cached['cursor']?.toString();
    _fromCache = _items.isNotEmpty;
    notifyListeners();
  }

  static List<Activity> _parse(Object? raw) =>
      (raw is List ? raw : const []).whereType<Map>().map((m) => Activity.fromJson(m.cast<String, dynamic>())).toList();

  Future<void> refresh({bool force = false}) async {
    final uid = _userId;
    if (uid == null || _refreshing) return;
    final t = _now();
    if (!force && _lastAttempt != null && t.difference(_lastAttempt!) < minInterval) return;
    _lastAttempt = t;
    _refreshing = true;
    _loading = _items.isEmpty;
    notifyListeners();
    try {
      final since = _cursor;
      final body = await _fetch(since == null ? '/me/activities/' : '/me/activities/?since=${Uri.encodeQueryComponent(since)}');
      if (uid != _userId) return; // le compte a changé pendant la requête : réponse ignorée
      final previous = _items;
      final next = _parse(body['activities']);
      _notice = _noticeFor(previous, next, _parse(body['changes'])) ?? _notice;
      _items = next;
      final primary = body['primary'];
      _primary = primary is Map ? Activity.fromJson(primary.cast<String, dynamic>()) : null;
      _cursor = body['server_time']?.toString() ?? _cursor;
      _syncedAt = DateTime.tryParse('${body['server_time'] ?? ''}') ?? _now();
      _offline = false;
      _fromCache = false;
      _failures = 0;
      _retry?.cancel();
      await _vault.write(uid, _cacheName, {
        'synced_at': _syncedAt!.toIso8601String(),
        'cursor': _cursor,
        'items': next.map((a) => a.toJson()).toList(),
      });
      final hook = onSynced;
      if (hook != null) unawaited(hook().catchError((_) {}));
    } catch (_) {
      if (uid != _userId) return;
      _offline = true; // dernier état connu conservé, signalé comme tel
      _scheduleRetry();
    } finally {
      _refreshing = false;
      _loading = false;
      notifyListeners();
    }
  }

  /// Activités qui étaient en cours chez nous et qui, d'après le serveur, ont changé ailleurs (terminées, annulées).
  String? _noticeFor(List<Activity> before, List<Activity> after, List<Activity> changes) {
    final stillActive = after.map((a) => a.key).toSet();
    final lines = <String>[];
    for (final c in changes.where((c) => !c.active)) {
      final wasActive = before.any((b) => b.key == c.key);
      if (wasActive && !stillActive.contains(c.key)) lines.add('« ${c.title} » : ${c.statusLabel.toLowerCase()}.');
    }
    return lines.isEmpty ? null : 'Mise à jour depuis un autre appareil ou l’autre partie — ${lines.join(' ')}';
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _failures++;
    final base = retryBase.inMilliseconds;
    final cap = retryMax.inMilliseconds < base ? base : retryMax.inMilliseconds; // plafond jamais sous la base
    final ms = base * (1 << (_failures - 1).clamp(0, 6));
    final delay = Duration(milliseconds: ms > cap ? cap : ms);
    _retry = Timer(delay, () => refresh(force: true));
  }

  @override
  void dispose() {
    _retry?.cancel();
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
