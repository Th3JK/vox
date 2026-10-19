import 'dart:convert';

import 'vox_envelope.dart';
import 'vox_exceptions.dart';

/// Translates between [VoxEnvelope]s and the JSON strings that
/// `flutter_embed_unity` moves across the platform boundary.
class VoxCodec {
  const VoxCodec();

  /// Longest prefix of a bad message included in a [VoxCodecException].
  static const int maxLoggedLength = 256;

  /// Encodes [envelope] as a JSON string.
  String encode(VoxEnvelope envelope) => jsonEncode(envelope.toJson());

  /// Decodes a raw string received from Unity.
  ///
  /// Throws [VoxCodecException] if the string is not valid JSON, is not a JSON
  /// object, or does not describe a well formed envelope.
  VoxEnvelope decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw VoxCodecException('Message from Unity is not valid JSON: ${e.message}', raw: _truncate(raw));
    }

    if (decoded is! Map) {
      throw VoxCodecException(
        'Message from Unity is not a JSON object (got ${decoded.runtimeType})',
        raw: _truncate(raw),
      );
    }

    final envelope = VoxEnvelope.tryFromJson(Map<String, Object?>.from(decoded));
    if (envelope == null) {
      throw VoxCodecException(
        'Message from Unity is not a valid vox envelope. Expected '
        '{"kind": "req|res|err|evt", "type": "...", "id": "..."}',
        raw: _truncate(raw),
      );
    }
    return envelope;
  }

  static String _truncate(String raw) => raw.length <= maxLoggedLength
      ? raw
      : '${raw.substring(0, maxLoggedLength)}...';
}
