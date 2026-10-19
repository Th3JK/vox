import 'package:flutter/foundation.dart';

/// Anything vox can send to Unity.
///
/// Subclasses supply a [type] that a Unity handler is registered for, and a
/// [toPayload] describing the body.
abstract class VoxMessage {
  const VoxMessage();

  /// The message type, matched against `[VoxHandler("...")]` on the Unity side.
  String get type;

  /// The JSON body of the message. Must contain only JSON-encodable values.
  Map<String, Object?> toPayload() => const {};
}

/// A fire-and-forget message. Unity is not expected to reply.
abstract class VoxCommand extends VoxMessage {
  const VoxCommand();
}

/// A message that expects a reply of type [R].
///
/// vox generates a correlation id, tracks the pending reply, and calls
/// [decodeResponse] with the payload of the matching `res` envelope.
abstract class VoxRequest<R> extends VoxMessage {
  const VoxRequest();

  /// Converts the payload of Unity's reply into the typed result.
  R decodeResponse(Map<String, Object?> payload);
}

/// A notification pushed from Unity that was not requested.
@immutable
abstract class VoxEvent {
  const VoxEvent();
}

/// Fallback event for a `type` that has no decoder registered.
///
/// Unrecognised events surface as this rather than being dropped silently, so
/// a mismatch between the Flutter and Unity sides is visible at runtime.
@immutable
class VoxUnknownEvent extends VoxEvent {
  const VoxUnknownEvent({required this.type, required this.payload});

  /// The unrecognised message type.
  final String type;

  /// The raw, undecoded payload.
  final Map<String, Object?> payload;

  @override
  String toString() => 'VoxUnknownEvent($type, $payload)';
}
