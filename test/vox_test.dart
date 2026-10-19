import 'package:flutter_test/flutter_test.dart';
import 'package:vox/vox.dart';

/// Records what the controller sends, so the bridge can be driven without
/// Unity or a platform view.
class FakeTransport implements VoxTransport {
  final List<String> sent = [];
  int pauseCount = 0;
  int resumeCount = 0;

  /// Decoded envelopes, in send order.
  List<VoxEnvelope> get envelopes =>
      sent.map(const VoxCodec().decode).toList(growable: false);

  @override
  void send(String gameObjectName, String methodName, String data) =>
      sent.add(data);

  @override
  void pause() => pauseCount++;

  @override
  void resume() => resumeCount++;

  @override
  void dispose() {}
}

String readyMessage({String scene = 'Main'}) => const VoxCodec().encode(
  VoxEnvelope(
    kind: VoxEnvelopeKind.event,
    type: VoxTypes.ready,
    payload: {'activeScene': scene},
  ),
);

void main() {
  group('VoxCodec', () {
    test('round-trips an envelope', () {
      const codec = VoxCodec();
      const original = VoxEnvelope.request(
        type: 'game.setSpeed',
        id: 'c1',
        payload: {'speed': 1.5},
      );

      expect(codec.decode(codec.encode(original)), original);
    });

    test('rejects malformed messages', () {
      const codec = VoxCodec();
      expect(() => codec.decode('not json'), throwsA(isA<VoxCodecException>()));
      expect(() => codec.decode('[1,2]'), throwsA(isA<VoxCodecException>()));
      // A response without a correlation id is unroutable.
      expect(
        () => codec.decode('{"kind":"res","type":"x"}'),
        throwsA(isA<VoxCodecException>()),
      );
    });
  });

  group('VoxController', () {
    late FakeTransport transport;
    late VoxController vox;

    setUp(() {
      transport = FakeTransport();
      vox = VoxController(
        transport: transport,
        // WidgetsBinding is not available in a plain unit test.
        bindAppLifecycle: false,
      );
    });

    tearDown(() => vox.dispose());

    test('probes with vox.hello on attach and becomes ready', () async {
      vox.attach();
      expect(vox.state.lifecycle, VoxLifecycle.attaching);
      expect(transport.envelopes.single.type, VoxTypes.hello);

      vox.handleRawMessage(readyMessage());
      await vox.ready;

      expect(vox.state.isReady, isTrue);
      expect(vox.state.activeScene, 'Main');
    });

    test('queues messages sent before ready and flushes them in order',
        () async {
      vox.attach();
      transport.sent.clear();

      vox.send(const VoxHelloCommand());
      unawaited(vox.loadScene('Level1'));
      expect(transport.sent, isEmpty, reason: 'not ready yet');

      vox.handleRawMessage(readyMessage());
      await vox.ready;

      expect(
        transport.envelopes.map((e) => e.type),
        [VoxTypes.hello, VoxTypes.loadScene],
      );
    });

    test('completes a request when Unity replies with a matching id', () async {
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;
      transport.sent.clear();

      final pending = vox.loadScene('Level1');
      final id = transport.envelopes.single.id;
      expect(id, isNotNull);

      vox.handleRawMessage(
        const VoxCodec().encode(
          VoxEnvelope(kind: VoxEnvelopeKind.response, type: 'x', id: id),
        ),
      );

      await expectLater(pending, completes);
    });

    test('surfaces an error envelope as VoxRequestException', () async {
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;
      transport.sent.clear();

      final pending = vox.loadScene('Missing');
      final id = transport.envelopes.single.id!;

      vox.handleRawMessage(
        const VoxCodec().encode(
          VoxEnvelope.error(
            id: id,
            code: 'sceneNotFound',
            message: 'No scene named Missing',
          ),
        ),
      );

      await expectLater(pending, throwsA(isA<VoxRequestException>()));
    });

    test('times out when Unity never replies', () async {
      vox = VoxController(
        transport: transport,
        bindAppLifecycle: false,
        defaultTimeout: const Duration(milliseconds: 20),
      );
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;

      await expectLater(
        vox.loadScene('Level1'),
        throwsA(isA<VoxTimeoutException>()),
      );
    });

    test('stays paused until every pause reason is removed', () async {
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;

      vox.addPauseReason(VoxPauseReason.appBackgrounded);
      vox.addPauseReason(VoxPauseReason.routeCovered);
      expect(vox.state.isPaused, isTrue);
      expect(transport.pauseCount, 1, reason: 'pause is not re-issued');

      vox.removePauseReason(VoxPauseReason.routeCovered);
      expect(
        vox.state.isPaused,
        isTrue,
        reason: 'the app is still backgrounded',
      );
      expect(transport.resumeCount, 0);

      vox.removePauseReason(VoxPauseReason.appBackgrounded);
      expect(vox.state.isReady, isTrue);
      expect(transport.resumeCount, 1);
    });

    test('does not touch Unity before the handshake completes', () async {
      vox.attach();
      // Backgrounding before Unity is up must not reach the transport: Unity
      // may have no surface yet, and on Android the platform plugin is running
      // its own pause/resume sequence at this point.
      vox.addPauseReason(VoxPauseReason.appBackgrounded);

      expect(transport.pauseCount, 0, reason: 'not connected yet');
      expect(
        vox.state.pauseReasons,
        contains(VoxPauseReason.appBackgrounded),
        reason: 'the reason is still recorded',
      );

      // ...and is applied as soon as Unity reports in.
      vox.handleRawMessage(readyMessage());
      await vox.ready;

      expect(transport.pauseCount, 1);
      expect(vox.state.isPaused, isTrue);
    });

    test('never issues a duplicate pause or resume', () async {
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;

      vox.addPauseReason(VoxPauseReason.appBackgrounded);
      vox.addPauseReason(VoxPauseReason.appBackgrounded);
      vox.addPauseReason(VoxPauseReason.routeCovered);
      expect(transport.pauseCount, 1);

      vox.removePauseReason(VoxPauseReason.routeCovered);
      vox.removePauseReason(VoxPauseReason.appBackgrounded);
      vox.removePauseReason(VoxPauseReason.appBackgrounded);
      expect(transport.resumeCount, 1);
    });

    test('decodes registered events and falls back to VoxUnknownEvent',
        () async {
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;

      final seen = <VoxEvent>[];
      vox.events.listen(seen.add);

      vox.handleRawMessage(
        const VoxCodec().encode(
          VoxEnvelope(
            kind: VoxEnvelopeKind.event,
            type: VoxTypes.sceneChanged,
            payload: {'from': 'Main', 'to': 'Level1'},
          ),
        ),
      );
      vox.handleRawMessage(
        const VoxCodec().encode(
          VoxEnvelope(kind: VoxEnvelopeKind.event, type: 'game.custom'),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.first, isA<VoxSceneChangedEvent>());
      expect(seen.last, isA<VoxUnknownEvent>());
      expect(vox.state.activeScene, 'Level1');
    });

    test('ignores malformed messages without failing the bridge', () async {
      vox.attach();
      vox.handleRawMessage(readyMessage());
      await vox.ready;

      vox.handleRawMessage('<html>gateway error</html>');

      expect(vox.state.isReady, isTrue);
    });
  });
}

/// Local stand-in for `package:async`'s `unawaited`, to avoid a dependency.
void unawaited(Future<void> future) {
  future.ignore();
}
