import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../config/env.dart';
import '../storage/secure_store.dart';

/// Live push, shared across every chat surface in the app (service-request
/// comments, support-ticket messages, ...). One persistent WebSocket
/// connection for the whole session; callers subscribe to whichever per-user
/// queue they care about. Direct port of Angular's `ChatSocketService`.
///
/// The backend addresses messages per-user (`convertAndSendToUser`), never a
/// public `/topic`, so a socket only ever receives messages meant for the
/// authenticated user — see `ServiceRequestServiceImpl.pushChatMessage` /
/// `SupportMessageServiceImpl.pushChatMessage` on the backend.
///
/// Plain WebSocket (no SockJS) — matches `WebSocketConfig` on the backend.
///
/// The WebSocket handshake can't carry a normal Authorization header, so the
/// JWT travels as a `?token=` query param instead — `WebSocketAuthInterceptor`
/// on the backend validates it at the handshake and refuses the upgrade if
/// it's missing or invalid. Read once when the socket first activates, the
/// same as Angular does — neither side re-reads it mid-session, so a token
/// that rotates while connected is a gap this shares with the web app rather
/// than one this app introduces.
class ChatSocketService {
  ChatSocketService(this._store);

  final SecureStore _store;

  StompClient? _client;
  bool _activating = false;
  bool _connectedFlag = false;
  final List<_Subscription> _pending = [];
  final Map<String, StompUnsubscribe> _activeSubs = {};

  bool get connected => _connectedFlag;

  /// Subscribes to a per-user destination (e.g.
  /// `/user/queue/support-tickets/13/messages`). Returns an unsubscribe fn.
  void Function() subscribe(
    String destination,
    void Function(Map<String, dynamic> payload) handler,
  ) {
    final sub = _Subscription(destination, handler);
    _pending.add(sub);

    _ensureClient();
    if (_connectedFlag) _doSubscribe(sub);

    return () {
      _pending.remove(sub);
      _activeSubs.remove(destination)?.call();
    };
  }

  void _ensureClient() {
    if (_client != null || _activating) return;
    _activating = true;
    unawaited(_activate());
  }

  Future<void> _activate() async {
    final token = await _store.readAccessToken();
    final url = '${Env.wsUrl}/ws?token=${Uri.encodeQueryComponent(token ?? '')}';

    _client = StompClient(
      config: StompConfig(
        url: url,
        reconnectDelay: const Duration(seconds: 5),
        onConnect: (_) {
          _connectedFlag = true;
          // (Re)subscribe everything — covers both the first connect and any
          // reconnect after a dropped connection.
          for (final sub in _pending) {
            _doSubscribe(sub);
          }
        },
        onWebSocketDone: () {
          _connectedFlag = false;
          _activeSubs.clear();
        },
      ),
    )..activate();
  }

  void _doSubscribe(_Subscription sub) {
    final client = _client;
    if (client == null ||
        !_connectedFlag ||
        _activeSubs.containsKey(sub.destination)) {
      return;
    }
    _activeSubs[sub.destination] = client.subscribe(
      destination: sub.destination,
      callback: (frame) {
        final body = frame.body;
        if (body == null) return;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) sub.handler(decoded);
        } catch (_) {
          // Ignore a malformed frame — same as Angular's client.
        }
      },
    );
  }
}

class _Subscription {
  _Subscription(this.destination, this.handler);

  final String destination;
  final void Function(Map<String, dynamic>) handler;
}
