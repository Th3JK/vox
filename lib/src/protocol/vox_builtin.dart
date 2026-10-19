import 'package:flutter/foundation.dart';

import 'vox_message.dart';

/// Message types reserved by vox itself. Application types must not use the
/// `vox.` prefix.
abstract final class VoxTypes {
  /// Flutter to Unity: "are you there?". Sent on every attach.
  static const String hello = 'vox.hello';

  /// Unity to Flutter: "I am running". Sent on `Start()` and per [hello].
  static const String ready = 'vox.ready';

  /// Flutter to Unity: load a scene by name.
  static const String loadScene = 'vox.scene.load';

  /// Unity to Flutter: the active scene changed.
  static const String sceneChanged = 'vox.scene.changed';

  /// Flutter to Unity: round-trip liveness check.
  static const String ping = 'vox.ping';
}

/// Handshake probe sent on every attach.
///
/// Unity replies with a [VoxReadyEvent]. This is a command rather than a
/// request because Unity also emits `vox.ready` unprompted on `Start()`, so the
/// reply is handled uniformly as an event either way.
class VoxHelloCommand extends VoxCommand {
  const VoxHelloCommand();

  @override
  String get type => VoxTypes.hello;
}

/// Emitted by Unity once the vox bridge is live and able to handle messages.
@immutable
class VoxReadyEvent extends VoxEvent {
  const VoxReadyEvent({this.activeScene, this.unityVersion});

  /// Builds the event from a `vox.ready` payload.
  factory VoxReadyEvent.fromPayload(Map<String, Object?> payload) =>
      VoxReadyEvent(
        activeScene: payload['activeScene'] as String?,
        unityVersion: payload['unityVersion'] as String?,
      );

  /// Name of the scene active at handshake time.
  final String? activeScene;

  /// Unity runtime version, useful for diagnostics.
  final String? unityVersion;

  @override
  String toString() =>
      'VoxReadyEvent(activeScene: $activeScene, unityVersion: $unityVersion)';
}

/// Emitted by Unity when the active scene changes.
@immutable
class VoxSceneChangedEvent extends VoxEvent {
  const VoxSceneChangedEvent({this.from, required this.to});

  /// Builds the event from a `vox.scene.changed` payload.
  factory VoxSceneChangedEvent.fromPayload(Map<String, Object?> payload) =>
      VoxSceneChangedEvent(
        from: payload['from'] as String?,
        to: payload['to'] as String? ?? '',
      );

  /// The scene being left, or null if there was none.
  final String? from;

  /// The scene now active.
  final String to;

  @override
  String toString() => 'VoxSceneChangedEvent($from -> $to)';
}

/// Asks Unity to load a scene by name.
///
/// Completes when Unity confirms the load has been kicked off; listen for
/// [VoxSceneChangedEvent] to know when it is actually active.
class VoxLoadSceneRequest extends VoxRequest<void> {
  const VoxLoadSceneRequest(this.sceneName, {this.additive = false});

  /// Name of the scene, as listed in Unity's build settings.
  final String sceneName;

  /// Whether to load additively instead of replacing the current scene.
  final bool additive;

  @override
  String get type => VoxTypes.loadScene;

  @override
  Map<String, Object?> toPayload() => {
    'sceneName': sceneName,
    'additive': additive,
  };

  @override
  void decodeResponse(Map<String, Object?> payload) {}
}

/// Round-trips a message through Unity, returning the reported latency.
class VoxPingRequest extends VoxRequest<Duration> {
  VoxPingRequest() : sentAt = DateTime.now();

  /// When the ping was constructed, used to compute round-trip time.
  final DateTime sentAt;

  @override
  String get type => VoxTypes.ping;

  @override
  Map<String, Object?> toPayload() => {
    'sentAt': sentAt.millisecondsSinceEpoch,
  };

  @override
  Duration decodeResponse(Map<String, Object?> payload) =>
      DateTime.now().difference(sentAt);
}
