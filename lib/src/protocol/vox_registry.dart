import 'vox_builtin.dart';
import 'vox_message.dart';

/// Builds a typed [VoxEvent] from a raw payload.
typedef VoxEventDecoder<T extends VoxEvent> =
    T Function(Map<String, Object?> payload);

/// Maps inbound message types onto typed event classes.
///
/// The built-in `vox.*` events are registered automatically. Register your own
/// before the first message arrives, typically right after constructing the
/// controller:
///
/// ```dart
/// vox.registry.register<PlayerDied>(
///   'game.playerDied',
///   PlayerDied.fromPayload,
/// );
/// ```
class VoxRegistry {
  VoxRegistry() {
    register<VoxReadyEvent>(VoxTypes.ready, VoxReadyEvent.fromPayload);
    register<VoxSceneChangedEvent>(
      VoxTypes.sceneChanged,
      VoxSceneChangedEvent.fromPayload,
    );
  }

  final Map<String, VoxEvent Function(Map<String, Object?>)> _decoders = {};

  /// Registers a decoder for [type], replacing any previous registration.
  void register<T extends VoxEvent>(String type, VoxEventDecoder<T> decode) {
    _decoders[type] = decode;
  }

  /// Removes the decoder for [type].
  void unregister(String type) => _decoders.remove(type);

  /// Whether a decoder exists for [type].
  bool contains(String type) => _decoders.containsKey(type);

  /// Decodes [payload] into a typed event, falling back to [VoxUnknownEvent].
  VoxEvent decode(String type, Map<String, Object?> payload) {
    final decoder = _decoders[type];
    if (decoder == null) {
      return VoxUnknownEvent(type: type, payload: payload);
    }
    return decoder(payload);
  }
}
