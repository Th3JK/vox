import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vox/vox.dart';

import 'fake_unity.dart';
import 'messages.dart';
import 'unity_page.dart';

/// TEMPORARY DIAGNOSTIC — takes vox entirely out of Unity's lifecycle.
///
/// When true, vox never calls pauseUnity()/resumeUnity(): app-lifecycle binding
/// is off and no RouteObserver is passed to VoxView. The Android platform
/// plugin is then the only thing driving Unity's pause/resume.
///
/// Used to determine whether vox is implicated in the null-ANativeWindow crash
/// in Unity's render thread. See example/README.md for the procedure.
const bool kIsolateVoxLifecycle = false;

/// Registered on the app's navigator so vox can pause Unity when its route is
/// covered. Without this, route-visibility pausing is simply inactive.
final routeObserver = RouteObserver<ModalRoute<void>>();

/// Unity only runs on Android and iOS.
bool get _unityIsAvailable =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

void main() {
  final VoxController controller;

  if (_unityIsAvailable) {
    controller = VoxController(bindAppLifecycle: !kIsolateVoxLifecycle);
  } else {
    // On desktop there is no Unity to talk to, so drive the bridge with a
    // simulator instead of showing a screen stuck on the handshake.
    final transport = FakeUnityTransport();
    controller = VoxController(transport: transport);
    transport.onMessage = controller.handleRawMessage;
  }

  registerExampleMessages(controller);

  runApp(VoxExampleApp(controller: controller));
}

class VoxExampleApp extends StatelessWidget {
  const VoxExampleApp({super.key, required this.controller});

  final VoxController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vox example',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42A5F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: UnityPage(
        controller: controller,
        // Null while isolating, so vox never pauses Unity on route changes.
        routeObserver: kIsolateVoxLifecycle ? null : routeObserver,
      ),
    );
  }
}
