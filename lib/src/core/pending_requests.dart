import 'dart:async';

import '../protocol/vox_exceptions.dart';

class _PendingRequest {
  _PendingRequest({required this.type, required this.timeout});

  final String type;
  final Duration timeout;
  final Completer<Map<String, Object?>> completer =
      Completer<Map<String, Object?>>();
  Timer? timer;

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }
}

/// Correlates outbound requests with the replies Unity sends back.
///
/// The timeout deliberately does not start at [register] but at
/// [startTimeout], which the controller calls only once the message is really
/// written to the transport. A request sitting in the outbox while Unity is
/// paused should not burn its own timeout budget.
class PendingRequests {
  final Map<String, _PendingRequest> _pending = <String, _PendingRequest>{};
  int _counter = 0;

  /// Number of requests awaiting a reply.
  int get length => _pending.length;

  /// Generates a correlation id unique within this controller.
  String nextId() => 'c${_counter++}';

  /// Starts tracking a request and returns the future for its raw payload.
  Future<Map<String, Object?>> register(
    String id,
    String type,
    Duration timeout,
  ) {
    final pending = _PendingRequest(type: type, timeout: timeout);
    _pending[id] = pending;
    return pending.completer.future;
  }

  /// Begins the timeout clock for [id]. Safe to call for unknown ids.
  void startTimeout(String id) {
    final pending = _pending[id];
    if (pending == null || pending.timer != null) return;
    pending.timer = Timer(pending.timeout, () {
      _pending.remove(id);
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          VoxTimeoutException(
            type: pending.type,
            id: id,
            timeout: pending.timeout,
          ),
        );
      }
    });
  }

  /// Completes the request [id] with [payload]. Unknown ids are ignored.
  ///
  /// Returns whether a matching request was found, so the caller can warn about
  /// replies that arrive after a timeout or for an id that was never sent.
  bool complete(String id, Map<String, Object?> payload) {
    final pending = _pending.remove(id);
    if (pending == null) return false;
    pending.cancelTimer();
    if (!pending.completer.isCompleted) {
      pending.completer.complete(payload);
    }
    return true;
  }

  /// Fails the request [id] with [error]. Unknown ids are ignored.
  bool completeError(String id, Object error) {
    final pending = _pending.remove(id);
    if (pending == null) return false;
    pending.cancelTimer();
    if (!pending.completer.isCompleted) {
      pending.completer.completeError(error);
    }
    return true;
  }

  /// Fails every in-flight request with [error] and clears the map.
  void failAll(Object error) {
    final all = _pending.values.toList(growable: false);
    _pending.clear();
    for (final pending in all) {
      pending.cancelTimer();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
  }
}
