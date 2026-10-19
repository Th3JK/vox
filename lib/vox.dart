/// Typed messaging, lifecycle management and state handling for Unity embedded
/// in Flutter via `flutter_embed_unity`.
///
/// See the README for the wire protocol and the Unity-side setup.
library;

export 'src/core/vox_controller.dart' show VoxController;
export 'src/core/vox_state.dart' show VoxLifecycle, VoxPauseReason, VoxState;
export 'src/protocol/vox_builtin.dart'
    show
        VoxHelloCommand,
        VoxLoadSceneRequest,
        VoxPingRequest,
        VoxReadyEvent,
        VoxSceneChangedEvent,
        VoxTypes;
export 'src/protocol/vox_codec.dart' show VoxCodec;
export 'src/protocol/vox_envelope.dart' show VoxEnvelope, VoxEnvelopeKind;
export 'src/protocol/vox_exceptions.dart'
    show
        VoxCodecException,
        VoxDisconnectedException,
        VoxException,
        VoxHandshakeException,
        VoxRequestException,
        VoxTimeoutException;
export 'src/protocol/vox_message.dart'
    show VoxCommand, VoxEvent, VoxMessage, VoxRequest, VoxUnknownEvent;
export 'src/protocol/vox_registry.dart' show VoxEventDecoder, VoxRegistry;
export 'src/transport/embed_unity_transport.dart' show EmbedUnityTransport;
export 'src/transport/vox_transport.dart' show VoxTransport;
export 'src/widgets/vox_scope.dart' show VoxScope;
export 'src/widgets/vox_view.dart' show VoxView;
