import 'dart:async';

import 'package:flutter/foundation.dart';

import '../lifecycle/app_lifecycle_binder.dart';
import '../protocol/vox_builtin.dart';
import '../protocol/vox_codec.dart';
import '../protocol/vox_envelope.dart';
import '../protocol/vox_exceptions.dart';
import '../protocol/vox_message.dart';
import '../protocol/vox_registry.dart';
import '../transport/embed_unity_transport.dart';
import '../transport/vox_transport.dart';
import 'outbox.dart';
import 'pause_reasons.dart';
import 'pending_requests.dart';
import 'vox_state.dart';

/// Owns the Unity bridge: handshake, message routing, request correlation,
/// pause/resume and state.
///
/// Usually there is exactly one of these per app, since Unity itself is a
/// single process-wide instance. Either let [VoxView] create one implicitly, or
/// construct one, hold it somewhere long-lived, and pass it to [VoxView].
///
/// ```dart
/// final vox = VoxController();
/// vox.registry.register<PlayerDied>('game.playerDied', PlayerDied.fromPayload);
///
/// await vox.ready;
/// final health = await vox.request(GetHealthRequest());
/// vox.on<PlayerDied>().listen(print);
/// ```
class VoxController extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [transport] defaults to the real `flutter_embed_unity` transport; pass a
  /// fake to drive the controller without Unity.
  VoxController({
    VoxTransport? transport,
    VoxRegistry? registry,
    this.gameObjectName = defaultGameObjectName,
    this.methodName = defaultMethodName,
    this.defaultTimeout = const Duration(seconds: 10),
    this.handshakeTimeout = const Duration(seconds: 30),
    int outboxCapacity = 128,
    bool bindAppLifecycle = true,
  }) : _transport = transport ?? EmbedUnityTransport(),
       registry = registry ?? VoxRegistry() {
    _outbox = VoxOutbox(
      capacity: outboxCapacity,
      onDropped: (dropped) => _log(
        'outbox full (capacity $outboxCapacity), dropped oldest: $dropped',
      ),
    );
    if (bindAppLifecycle) {
      _appLifecycle = AppLifecycleBinder(
        onBackgrounded: () => addPauseReason(VoxPauseReason.appBackgrounded),
        onForegrounded: () => removePauseReason(VoxPauseReason.appBackgrounded),
      )..bind();
    }
  }

  /// Name of the Unity game object hosting `VoxBridge.cs`.
  static const String defaultGameObjectName = 'VoxBridge';

  /// Name of the public method on `VoxBridge.cs` that receives messages.
  static const String defaultMethodName = 'OnFlutterMessage';

  /// Retry schedule for the handshake probe, capped at the final entry.
  static const List<Duration> _helloBackoff = [
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// Maps inbound message types to typed event classes.
  final VoxRegistry registry;

  /// The Unity game object messages are addressed to.
  final String gameObjectName;

  /// The Unity method messages are addressed to.
  final String methodName;

  /// Timeout applied to [request] when none is given.
  final Duration defaultTimeout;

  /// How long to keep probing before giving up on the handshake.
  final Duration handshakeTimeout;

  final VoxTransport _transport;
  final VoxCodec _codec = const VoxCodec();
  final PendingRequests _pending = PendingRequests();
  final PauseCoordinator _pauses = PauseCoordinator();
  late final VoxOutbox _outbox;

  final StreamController<VoxEvent> _events =
      StreamController<VoxEvent>.broadcast();
  final StreamController<VoxState> _states =
      StreamController<VoxState>.broadcast();
  final StreamController<String> _rawMessages =
      StreamController<String>.broadcast();

  AppLifecycleBinder? _appLifecycle;
  Completer<void> _readyCompleter = Completer<void>();
  Timer? _helloTimer;
  Timer? _handshakeDeadline;
  int _helloAttempt = 0;
  int _attachCount = 0;
  bool _disposed = false;

  /// What the transport has actually been told, as opposed to what the pause
  /// reasons currently want. Keeps [_syncTransportPause] idempotent.
  bool _transportPaused = false;

  VoxState _state = const VoxState.initial();

  /// The current snapshot. Also available via [ChangeNotifier] notifications.
  VoxState get state => _state;

  /// Snapshots emitted on every change.
  Stream<VoxState> get states => _states.stream;

  /// Every decoded event pushed from Unity.
  Stream<VoxEvent> get events => _events.stream;

  /// Every raw string received from Unity, before decoding.
  ///
  /// An escape hatch for debugging and for messages that do not follow the vox
  /// envelope format.
  Stream<String> get rawMessages => _rawMessages.stream;

  /// Completes when the handshake succeeds, or errors if it fails.
  Future<void> get ready => _readyCompleter.future;

  /// Events of type [T] only.
  Stream<T> on<T extends VoxEvent>() => _events.stream.where((e) => e is T).cast<T>();

  // ---------------------------------------------------------------------------
  // Attachment and handshake
  // ---------------------------------------------------------------------------

  /// Registers that a [VoxView] is now in the widget tree.
  ///
  /// Called automatically by [VoxView]. Attaches are reference counted so that
  /// two briefly-overlapping views during a route transition do not detach the
  /// bridge.
  void attach() {
    _throwIfDisposed();
    _attachCount++;
    removePauseReason(VoxPauseReason.detached);

    // Unity's Start() fires only once for the entire life of the app, so a
    // second attach would never see an unprompted vox.ready. Probing on every
    // attach is what makes re-entry work.
    if (!_state.isConnected) {
      _beginHandshake();
    }
  }

  /// Registers that a [VoxView] left the widget tree.
  void detach() {
    if (_disposed) return;
    if (_attachCount > 0) _attachCount--;
    if (_attachCount == 0) {
      _stopHandshake();
      addPauseReason(VoxPauseReason.detached);
    }
  }

  /// Restarts a handshake that previously failed.
  void retry() {
    _throwIfDisposed();
    if (_state.isConnected) return;
    if (_readyCompleter.isCompleted) _readyCompleter = Completer<void>();
    _beginHandshake();
  }

  void _beginHandshake() {
    _stopHandshake();
    _helloAttempt = 0;
    if (!_state.isConnected) {
      _setState(
        _state.copyWith(lifecycle: VoxLifecycle.attaching, clearError: true),
      );
    }
    _handshakeDeadline = Timer(handshakeTimeout, _onHandshakeTimeout);
    _sendHello();
  }

  void _stopHandshake() {
    _helloTimer?.cancel();
    _helloTimer = null;
    _handshakeDeadline?.cancel();
    _handshakeDeadline = null;
  }

  void _sendHello() {
    if (_disposed || _state.isConnected) return;
    // Forced: the handshake is precisely what unblocks normal sending, so it
    // must bypass the outbox.
    _dispatch(
      const VoxEnvelope(kind: VoxEnvelopeKind.event, type: VoxTypes.hello),
      force: true,
    );

    final delay =
        _helloBackoff[_helloAttempt.clamp(0, _helloBackoff.length - 1)];
    _helloAttempt++;
    _helloTimer = Timer(delay, _sendHello);
  }

  void _onHandshakeTimeout() {
    if (_disposed || _state.isConnected) return;
    _stopHandshake();
    _fail(
      VoxHandshakeException(
        'Unity did not complete the vox handshake within '
        '${handshakeTimeout.inSeconds}s. Check that a game object named '
        '"$gameObjectName" with VoxBridge.cs attached exists in the active '
        'scene.',
      ),
    );
  }

  void _fail(Object error) {
    _setState(_state.copyWith(lifecycle: VoxLifecycle.failed, lastError: error));
    _outbox.clear();
    _pending.failAll(error);
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error);
      // Nobody may be awaiting ready; do not let it surface as an unhandled
      // async error.
      _readyCompleter.future.ignore();
    }
  }

  void _onReady(Map<String, Object?> payload) {
    _stopHandshake();
    _setState(
      _state.copyWith(
        lifecycle: _pauses.isPaused ? VoxLifecycle.paused : VoxLifecycle.ready,
        activeScene: payload['activeScene'] as String?,
        pauseReasons: _pauses.reasons,
        clearError: true,
      ),
    );
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();

    // Unity is running but may be immediately paused (e.g. attached while the
    // app was backgrounded). Any pause requested before now was recorded but
    // not issued, so apply it here.
    _syncTransportPause();
    if (_state.canSend) _flushOutbox();
  }

  // ---------------------------------------------------------------------------
  // Pause and resume
  // ---------------------------------------------------------------------------

  /// Pauses Unity for [reason], if it is not already paused for that reason.
  void addPauseReason(VoxPauseReason reason) {
    if (_disposed) return;
    _pauses.add(reason);
    _syncPauseState();
    _syncTransportPause();
  }

  /// Removes [reason], resuming Unity if nothing else wants it paused.
  void removePauseReason(VoxPauseReason reason) {
    if (_disposed) return;
    _pauses.remove(reason);
    _syncPauseState();
    _syncTransportPause();
    if (_state.canSend) _flushOutbox();
  }

  /// Brings the transport in line with the current pause reasons.
  ///
  /// Does nothing before the handshake completes. Unity may not have a surface
  /// yet, and on Android the platform plugin is running its own pause/resume
  /// sequence around activity resume and window visibility; issuing competing
  /// calls in that window can leave Unity rendering against a dead surface.
  /// Reasons are still recorded, and applied here once Unity is up.
  void _syncTransportPause() {
    if (!_state.isConnected) return;
    final shouldPause = _pauses.isPaused;
    if (shouldPause == _transportPaused) return;
    _transportPaused = shouldPause;
    if (shouldPause) {
      _transport.pause();
    } else {
      _transport.resume();
    }
  }

  /// Pauses Unity explicitly. Undone by [resume].
  void pause() => addPauseReason(VoxPauseReason.manual);

  /// Undoes [pause].
  void resume() => removePauseReason(VoxPauseReason.manual);

  void _syncPauseState() {
    var lifecycle = _state.lifecycle;
    if (_state.isConnected) {
      lifecycle = _pauses.isPaused ? VoxLifecycle.paused : VoxLifecycle.ready;
    }
    _setState(
      _state.copyWith(lifecycle: lifecycle, pauseReasons: _pauses.reasons),
    );
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Sends a fire-and-forget message.
  ///
  /// If Unity is not ready the message is queued and flushed on resume. Set
  /// [sendWhilePaused] for handlers known to respond without needing Unity's
  /// time to advance.
  void send(VoxCommand command, {bool sendWhilePaused = false}) {
    _throwIfDisposed();
    _dispatch(
      VoxEnvelope(
        kind: VoxEnvelopeKind.event,
        type: command.type,
        payload: command.toPayload(),
      ),
      force: sendWhilePaused && _state.isConnected,
    );
  }

  /// Sends [message] and waits for Unity's reply.
  ///
  /// Throws [VoxRequestException] if Unity replies with an error,
  /// [VoxTimeoutException] if it does not reply in time, and
  /// [VoxDisconnectedException] if the controller is disposed while waiting.
  Future<R> request<R>(
    VoxRequest<R> message, {
    Duration? timeout,
    bool sendWhilePaused = false,
  }) async {
    _throwIfDisposed();
    final id = _pending.nextId();
    final future = _pending.register(
      id,
      message.type,
      timeout ?? defaultTimeout,
    );
    _dispatch(
      VoxEnvelope.request(
        type: message.type,
        id: id,
        payload: message.toPayload(),
      ),
      force: sendWhilePaused && _state.isConnected,
    );
    return message.decodeResponse(await future);
  }

  /// Sends a raw string straight to Unity, bypassing the vox envelope, the
  /// outbox and readiness gating.
  void sendRaw(String data, {String? gameObjectName, String? methodName}) {
    _throwIfDisposed();
    _transport.send(
      gameObjectName ?? this.gameObjectName,
      methodName ?? this.methodName,
      data,
    );
  }

  /// Asks Unity to load [sceneName].
  ///
  /// Completes once Unity accepts the request; await a [VoxSceneChangedEvent]
  /// to know when the scene is actually active.
  Future<void> loadScene(String sceneName, {bool additive = false}) =>
      request(VoxLoadSceneRequest(sceneName, additive: additive));

  /// Round-trips a message through Unity and returns the elapsed time.
  Future<Duration> ping({Duration? timeout}) =>
      request(VoxPingRequest(), timeout: timeout);

  void _dispatch(VoxEnvelope envelope, {bool force = false}) {
    if (force || _state.canSend) {
      _transport.send(gameObjectName, methodName, _codec.encode(envelope));
      if (envelope.kind == VoxEnvelopeKind.request && envelope.id != null) {
        // Started here, not at registration, so time spent queued is not
        // charged against the caller's timeout.
        _pending.startTimeout(envelope.id!);
      }
    } else {
      _outbox.add(envelope);
    }
  }

  void _flushOutbox() {
    if (!_outbox.isNotEmpty) return;
    for (final envelope in _outbox.drain()) {
      _dispatch(envelope, force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  /// Handles one raw message from Unity.
  ///
  /// Wired to `EmbedUnity.onMessageFromUnity` by [VoxView]. Call directly to
  /// drive the controller in tests.
  void handleRawMessage(String message) {
    if (_disposed) return;
    _rawMessages.add(message);

    final VoxEnvelope envelope;
    try {
      envelope = _codec.decode(message);
    } on VoxCodecException catch (e) {
      // A malformed message must not take down the bridge: log and skip.
      _log('${e.message}${e.raw == null ? '' : '\n  raw: ${e.raw}'}');
      return;
    }

    switch (envelope.kind) {
      case VoxEnvelopeKind.response:
        if (!_pending.complete(envelope.id!, envelope.payload)) {
          _log(
            'response for unknown request id "${envelope.id}" '
            '(it may have already timed out)',
          );
        }
      case VoxEnvelopeKind.error:
        final error = VoxRequestException.fromPayload(envelope.payload);
        if (!_pending.completeError(envelope.id!, error)) {
          _log('error for unknown request id "${envelope.id}": $error');
        }
      case VoxEnvelopeKind.event:
        _handleEvent(envelope);
      case VoxEnvelopeKind.request:
        // Unity-initiated requests are not supported yet. Reply explicitly so
        // the Unity side fails fast instead of hanging until its own timeout.
        _dispatch(
          VoxEnvelope.error(
            id: envelope.id!,
            code: 'unsupported',
            message:
                'vox does not support Unity-initiated requests '
                '(received "${envelope.type}")',
          ),
          force: true,
        );
    }
  }

  void _handleEvent(VoxEnvelope envelope) {
    switch (envelope.type) {
      case VoxTypes.ready:
        _onReady(envelope.payload);
      case VoxTypes.sceneChanged:
        final to = envelope.payload['to'] as String?;
        if (to != null) _setState(_state.copyWith(activeScene: to));
    }

    if (!_events.isClosed) {
      _events.add(registry.decode(envelope.type, envelope.payload));
    }
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  void _setState(VoxState next) {
    if (_disposed || next == _state) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
    notifyListeners();
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('VoxController was used after being disposed');
    }
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[vox] $message');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopHandshake();
    _appLifecycle?.unbind();
    _appLifecycle = null;
    _outbox.clear();
    _pending.failAll(const VoxDisconnectedException());
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(const VoxDisconnectedException());
      _readyCompleter.future.ignore();
    }
    _events.close();
    _states.close();
    _rawMessages.close();
    _transport.dispose();
    super.dispose();
  }
}
