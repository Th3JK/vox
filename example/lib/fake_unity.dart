import 'dart:async';
import 'dart:math';

import 'package:vox/vox.dart';

import 'messages.dart';

/// A stand-in for Unity, so the example is a working demo on desktop.
///
/// Unity only runs on Android and iOS, which would otherwise leave this app
/// stuck on the handshake with nothing to show. This parses what vox sends,
/// answers it the way `VoxExampleHandlers.cs` would, and pushes the occasional
/// unsolicited event.
///
/// It is also a decent illustration of why [VoxTransport] is an interface:
/// swapping the real transport out is all it takes to drive the whole bridge
/// without a platform view.
class FakeUnityTransport implements VoxTransport {
  FakeUnityTransport({this.latency = const Duration(milliseconds: 30)});

  /// Simulated round-trip delay, so latency readouts are not all zero.
  final Duration latency;

  /// Set to `controller.handleRawMessage` once the controller exists.
  void Function(String message)? onMessage;

  static const _codec = VoxCodec();
  final _random = Random();

  Timer? _touchTimer;
  bool _paused = false;
  bool _disposed = false;
  double _rotationSpeed = 20;
  String _activeScene = ExampleScenes.main;

  @override
  void send(String gameObjectName, String methodName, String data) {
    final VoxEnvelope envelope;
    try {
      envelope = _codec.decode(data);
    } on VoxCodecException {
      return;
    }
    _after(() => _handle(envelope));
  }

  @override
  void pause() {
    _paused = true;
    _touchTimer?.cancel();
    _touchTimer = null;
  }

  @override
  void resume() {
    _paused = false;
    _startTouchTimer();
  }

  @override
  void dispose() {
    _disposed = true;
    _touchTimer?.cancel();
    _touchTimer = null;
  }

  // ---------------------------------------------------------------------------

  void _handle(VoxEnvelope envelope) {
    switch (envelope.type) {
      case VoxTypes.hello:
        _emit(
          VoxEnvelope(
            kind: VoxEnvelopeKind.event,
            type: VoxTypes.ready,
            payload: {
              'activeScene': _activeScene,
              'unityVersion': '2022.3 (simulated)',
            },
          ),
        );
        _startTouchTimer();

      case VoxTypes.ping:
        _respond(envelope, {
          'sentAt': envelope.payload['sentAt'],
          'receivedAt': DateTime.now().millisecondsSinceEpoch,
        });

      case VoxTypes.loadScene:
        final requested = envelope.payload['sceneName'] as String?;
        if (requested == null || !ExampleScenes.all.contains(requested)) {
          _fail(envelope, 'sceneNotFound', 'No scene named "$requested"');
          return;
        }
        final previous = _activeScene;
        _activeScene = requested;
        _respond(envelope, const {});
        _after(
          () => _emit(
            VoxEnvelope(
              kind: VoxEnvelopeKind.event,
              type: VoxTypes.sceneChanged,
              payload: {'from': previous, 'to': requested},
            ),
          ),
        );

      case ExampleTypes.setRotationSpeed:
        _rotationSpeed = (envelope.payload['speed'] as num?)?.toDouble() ?? 20;
        _respond(envelope, const {});

      case ExampleTypes.getRotationSpeed:
        _respond(envelope, {'speed': _rotationSpeed});

      case ExampleTypes.getSceneInfo:
        _respond(envelope, {
          'scene': _activeScene,
          'unityVersion': '2022.3 (simulated)',
        });

      default:
        // Mirrors the real bridge: an unhandled request must be answered, or
        // the caller waits out its full timeout.
        _fail(
          envelope,
          'unhandledType',
          'No simulated handler for "${envelope.type}"',
        );
    }
  }

  void _startTouchTimer() {
    if (_disposed || _paused || _touchTimer != null) return;
    _touchTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _emit(
        VoxEnvelope(
          kind: VoxEnvelopeKind.event,
          type: ExampleTypes.touched,
          payload: {'objectName': 'FlutterLogo'},
        ),
      );
      // Occasionally send something the registry has no decoder for, to show
      // that it surfaces as VoxUnknownEvent rather than vanishing.
      if (_random.nextInt(3) == 0) {
        _emit(
          const VoxEnvelope(
            kind: VoxEnvelopeKind.event,
            type: 'example.unregistered',
            payload: {'note': 'no decoder registered for this type'},
          ),
        );
      }
    });
  }

  void _respond(VoxEnvelope request, Map<String, Object?> payload) {
    if (request.id == null) return;
    _emit(
      VoxEnvelope(
        kind: VoxEnvelopeKind.response,
        type: request.type,
        id: request.id,
        payload: payload,
      ),
    );
  }

  void _fail(VoxEnvelope request, String code, String message) {
    if (request.id == null) return;
    _emit(VoxEnvelope.error(id: request.id!, code: code, message: message));
  }

  void _emit(VoxEnvelope envelope) {
    if (_disposed) return;
    onMessage?.call(_codec.encode(envelope));
  }

  void _after(void Function() action) {
    Future<void>.delayed(latency, () {
      if (!_disposed) action();
    });
  }
}
