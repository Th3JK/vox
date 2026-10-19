import 'package:flutter/widgets.dart';

/// Pauses Unity while the app is not in the foreground.
///
/// Takes callbacks rather than a controller reference so the lifecycle layer
/// stays independent of the core.
class AppLifecycleBinder with WidgetsBindingObserver {
  /// Creates a binder. Call [bind] to start observing.
  AppLifecycleBinder({
    required this.onBackgrounded,
    required this.onForegrounded,
  });

  /// Invoked when the app leaves the foreground.
  final VoidCallback onBackgrounded;

  /// Invoked when the app returns to the foreground.
  final VoidCallback onForegrounded;

  bool _bound = false;

  /// Starts observing app lifecycle changes. Idempotent.
  void bind() {
    if (_bound) return;
    // ensureInitialized rather than WidgetsBinding.instance: creating a
    // VoxController in main() before runApp() is the documented way to hold one
    // for the life of the app, and at that point the binding does not exist yet.
    // It is idempotent, and returns the existing binding under flutter_test.
    WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    _bound = true;
  }

  /// Stops observing. Idempotent.
  void unbind() {
    if (!_bound) return;
    WidgetsBinding.instance.removeObserver(this);
    _bound = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        onForegrounded();

      // `inactive` is deliberately NOT treated as backgrounded. It fires
      // transiently on window-focus changes, during startup and around
      // platform-view attachment — precisely when Unity's surface is being set
      // up. The Android plugin does not treat it as a pause point either, and
      // pausing Unity in that window risks rendering against a dead surface.
      case AppLifecycleState.inactive:
        break;

      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        onBackgrounded();
    }
  }
}
