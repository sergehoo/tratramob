// lib/continuity/offline_queue.dart
//
// File d'attente hors ligne PERSISTANTE, limitée aux actions SÛRES : sans effet financier ni métier, idempotentes ou
// sans conséquence si elles sont rejouées (marquer une notification lue, signaler la vue / l'ouverture d'une annonce).
//
//  * Les actions CRITIQUES (créer ou annuler une réservation, démarrer / terminer une mission, payer) ne passent
//    JAMAIS par cette file : [enqueue] les refuse. Elles ne sont affichées comme réussies qu'après confirmation du
//    serveur ; hors ligne, l'écran dit « non envoyée » et conserve un brouillon (voir drafts.dart).
//  * Envoi dans l'ordre, arrêt à la première panne réseau (reprise automatique à la synchronisation suivante) ;
//    erreur définitive (400/403/404/410/422) : l'action est abandonnée ; conflit (409/412) : abandonnée et signalée.
//  * Doublons exacts fusionnés ; 200 actions et 7 jours au maximum ; chiffrée, cloisonnée par compte, effacée au logout.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_tratra/continuity/vault.dart';

class QueuedAction {
  QueuedAction({required this.method, required this.path, this.body, DateTime? createdAt, this.attempts = 0})
      : createdAt = createdAt ?? DateTime.now();

  final String method;
  final String path;
  final Map<String, dynamic>? body;
  final DateTime createdAt;
  int attempts;

  bool sameAs(String m, String p, Map<String, dynamic>? b) => m == method && p == path && mapEquals(b ?? const {}, body ?? const {});

  Map<String, dynamic> toJson() =>
      {'method': method, 'path': path, 'body': body, 'created_at': createdAt.toIso8601String(), 'attempts': attempts};

  factory QueuedAction.fromJson(Map<String, dynamic> j) => QueuedAction(
        method: '${j['method']}',
        path: '${j['path']}',
        body: (j['body'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.tryParse('${j['created_at']}'),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      );
}

/// Envoie une action et renvoie le code HTTP ; lève une exception en cas de panne réseau (l'action reste en file).
typedef QueueSender = Future<int> Function(QueuedAction action);

class OfflineQueue extends ChangeNotifier {
  OfflineQueue({required QueueSender send, ContinuityVault? vault, DateTime Function()? now})
      : _send = send,
        _vault = vault ?? ContinuityVault(),
        _now = now ?? DateTime.now;

  final QueueSender _send;
  final ContinuityVault _vault;
  final DateTime Function() _now;

  static const int maxEntries = 200;
  static const Duration maxAge = Duration(days: 7);
  static const String _name = 'queue';

  /// Liste blanche : (méthode, chemin) des seules actions sûres.
  static final List<(String, RegExp)> _safe = [
    ('POST', RegExp(r'^/notifications/mark-read/$')),
    ('PATCH', RegExp(r'^/notifications/\d+/$')),
    ('POST', RegExp(r'^/me/announcements/\d+/(seen|open)/$')),
  ];

  static bool isSafe(String method, String path, [Map<String, dynamic>? body]) {
    if (!_safe.any((s) => s.$1 == method && s.$2.hasMatch(path))) return false;
    // Une notification ne se « dé-lit » pas : seul `{is_read: true}` est une action sûre.
    if (method == 'PATCH') return body != null && body.length == 1 && body['is_read'] == true;
    return true;
  }

  String? _userId;
  List<QueuedAction> _items = [];
  bool _flushing = false;
  String? _problem;

  int get pending => _items.length;
  String? get lastProblem => _problem;
  List<QueuedAction> get items => List.unmodifiable(_items);

  Future<void> bindUser(String? userId) async {
    if (userId == _userId) return;
    _userId = userId;
    _items = [];
    _problem = null;
    notifyListeners();
    if (userId == null) return;
    final raw = await _vault.read(userId, _name);
    if (userId != _userId || raw is! List) return;
    final cutoff = _now().subtract(maxAge);
    _items = raw.whereType<Map>().map((m) => QueuedAction.fromJson(m.cast<String, dynamic>())).where((a) => a.createdAt.isAfter(cutoff)).toList();
    notifyListeners();
  }

  Future<void> _persist() async {
    final uid = _userId;
    if (uid == null) return;
    if (_items.isEmpty) {
      await _vault.delete(uid, _name);
    } else {
      await _vault.write(uid, _name, _items.map((a) => a.toJson()).toList());
    }
  }

  /// Met l'action en file (persistée) puis tente de l'envoyer. Refuse toute action non « sûre ».
  Future<void> enqueue(String method, String path, [Map<String, dynamic>? body]) async {
    if (!isSafe(method, path, body)) {
      throw ArgumentError('Action non éligible à la file hors ligne : $method $path');
    }
    if (_userId == null) return;
    if (!_items.any((a) => a.sameAs(method, path, body))) {
      _items.add(QueuedAction(method: method, path: path, body: body, createdAt: _now()));
      if (_items.length > maxEntries) _items.removeAt(0);
      await _persist();
      notifyListeners();
    }
    await flush();
  }

  /// Envoie dans l'ordre ; s'arrête à la première panne réseau (reprise au prochain appel).
  Future<void> flush() async {
    if (_flushing || _userId == null) return;
    _flushing = true;
    final uid = _userId;
    try {
      while (_items.isNotEmpty && uid == _userId) {
        final action = _items.first;
        final int code;
        try {
          code = await _send(action);
        } catch (_) {
          action.attempts++;
          await _persist();
          break; // réseau indisponible : on garde tout, dans l'ordre
        }
        if (code == 401 || code == 408 || code == 429 || code >= 500) {
          action.attempts++; // session à renouveler ou serveur occupé : réessai plus tard, rien n'est perdu
          await _persist();
          break;
        }
        if (code == 409 || code == 412) _problem = 'Une action a été abandonnée : l’élément a été modifié entre-temps.';
        _items.removeAt(0); // succès, erreur définitive ou conflit : plus rien à rejouer
        await _persist();
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  void clearProblem() {
    if (_problem == null) return;
    _problem = null;
    notifyListeners();
  }

  /// Déconnexion volontaire.
  Future<void> wipe() async {
    _userId = null;
    _items = [];
    _problem = null;
    await _vault.wipeAll();
    notifyListeners();
  }
}
