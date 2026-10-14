// lib/messaging/inbox_controller.dart
//
// Temps réel de la messagerie et des statuts : UNE WebSocket par session (billet signé de 60 s, reconnexion progressive), avec repli sur la
// lecture par l'API (rattrapage `GET /me/messages/sync/` et compteur) tant que la connexion est coupée. Le WebSocket n'est qu'un confort :
// les messages sont persistés par le serveur avant toute diffusion, rien n'est perdu pendant une coupure.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_tratra/core/base_api.dart';
import 'package:flutter_tratra/messaging/chat_models.dart';
import 'package:flutter_tratra/messaging/messaging_api.dart';
import 'package:flutter_tratra/screens/live/live_socket.dart';

enum InboxStatus { connecting, live, offline }

class InboxEvent {
  InboxEvent(this.type, {this.message, this.conversation, this.conversationId, this.upto, this.ids = const [], this.raw = const {}});
  final String type; // message | read | delivered | status | status_view | resync
  final ChatMessage? message;
  final ChatConversation? conversation;
  final int? conversationId;
  final int? upto;
  final List<int> ids;
  final Map<String, dynamic> raw;
}

typedef InboxSocketConnector = WebSocketChannel Function(Uri uri);

Duration inboxReconnectDelay(int attempt) => Duration(seconds: (1 << attempt.clamp(1, 6)).clamp(1, 30));

class InboxController extends ChangeNotifier with WidgetsBindingObserver {
  InboxController(
    this._base,
    this._api, {
    InboxSocketConnector? connect,
    Duration pollEvery = const Duration(seconds: 15),
    Duration Function(int attempt)? backoff,
    Duration requestTimeout = const Duration(seconds: 10),
  })  : _connect = connect ?? connectLiveSocket,
        _pollEvery = pollEvery,
        _backoff = backoff ?? inboxReconnectDelay,
        _requestTimeout = requestTimeout;

  final BaseApi _base;
  final MessagingApi _api;
  final InboxSocketConnector _connect;
  final Duration _pollEvery;
  final Duration Function(int attempt) _backoff;
  final Duration _requestTimeout;

  int unread = 0;
  InboxStatus status = InboxStatus.connecting;
  int lastMessageId = 0;

  final _events = StreamController<InboxEvent>.broadcast();
  Stream<InboxEvent> get events => _events.stream;

  String? _user;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _poll;
  int _attempt = 0;
  int _gen = 0;
  bool _disposed = false;
  bool _observing = false;

  bool get isLive => status == InboxStatus.live;

  /// Appelé à chaque changement de compte : coupe la connexion de l'ancien compte, ouvre celle du nouveau.
  Future<void> bindUser(String? userId) async {
    if (userId == _user) return;
    _stop();
    _user = userId;
    unread = 0;
    lastMessageId = 0;
    _notify();
    if (userId != null) _start();
  }

  void _start() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    refreshUnread();
    _openSocket();
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
      if (status != InboxStatus.live) _resync();
    });
  }

  void _stop() {
    _gen++;
    _retry?.cancel();
    _poll?.cancel();
    _closeSocket();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _user != null) {
      _attempt = 0;
      _openSocket();
      _resync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    _events.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _emit(InboxEvent e) {
    if (!_disposed && !_events.isClosed) _events.add(e);
  }

  Future<void> refreshUnread() async {
    try {
      final n = await _api.unreadTotal().timeout(_requestTimeout);
      if (n != unread) {
        unread = n;
        _notify();
      }
    } catch (_) {/* le compteur se met à jour à la prochaine occasion */}
  }

  /// Rattrapage : si des messages ont déjà été vus, ceux qui sont plus récents sont rejoués comme évènements ; dans tous les cas, les écrans
  /// rechargent leurs données par l'API (évènement `resync`).
  Future<void> _resync() async {
    try {
      if (lastMessageId > 0) {
        var after = lastMessageId;
        for (var i = 0; i < 5; i++) {
          final r = await _api.sync(after).timeout(_requestTimeout);
          final byId = {for (final c in r.conversations) c.id: c};
          for (final m in r.messages) {
            lastMessageId = m.id > lastMessageId ? m.id : lastMessageId;
            _emit(InboxEvent('message', message: m, conversation: byId[m.conversation], conversationId: m.conversation));
          }
          if (unread != r.unreadTotal) {
            unread = r.unreadTotal;
            _notify();
          }
          after = r.lastId;
          if (!r.hasMore) break;
        }
      } else {
        await refreshUnread();
      }
    } catch (_) {/* hors ligne : le prochain sondage réessaiera */}
    _emit(InboxEvent('resync'));
  }

  void _closeSocket() {
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.sink.close();
    } catch (_) {}
    _socket = null;
  }

  Future<void> _openSocket() async {
    if (_disposed || _user == null) return;
    _retry?.cancel();
    _closeSocket();
    final gen = ++_gen;
    if (status != InboxStatus.live) {
      status = InboxStatus.connecting;
      _notify();
    }
    try {
      final t = await _api.ticket().timeout(_requestTimeout);
      if (_disposed || gen != _gen) return;
      final base = Uri.parse(_base.baseUrl);
      final ws = Uri(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        host: base.host,
        port: base.hasPort ? base.port : null,
        path: t.path,
        queryParameters: {'ticket': t.ticket},
      );
      final channel = _connect(ws);
      _socket = channel;
      await channel.ready;
      if (_disposed || gen != _gen) {
        channel.sink.close();
        return;
      }
      _attempt = 0;
      status = InboxStatus.live;
      _notify();
      _sub = channel.stream.listen(
        (raw) => _onFrame(raw, channel),
        onDone: () => _closed(gen),
        onError: (_) => _closed(gen),
        cancelOnError: true,
      );
      _resync(); // rattrapage de ce qui a pu arriver pendant la coupure
    } catch (_) {
      _closed(gen);
    }
  }

  void _closed(int gen) {
    if (gen != _gen || _disposed) return;
    status = InboxStatus.offline;
    _notify();
    _attempt = (_attempt + 1).clamp(1, 6);
    _retry?.cancel();
    _retry = Timer(_backoff(_attempt), _openSocket);
  }

  void _onFrame(dynamic raw, WebSocketChannel channel) {
    final Object? d;
    try {
      d = json.decode('$raw');
    } catch (_) {
      return;
    }
    if (d is! Map) return;
    final m = d.cast<String, dynamic>();
    switch (m['type']) {
      case 'ready':
        final n = (m['unread_total'] as num?)?.toInt();
        if (n != null && n != unread) {
          unread = n;
          _notify();
        }
      case 'message':
        final msg = m['message'] is Map ? ChatMessage.fromJson((m['message'] as Map).cast<String, dynamic>()) : null;
        if (msg == null) return;
        final n = (m['unread_total'] as num?)?.toInt();
        if (n != null && n != unread) {
          unread = n;
          _notify();
        }
        if (msg.id > lastMessageId) lastMessageId = msg.id;
        if (!msg.mine) {
          try {
            channel.sink.add(json.encode({'type': 'ack', 'ids': [msg.id]})); // accusé : « distribué »
          } catch (_) {}
        }
        _emit(InboxEvent('message',
            message: msg,
            conversation: m['conversation'] is Map ? ChatConversation.fromJson((m['conversation'] as Map).cast<String, dynamic>()) : null,
            conversationId: msg.conversation));
      case 'read':
        refreshUnread();
        _emit(InboxEvent('read', conversationId: (m['conversation'] as num?)?.toInt(), upto: (m['upto'] as num?)?.toInt(), raw: m));
      case 'read_self':
        // Lu sur un autre appareil : seul le compteur est synchronisé (les messages du lecteur ne changent pas d'état).
        final n = (m['unread_total'] as num?)?.toInt();
        if (n != null && n != unread) {
          unread = n;
          _notify();
        }
        _emit(InboxEvent('resync'));
      case 'delivered':
        _emit(InboxEvent('delivered', ids: ((m['ids'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(), raw: m));
      case 'status' || 'status_view':
        _emit(InboxEvent('${m['type']}', raw: m));
    }
  }
}
