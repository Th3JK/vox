import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox/vox.dart';

/// Mounting a VoxView over a controller that is already connected — the
/// return-visit case, where Unity survives between routes and the handshake
/// is long since done.
void main() {
  testWidgets(
    'an already-connected controller fires onReady after the build, not during',
    (tester) async {
      final transport = _InstantHandshakeTransport();
      final controller = VoxController(
        transport: transport,
        bindAppLifecycle: false,
      );
      transport.onMessage = controller.handleRawMessage;
      addTearDown(controller.dispose);

      // Connect before any view exists, as a previous visit would have.
      controller.attach();
      await tester.pump();
      expect(controller.state.isConnected, isTrue);

      // The crashing pattern: onReady calls setState on a widget above the
      // view, while the view is being mounted as part of that widget's build.
      await tester.pumpWidget(_Host(controller: controller));

      expect(tester.takeException(), isNull);

      // onReady lands in the post-frame callback; one more frame shows it.
      await tester.pump();
      expect(find.text('ready'), findsOneWidget);
    },
  );
}

class _Host extends StatefulWidget {
  const _Host({required this.controller});

  final VoxController controller;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Stack(
        textDirection: TextDirection.ltr,
        children: [
          VoxView(
            controller: widget.controller,
            onReady: () => setState(() => _ready = true),
            unsupportedPlatformBuilder: (_) => const SizedBox.expand(),
          ),
          if (_ready) const Text('ready'),
        ],
      ),
    );
  }
}

/// Answers the handshake on the next microtask — after send() returns, so
/// the controller's retry bookkeeping sees the reply and cancels itself.
class _InstantHandshakeTransport implements VoxTransport {
  void Function(String message)? onMessage;

  static const _codec = VoxCodec();

  @override
  void send(String gameObjectName, String methodName, String data) {
    final VoxEnvelope envelope;
    try {
      envelope = _codec.decode(data);
    } on VoxCodecException {
      return;
    }
    Future.microtask(() => _handle(envelope));
  }

  void _handle(VoxEnvelope envelope) {
    if (envelope.type == VoxTypes.hello) {
      onMessage?.call(
        _codec.encode(
          const VoxEnvelope(
            kind: VoxEnvelopeKind.event,
            type: VoxTypes.ready,
            payload: {'activeScene': 'Test', 'unityVersion': 'test'},
          ),
        ),
      );
    } else if (envelope.id != null) {
      onMessage?.call(
        _codec.encode(
          VoxEnvelope(
            kind: VoxEnvelopeKind.response,
            type: envelope.type,
            id: envelope.id,
          ),
        ),
      );
    }
  }

  @override
  void pause() {}

  @override
  void resume() {}

  @override
  void dispose() {}
}
