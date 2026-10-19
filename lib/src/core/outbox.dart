import 'dart:collection';

import '../protocol/vox_envelope.dart';

/// A bounded FIFO queue for messages that cannot be sent yet.
///
/// Messages are queued when the handshake has not completed, or while Unity is
/// paused. Pausing zeroes Unity's time scale, so a handler that replies from a
/// coroutine would never run and the request would time out for no good reason
/// — queuing until resume avoids that.
class VoxOutbox {
  /// Creates an outbox holding at most [capacity] messages.
  VoxOutbox({this.capacity = 128, this.onDropped})
    : assert(capacity > 0, 'capacity must be positive');

  /// Maximum number of queued messages before the oldest is dropped.
  final int capacity;

  /// Called with any envelope evicted because the queue was full.
  final void Function(VoxEnvelope dropped)? onDropped;

  final Queue<VoxEnvelope> _queue = Queue<VoxEnvelope>();

  /// Number of queued messages.
  int get length => _queue.length;

  /// Whether anything is queued.
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Queues [envelope], evicting the oldest message if already at [capacity].
  ///
  /// Dropping the oldest keeps the most recent intent, which is usually what a
  /// caller wants after a long pause.
  void add(VoxEnvelope envelope) {
    if (_queue.length >= capacity) {
      onDropped?.call(_queue.removeFirst());
    }
    _queue.add(envelope);
  }

  /// Removes and returns everything queued, in the order it was added.
  List<VoxEnvelope> drain() {
    final drained = _queue.toList(growable: false);
    _queue.clear();
    return drained;
  }

  /// Discards everything queued without sending it.
  void clear() => _queue.clear();
}
