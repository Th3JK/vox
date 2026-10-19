import 'package:flutter/foundation.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

import 'vox_transport.dart';

/// The real transport, backed by `flutter_embed_unity`.
///
/// This is the only file in the package that imports `flutter_embed_unity`,
/// which keeps the rest of vox pure Dart.
class EmbedUnityTransport implements VoxTransport {
  /// Creates the transport and configures message routing.
  ///
  /// [unicastMessagesFromUnity] sets
  /// [EmbedUnityPreferences.messageFromUnityListeningBehaviour] to
  /// [MessageFromUnityListeningBehaviour.onlyMostRecentlyCreatedWidgetReceivesMessages].
  /// vox defaults this to true: during a route transition two `VoxView`s can
  /// briefly coexist, and under the default multicast behaviour both would
  /// deliver the same reply, double-completing a pending request.
  EmbedUnityTransport({bool unicastMessagesFromUnity = true}) {
    if (unicastMessagesFromUnity) {
      EmbedUnityPreferences.messageFromUnityListeningBehaviour =
          MessageFromUnityListeningBehaviour
              .onlyMostRecentlyCreatedWidgetReceivesMessages;
    }
  }

  /// Whether Unity can actually run here.
  ///
  /// `flutter_embed_unity` has no implementation off Android and iOS, so every
  /// call is a no-op elsewhere rather than an exception. A desktop debug run
  /// then simply fails its handshake, instead of crashing the app.
  static bool get _isSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _warned = false;

  void _warnOnce() {
    if (_warned || !kDebugMode) return;
    _warned = true;
    debugPrint(
      '[vox] Unity is not available on $defaultTargetPlatform, so messages are '
      'being dropped. Pass a fake VoxTransport to VoxController to develop '
      'against a simulated Unity.',
    );
  }

  @override
  void send(String gameObjectName, String methodName, String data) {
    if (!_isSupported) return _warnOnce();
    sendToUnity(gameObjectName, methodName, data);
  }

  @override
  void pause() {
    if (!_isSupported) return;
    pauseUnity();
  }

  @override
  void resume() {
    if (!_isSupported) return;
    resumeUnity();
  }

  @override
  void dispose() {
    // Unity cannot be unloaded without terminating the app, so there is
    // nothing to tear down here.
  }
}
