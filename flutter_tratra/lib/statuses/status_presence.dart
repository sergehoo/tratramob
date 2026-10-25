// lib/statuses/status_presence.dart
//
// Qui a un statut ? Comme WhatsApp, l'avatar d'un membre porte un anneau dès qu'il a un statut que je peux voir — à l'accueil, dans la
// messagerie, sur son profil — vert par segment non vu, gris une fois vu ; le toucher ouvre ses statuts. Une seule source pour toute
// l'application (`/statuses/presence/`), rafraîchie par le temps réel (publication, vue, rattrapage) et au plus toutes les 20 s sinon.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tratra/design/design.dart';
import 'package:flutter_tratra/messaging/inbox_controller.dart';
import 'package:flutter_tratra/statuses/status_api.dart';
import 'package:flutter_tratra/statuses/status_bar.dart';
import 'package:flutter_tratra/statuses/status_models.dart';

class StatusPresence extends ChangeNotifier {
  StatusPresence(this._api, InboxController inbox, {this.minInterval = const Duration(seconds: 20)}) {
    _sub = inbox.events.listen((e) {
      if (e.type == 'status' || e.type == 'status_view' || e.type == 'resync') unawaited(refresh(force: true));
    });
  }

  final StatusApi _api;
  final Duration minInterval;
  StreamSubscription<InboxEvent>? _sub;
  Map<int, StatusPresenceEntry> _byUser = const {};
  String? _userId;
  DateTime? _loadedAt;
  Future<void>? _pending;

  StatusPresenceEntry? of(int? userId) => userId == null ? null : _byUser[userId];

  /// Un statut non vu d'un autre membre : pastille sur l'icône des statuts.
  bool get hasUnseen => _byUser.values.any((e) => !e.mine && e.unseen > 0);

  /// Changement de compte : rien de l'ancien compte ne reste affiché.
  void bindUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _byUser = const {};
    _loadedAt = null;
    notifyListeners();
    if (userId != null) unawaited(refresh(force: true));
  }

  Future<void> refresh({bool force = false}) {
    if (_userId == null) return Future.value();
    final fresh = _loadedAt != null && DateTime.now().difference(_loadedAt!) < minInterval;
    if (fresh && !force) return Future.value();
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  Future<void> _load() async {
    final user = _userId;
    try {
      final rows = await _api.presence();
      if (user != _userId) return;
      _byUser = {for (final r in rows) r.userId: r};
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Statuts indisponibles : les avatars restent simples, rien d'autre n'est dégradé.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Présence des statuts si elle est fournie (écrans de test isolés : avatars simples).
StatusPresence? maybeStatusPresence(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<StatusPresence>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Ouvre les statuts d'un membre (toucher son avatar) puis met les anneaux à jour.
Future<void> openMemberStatuses(BuildContext context, int userId) async {
  final presence = maybeStatusPresence(context, listen: false);
  try {
    final group = await context.read<StatusApi>().author(userId);
    if (!context.mounted) return;
    await openStatusViewer(context, [group], 0);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Ce statut n’est plus disponible.')));
    }
  } finally {
    unawaited(presence?.refresh(force: true));
  }
}

/// Avatar d'un membre avec l'anneau de ses statuts s'il en a (un segment par statut, vert si non vu, gris si vu) ; le toucher ouvre ses
/// statuts. Sans statut : avatar simple (et `onTap` éventuel).
class StatusAvatar extends StatelessWidget {
  const StatusAvatar({super.key, required this.userId, required this.name, this.photoUrl, this.size = 44, this.onTap, this.online = false});
  final int? userId;
  final String name;
  final String? photoUrl;
  final double size;
  final VoidCallback? onTap;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final entry = maybeStatusPresence(context)?.of(userId);
    final avatar = TratraAvatar(name: name, photoUrl: photoUrl, size: size, online: online);
    if (entry == null) {
      return onTap == null ? avatar : InkWell(customBorder: const CircleBorder(), onTap: onTap, child: avatar);
    }
    final unseen = entry.mine ? 0 : entry.unseen;
    return Semantics(
      button: true,
      label: 'Statuts de $name${unseen > 0 ? ', $unseen non lu${unseen > 1 ? 's' : ''}' : ''}',
      child: InkWell(
        key: ValueKey('status-avatar-${entry.userId}'),
        customBorder: const CircleBorder(),
        onTap: () => openMemberStatuses(context, entry.userId),
        child: StatusRing(unseen: unseen > 0, count: entry.count, unseenCount: unseen, size: size + 10, child: avatar),
      ),
    );
  }
}
