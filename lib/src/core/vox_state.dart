import 'package:flutter/foundation.dart';

/// Where the Unity bridge is in its lifecycle.
enum VoxLifecycle {
  /// No `VoxView` has been attached yet.
  idle,

  /// Attached, handshake in flight, waiting for `vox.ready`.
  attaching,

  /// Handshake complete and Unity is running.
  ready,

  /// Handshake complete but Unity's time is paused. Messages are queued.
  paused,

  /// The handshake timed out or the bridge errored. See [VoxState.lastError].
  failed,
}

/// Why Unity is currently paused.
///
/// Reasons accumulate in a set and Unity resumes only once the set is empty,
/// so returning to a route while the app is still backgrounded does not
/// wrongly resume Unity.
enum VoxPauseReason {
  /// The app moved to the background or became inactive.
  appBackgrounded,

  /// Another route was pushed on top of the route hosting Unity.
  routeCovered,

  /// `VoxController.pause()` was called explicitly.
  manual,

  /// No `VoxView` is currently in the widget tree.
  detached,
}

/// An immutable snapshot of the bridge.
@immutable
class VoxState {
  /// Creates a snapshot. Prefer [VoxState.initial] and [copyWith].
  const VoxState({
    required this.lifecycle,
    this.activeScene,
    this.pauseReasons = const {},
    this.lastError,
  });

  /// The state before anything has attached.
  const VoxState.initial() : this(lifecycle: VoxLifecycle.idle);

  /// Current lifecycle phase.
  final VoxLifecycle lifecycle;

  /// Name of Unity's active scene, once known.
  final String? activeScene;

  /// Everything currently holding Unity paused.
  final Set<VoxPauseReason> pauseReasons;

  /// The error that caused [VoxLifecycle.failed], if any.
  final Object? lastError;

  /// Whether Unity has completed the handshake and is running.
  bool get isReady => lifecycle == VoxLifecycle.ready;

  /// Whether the handshake completed but Unity is paused.
  bool get isPaused => lifecycle == VoxLifecycle.paused;

  /// Whether the handshake has completed, regardless of pause state.
  bool get isConnected => isReady || isPaused;

  /// Whether messages can go out immediately rather than being queued.
  bool get canSend => isReady;

  /// Returns a copy with the given fields replaced.
  ///
  /// [lastError] is cleared by passing [clearError], since null cannot be
  /// distinguished from "not supplied".
  VoxState copyWith({
    VoxLifecycle? lifecycle,
    String? activeScene,
    Set<VoxPauseReason>? pauseReasons,
    Object? lastError,
    bool clearError = false,
  }) => VoxState(
    lifecycle: lifecycle ?? this.lifecycle,
    activeScene: activeScene ?? this.activeScene,
    pauseReasons: pauseReasons ?? this.pauseReasons,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  @override
  String toString() =>
      'VoxState(${lifecycle.name}'
      '${activeScene == null ? '' : ', scene: $activeScene'}'
      '${pauseReasons.isEmpty ? '' : ', paused by: ${pauseReasons.map((r) => r.name).join(', ')}'}'
      '${lastError == null ? '' : ', error: $lastError'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoxState &&
          other.lifecycle == lifecycle &&
          other.activeScene == activeScene &&
          setEquals(other.pauseReasons, pauseReasons) &&
          other.lastError == lastError;

  @override
  int get hashCode => Object.hash(
    lifecycle,
    activeScene,
    Object.hashAllUnordered(pauseReasons),
    lastError,
  );
}
