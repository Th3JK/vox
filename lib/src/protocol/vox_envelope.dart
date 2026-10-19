import 'package:flutter/foundation.dart';

/// The four kinds of message that can cross the Flutter/Unity boundary.
enum VoxEnvelopeKind {
  /// A call expecting a matching [response] or [error] carrying the same id.
  request('req'),

  /// A successful reply to a [request].
  response('res'),

  /// A failed reply to a [request].
  error('err'),

  /// An unsolicited notification. Carries no id.
  event('evt');

  const VoxEnvelopeKind(this.wireName);

  /// The value written to the `kind` field on the wire.
  final String wireName;

  /// Parses a wire value, returning `null` if it is not recognised.
  static VoxEnvelopeKind? fromWireName(String value) {
    for (final kind in VoxEnvelopeKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// A single vox message, in the shape it takes on the wire:
///
/// ```json
/// { "kind": "req", "type": "scene.load", "id": "c17", "payload": {} }
/// ```
@immutable
class VoxEnvelope {
  const VoxEnvelope({
    required this.kind,
    required this.type,
    this.id,
    this.payload = const {},
  });

  /// Convenience constructor for an outbound request.
  const VoxEnvelope.request({
    required this.type,
    required String this.id,
    this.payload = const {},
  }) : kind = VoxEnvelopeKind.request;

  /// Convenience constructor for an outbound error reply.
  VoxEnvelope.error({
    required String this.id,
    required String code,
    required String message,
    String? details,
  }) : kind = VoxEnvelopeKind.error,
       type = 'vox.error',
       payload = {
         'code': code,
         'message': message,
         'details': ?details,
       };

  /// Whether this is a request, response, error or event.
  final VoxEnvelopeKind kind;

  /// The message type, e.g. `vox.scene.load`.
  final String type;

  /// Correlation id. Present on requests, responses and errors; null on events.
  final String? id;

  /// Message body. Always a JSON object, never null.
  final Map<String, Object?> payload;

  /// Builds an envelope from already-decoded JSON.
  ///
  /// Returns `null` when required fields are missing or malformed, so callers
  /// can decide whether to log and skip or throw.
  static VoxEnvelope? tryFromJson(Map<String, Object?> json) {
    final rawKind = json['kind'];
    final rawType = json['type'];
    if (rawKind is! String || rawType is! String) return null;

    final kind = VoxEnvelopeKind.fromWireName(rawKind);
    if (kind == null) return null;

    final rawId = json['id'];
    if (rawId != null && rawId is! String) return null;

    // Requests, responses and errors are meaningless without a correlation id.
    if (kind != VoxEnvelopeKind.event && rawId == null) return null;

    final rawPayload = json['payload'];
    if (rawPayload != null && rawPayload is! Map) return null;

    return VoxEnvelope(
      kind: kind,
      type: rawType,
      id: rawId as String?,
      payload: rawPayload == null
          ? const {}
          : Map<String, Object?>.from(rawPayload as Map),
    );
  }

  /// Serialises to the wire shape. Null fields are omitted.
  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    'type': type,
    if (id != null) 'id': id,
    if (payload.isNotEmpty) 'payload': payload,
  };

  @override
  String toString() =>
      'VoxEnvelope(${kind.wireName}, $type${id == null ? '' : ', id: $id'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoxEnvelope &&
          other.kind == kind &&
          other.type == type &&
          other.id == id &&
          mapEquals(other.payload, payload);

  @override
  int get hashCode => Object.hash(kind, type, id);
}
