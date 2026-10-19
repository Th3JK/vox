import 'package:vox/vox.dart';

/// Message types handled by `Assets/Vox/Example/VoxExampleHandlers.cs` in the
/// VoxUnity project. Keep the strings in step with the constants there.
abstract final class ExampleTypes {
  static const String setRotationSpeed = 'example.setRotationSpeed';
  static const String getRotationSpeed = 'example.getRotationSpeed';
  static const String getSceneInfo = 'example.getSceneInfo';
  static const String touched = 'example.touched';
}

/// Sets how fast the Flutter logo spins. Fire-and-forget.
class SetRotationSpeed extends VoxCommand {
  const SetRotationSpeed(this.speed);

  /// Degrees per second.
  final double speed;

  @override
  String get type => ExampleTypes.setRotationSpeed;

  @override
  Map<String, Object?> toPayload() => {'speed': speed};
}

/// Reads the current rotation speed back from Unity.
class GetRotationSpeed extends VoxRequest<double> {
  const GetRotationSpeed();

  @override
  String get type => ExampleTypes.getRotationSpeed;

  @override
  double decodeResponse(Map<String, Object?> payload) =>
      (payload['speed'] as num).toDouble();
}

/// What Unity reports about itself.
class SceneInfo {
  const SceneInfo({required this.scene, required this.unityVersion});

  final String scene;
  final String unityVersion;

  @override
  String toString() => '$scene (Unity $unityVersion)';
}

/// Asks Unity which scene is active and which runtime version it is.
class GetSceneInfo extends VoxRequest<SceneInfo> {
  const GetSceneInfo();

  @override
  String get type => ExampleTypes.getSceneInfo;

  @override
  SceneInfo decodeResponse(Map<String, Object?> payload) => SceneInfo(
    scene: payload['scene'] as String? ?? 'unknown',
    unityVersion: payload['unityVersion'] as String? ?? 'unknown',
  );
}

/// Pushed by Unity when a collider is tapped.
class LogoTouched extends VoxEvent {
  const LogoTouched(this.objectName);

  factory LogoTouched.fromPayload(Map<String, Object?> payload) =>
      LogoTouched(payload['objectName'] as String? ?? 'unknown');

  final String objectName;

  @override
  String toString() => 'LogoTouched($objectName)';
}

/// Scenes present in the VoxUnity project. They must also be listed in Unity's
/// Build Settings for `loadScene` to find them.
abstract final class ExampleScenes {
  static const String main = 'FlutterEmbedExampleScene';
  static const String ar = 'FlutterEmbedExampleSceneAR';

  static const List<String> all = [main, ar];
}

/// Registers the example's event decoders on [controller].
void registerExampleMessages(VoxController controller) {
  controller.registry.register<LogoTouched>(
    ExampleTypes.touched,
    LogoTouched.fromPayload,
  );
}
