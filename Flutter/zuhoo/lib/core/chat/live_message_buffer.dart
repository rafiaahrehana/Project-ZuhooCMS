import 'chat_socket_service.dart';

/// Merges a live-pushed stream of chat messages into a GET-fetched list,
/// deduping by id and keeping ascending time order.
///
/// Every screen that pairs a fetched history with a [ChatSocketService] push
/// needs this same merge — a message that arrives live and one already in the
/// fetched page can be the same message (a reconnect can redeliver, and the
/// fetch and the first live push can race), so identity, not arrival order,
/// is what decides whether it is shown twice.
class LiveMessageBuffer<T> {
  LiveMessageBuffer({required this.idOf, required this.createdAtOf});

  final Object Function(T) idOf;
  final String Function(T) createdAtOf;

  final List<T> _live = [];

  void add(T message) => _live.add(message);

  List<T> merge(List<T> fetched) {
    final seen = fetched.map(idOf).toSet();
    final merged = [
      ...fetched,
      for (final message in _live)
        if (seen.add(idOf(message))) message,
    ];
    merged.sort((a, b) => createdAtOf(a).compareTo(createdAtOf(b)));
    return merged;
  }
}

/// Subscribes [socket] to [destination], decoding each push with [fromJson]
/// into [buffer] and calling [onMessage] (typically a `setState`) so the
/// caller re-renders with the newly merged list. Returns the unsubscribe fn.
void Function() connectLiveMessages<T>({
  required ChatSocketService socket,
  required String destination,
  required T Function(Map<String, dynamic>) fromJson,
  required LiveMessageBuffer<T> buffer,
  required void Function() onMessage,
}) {
  return socket.subscribe(destination, (payload) {
    buffer.add(fromJson(payload));
    onMessage();
  });
}
