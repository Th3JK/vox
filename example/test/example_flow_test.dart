import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox/vox.dart';
import 'package:vox_example/fake_unity.dart';
import 'package:vox_example/messages.dart';
import 'package:vox_example/unity_page.dart';

/// Drives the real example widget tree against [FakeUnityTransport].
///
/// Runs as the windows target so `VoxView` takes its non-mobile fallback and no
/// platform view is involved — the same path the desktop demo uses.
/// Forces the non-mobile path so `VoxView` renders its fallback instead of a
/// platform view. TargetPlatformVariant is used rather than setting
/// debugDefaultTargetPlatformOverride directly, because it restores the value
/// before flutter_test checks that no debug variable leaked out of the test.
final windowsOnly = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  late VoxController vox;
  late FakeUnityTransport transport;
  late RouteObserver<ModalRoute<void>> routeObserver;

  setUp(() {
    transport = FakeUnityTransport(latency: const Duration(milliseconds: 1));
    vox = VoxController(transport: transport, bindAppLifecycle: false);
    transport.onMessage = vox.handleRawMessage;
    registerExampleMessages(vox);
    routeObserver = RouteObserver<ModalRoute<void>>();
  });

  tearDown(() => vox.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [routeObserver],
        home: UnityPage(controller: vox, routeObserver: routeObserver),
      ),
    );
    // Let the handshake round-trip through the fake transport.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  testWidgets('completes the handshake and shows READY', (tester) async {
    await pumpApp(tester);

    expect(vox.state.isReady, isTrue);
    expect(find.text('READY'), findsOneWidget);
    expect(find.textContaining(ExampleScenes.main), findsWidgets);
  }, variant: windowsOnly);

  testWidgets('round-trips a typed request', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Read speed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('getRotationSpeed -> 20.0'), findsOneWidget);
  }, variant: windowsOnly);

  testWidgets('reports a ping latency', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ping'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('ping -> '), findsOneWidget);
  }, variant: windowsOnly);

  testWidgets('surfaces an unhandled request as a typed error', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Unknown type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('Unity reported unhandledType'),
      findsOneWidget,
    );
  }, variant: windowsOnly);

  testWidgets('switches scene and logs the change event', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('SceneAR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(vox.state.activeScene, ExampleScenes.ar);
    expect(find.textContaining('scene: '), findsOneWidget);
  }, variant: windowsOnly);

  testWidgets('pauses while a route covers Unity, and resumes on pop', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(vox.state.isReady, isTrue);

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();

    expect(vox.state.pauseReasons, contains(VoxPauseReason.routeCovered));
    expect(vox.state.isPaused, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(vox.state.pauseReasons, isNot(contains(VoxPauseReason.routeCovered)));
    expect(vox.state.isReady, isTrue);
  }, variant: windowsOnly);

  testWidgets('manual pause holds Unity paused independently of the route', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(vox.state.pauseReasons, {VoxPauseReason.manual});

    // Cover and uncover the route while manually paused: the route reason comes
    // and goes, but the manual one must keep Unity paused throughout.
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(vox.state.isPaused, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      vox.state.isPaused,
      isTrue,
      reason: 'the manual pause must survive the route being revealed',
    );

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(vox.state.isReady, isTrue);
  }, variant: windowsOnly);

  testWidgets('queues messages sent while paused and flushes them on resume', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Pause'));
    await tester.pump();

    // Captured via then rather than awaited: awaiting a future that cannot
    // complete until time is pumped would deadlock the test.
    double? received;
    unawaited(
      vox.request(const GetRotationSpeed()).then((value) => received = value),
    );

    await tester.pump(const Duration(milliseconds: 50));
    expect(received, isNull, reason: 'queued while paused, not sent');

    await tester.tap(find.text('Resume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(received, 20.0, reason: 'flushed on resume');
  }, variant: windowsOnly);
}
