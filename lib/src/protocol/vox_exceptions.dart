/// Base class for every error surfaced by vox.
abstract class VoxException implements Exception {
  const VoxException(this.message);

  /// Human readable description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when Unity did not reply to a request within the allowed time.
///
/// The timeout clock starts when the request is actually written to the
/// transport, not when it is enqueued, so time spent waiting in the outbox
/// while Unity is paused or not yet ready does not count against it.
class VoxTimeoutException extends VoxException {
  VoxTimeoutException({
    required this.type,
    required this.id,
    required this.timeout,
  }) : super(
         'Unity did not respond to "$type" (id: $id) '
         'within ${timeout.inMilliseconds}ms',
       );

  /// Message type of the request that timed out.
  final String type;

  /// Correlation id of the request that timed out.
  final String id;

  /// How long vox waited before giving up.
  final Duration timeout;
}

/// Thrown when Unity replied to a request with an error envelope.
class VoxRequestException extends VoxException {
  const VoxRequestException({
    required this.code,
    required String message,
    this.details,
  }) : super(message);

  /// Creates an exception from the payload of an `err` envelope.
  factory VoxRequestException.fromPayload(Map<String, Object?> payload) {
    return VoxRequestException(
      code: payload['code'] as String? ?? 'unknown',
      message: payload['message'] as String? ?? 'Unity reported an error',
      details: payload['details'] as String?,
    );
  }

  /// Machine readable error code chosen by the Unity handler.
  final String code;

  /// Optional extra context, such as a C# stack trace.
  final String? details;

  @override
  String toString() =>
      'VoxRequestException($code): $message${details == null ? '' : '\n$details'}';
}

/// Thrown when a raw message from Unity could not be parsed as a vox envelope.
class VoxCodecException extends VoxException {
  const VoxCodecException(super.message, {this.raw});

  /// The offending message, truncated by the codec for logging.
  final String? raw;
}

/// Thrown when Unity failed to complete the vox handshake in time.
class VoxHandshakeException extends VoxException {
  const VoxHandshakeException(super.message);
}

/// Thrown for in-flight requests when the controller is disposed.
class VoxDisconnectedException extends VoxException {
  const VoxDisconnectedException([
    super.message = 'The VoxController was disposed before Unity replied',
  ]);
}
