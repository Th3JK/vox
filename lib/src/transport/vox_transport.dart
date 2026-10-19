/// The outbound half of the Unity bridge.
///
/// Inbound messages are not modelled here: they arrive through the
/// `EmbedUnity` widget callback and are handed to
/// `VoxController.handleRawMessage`. Keeping the interface outbound-only means
/// a test double just has to record what was sent, and the controller can be
/// driven end to end without Unity or a platform view.
abstract class VoxTransport {
  /// Sends an already-encoded message to a Unity game object.
  void send(String gameObjectName, String methodName, String data);

  /// Pauses Unity's time. Unity stays in memory and can still receive messages.
  void pause();

  /// Resumes Unity's time.
  void resume();

  /// Releases any resources held by the transport.
  void dispose() {}
}
