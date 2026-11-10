// lib/flash/flash_search.dart
//
// Suivi en direct d'une demande Tratra Flash côté client (recherche façon VTC). L'état arrive par la WebSocket du membre (évènement
// `flash_request` : phase, rayon, compteurs) ; l'API `GET /flash/requests/<id>/` reste la référence et sert la reprise : ouverture de
// l'écran, retour au premier plan, reconnexion, message en double ou en retard (`seq` croissant), changement de version (propositions,
// professionnel retenu). Sans WebSocket, lecture périodique. Chaque requête a un délai maximal : jamais de chargement infini.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import 'package:flutter_tratra/flash/flash_api.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';

const Set<String> kFlashOpen = {'searching', 'quoting', 'awaiting'};

/// Bloc « recherche » renvoyé par le serveur (API et WebSocket).
class FlashSearch {
  FlashSearch(this.raw);
  final Map<String, dynamic> raw;

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  int get seq => _int(raw['seq']);
  String get phase => '${raw['phase'] ?? 'search'}';
  String get phaseLabel => '${raw['phase_label'] ?? ''}';
  bool get progressive => raw['progressive'] == true;
  int get radiusM => _int(raw['radius_m']);
  String get radiusLabel => '${raw['radius_label'] ?? ''}';
  List<int> get stepsM => ((raw['steps_m'] as List?) ?? const []).map(_int).toList();
  int? get nextStepIn => raw['next_step_in'] == null ? null : _int(raw['next_step_in']);
  Map<String, dynamic> get far => raw['far'] is Map ? (raw['far'] as Map).cast<String, dynamic>() : const {};
  bool get needsConsent => far['needs_consent'] == true;
  int get availableBeyond => _int(far['available_beyond']);
  num get farKm => (far['threshold_km'] as num?) ?? 30;
  Map<String, dynamic> get counts => raw['counts'] is Map ? (raw['counts'] as Map).cast<String, dynamic>() : const {};
  int count(String key) => _int(counts[key]);
}

class FlashRequestLive extends ChangeNotifier with WidgetsBindingObserver {
  FlashRequestLive({
    required this.api,
    required this.requestId,
    Stream<InboxEvent>? events,
    bool Function()? socketLive,
    this.pollEvery = const Duration(seconds: 5),
    this.livePollEvery = const Duration(seconds: 30),
    this.observeLifecycle = true,
  }) : _socketLive = socketLive ?? (() => false) {
    _sub = events?.listen(_onEvent);
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _schedulePoll();
  }

  final FlashApi api;
  final int requestId;
  final Duration pollEvery;
  final Duration livePollEvery;
  final bool observeLifecycle;
  final bool Function() _socketLive;

  Map<String, dynamic>? data;
  String? error;          // aucune donnée affichable (introuvable, ou jamais chargée)
  bool offline = false;   // la dernière mise à jour a échoué : l'état affiché peut être ancien
  bool loading = false;
  StreamSubscription<InboxEvent>? _sub;
  Timer? _poll;
  Timer? _catchUp;
  bool _disposed = false;
  int _gen = 0;

  FlashSearch get search => FlashSearch(data?['search'] is Map ? (data!['search'] as Map).cast<String, dynamic>() : const {});
  String get status => '${data?['status'] ?? ''}';
  bool get isOpen => kFlashOpen.contains(status);

  Future<void> start() => refresh();

  Future<void> refresh() async {
    final gen = ++_gen;
    loading = true;
    _notify();
    try {
      final d = await api.request(requestId);
      if (_disposed || gen != _gen) return;
      final incoming = d['search'] is Map ? FlashSearch((d['search'] as Map).cast<String, dynamic>()).seq : 0;
      if (data != null && incoming < search.seq) {
        // Lecture partie AVANT un évènement déjà reçu par la WebSocket (ex. devis reçu puis vague suivante) : elle ne doit pas
        // écraser l'état plus récent ; une nouvelle lecture suit aussitôt.
        _catchUp?.cancel();
        _catchUp = Timer(const Duration(milliseconds: 700), () => unawaited(refresh()));
        return;
      }
      _apply(d);
      offline = false;
      error = null;
    } on FlashApiError catch (e) {
      if (_disposed || gen != _gen) return;
      if (e.status == 404 || data == null) error = e.status == 404 ? 'Cette demande n’existe pas sur ce compte.' : e.message;
      offline = e.status >= 500;
    } catch (_) {
      if (_disposed || gen != _gen) return;
      offline = true;
      if (data == null) error = 'Connexion impossible. Vérifiez votre connexion puis réessayez.';
    } finally {
      if (!_disposed && gen == _gen) {
        loading = false;
        _notify();
        _schedulePoll();
      }
    }
  }

  /// Réponse d'une action (annuler, élargir, contre-offre, choisir…) : même forme que la lecture.
  void apply(Map<String, dynamic> d) {
    _apply(d);
    offline = false;
    error = null;
    _notify();
    _schedulePoll();
  }

  void _apply(Map<String, dynamic> d) {
    if (d.isEmpty) {
      data ??= d;
      return;
    }
    data = d;
  }

  void _onEvent(InboxEvent e) {
    if (e.type != 'flash_request') return;
    final raw = e.raw;
    if ('${raw['id']}' != '$requestId') return;
    final incoming = raw['search'] is Map ? FlashSearch((raw['search'] as Map).cast<String, dynamic>()) : null;
    if (incoming == null || data == null) {
      unawaited(refresh());
      return;
    }
    final previous = search;
    if (incoming.seq <= previous.seq) return;                     // message en double ou arrivé en retard
    final versionChanged = '${raw['version']}' != '${data!['version']}';
    data = {...data!, 'status': raw['status'] ?? data!['status'], 'status_label': raw['status_label'] ?? data!['status_label'],
        'search': incoming.raw};
    offline = false;
    _notify();
    // Propositions reçues, professionnel retenu, demande close : le détail complet vient de l'API.
    if (versionChanged || incoming.phase != previous.phase || incoming.count('proposals') != previous.count('proposals') ||
        incoming.count('responses') != previous.count('responses')) {
      unawaited(refresh());
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (_disposed || (data != null && !isOpen)) return;
    _poll = Timer(_socketLive() ? livePollEvery : pollEvery, () => unawaited(refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());   // reprise après mise en arrière-plan
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _catchUp?.cancel();
    _sub?.cancel();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
