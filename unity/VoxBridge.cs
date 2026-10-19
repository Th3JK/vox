using System;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Vox
{
    /// <summary>
    /// The Unity end of the vox bridge.
    ///
    /// Attach to a game object named "VoxBridge" (the name Flutter addresses
    /// messages to). Survives scene loads via DontDestroyOnLoad, matching the
    /// Flutter side, where Unity itself lives for the whole life of the app.
    /// </summary>
    [DefaultExecutionOrder(-1000)]
    public class VoxBridge : MonoBehaviour
    {
        /// <summary>
        /// Must match VoxController.defaultGameObjectName on the Dart side.
        /// </summary>
        public const string GameObjectName = "VoxBridge";

        static VoxBridge _instance;

        /// <summary>Whether a bridge is alive and able to send.</summary>
        public static bool IsAlive
        {
            get { return _instance != null; }
        }

        /// <summary>
        /// Creates the bridge automatically, so no scene setup is required.
        /// </summary>
        /// <remarks>
        /// AfterSceneLoad rather than BeforeSceneLoad on purpose: scene objects
        /// have already run Awake by this point, so a VoxBridge placed in the
        /// scene by hand has claimed _instance and wins. BeforeSceneLoad would
        /// spawn a second bridge first and then destroy the hand-placed one,
        /// silently discarding whatever was configured on it in the Inspector.
        /// </remarks>
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Bootstrap()
        {
            if (_instance != null)
            {
                return;
            }

            // Awake handles naming and DontDestroyOnLoad.
            new GameObject(GameObjectName).AddComponent<VoxBridge>();
        }

        void Awake()
        {
            if (_instance != null && _instance != this)
            {
                Debug.LogWarning("[vox] a second VoxBridge was created; destroying the duplicate");
                Destroy(gameObject);
                return;
            }

            _instance = this;

            // Flutter addresses messages by game object name, so the name must
            // match regardless of what the object is called in the scene.
            if (gameObject.name != GameObjectName)
            {
                Debug.LogWarningFormat(
                    "[vox] renaming game object \"{0}\" to \"{1}\" so Flutter can address it",
                    gameObject.name, GameObjectName);
                gameObject.name = GameObjectName;
            }

            DontDestroyOnLoad(gameObject);
            RegisterBuiltins();
            SceneManager.activeSceneChanged += OnActiveSceneChanged;
        }

        void Start()
        {
            // Fires exactly once for the life of the app. Flutter also probes
            // with vox.hello on every attach, which is what makes re-entering
            // the Unity route work.
            EmitReady();
        }

        void OnDestroy()
        {
            if (_instance != this)
            {
                return;
            }

            SceneManager.activeSceneChanged -= OnActiveSceneChanged;
            _instance = null;
        }

        // ---------------------------------------------------------------------
        // Inbound
        // ---------------------------------------------------------------------

        /// <summary>
        /// Entry point for messages from Flutter. Called by UnitySendMessage,
        /// so the name must match VoxController.defaultMethodName.
        /// </summary>
        public void OnFlutterMessage(string json)
        {
            VoxEnvelope envelope;
            try
            {
                envelope = VoxEnvelope.FromJson(json);
            }
            catch (Exception e)
            {
                Debug.LogErrorFormat("[vox] could not parse message from Flutter: {0}\n{1}", e.Message, json);
                return;
            }

            if (envelope == null || string.IsNullOrEmpty(envelope.Type))
            {
                Debug.LogErrorFormat("[vox] message from Flutter is not a vox envelope: {0}", json);
                return;
            }

            var context = new VoxContext
            {
                Type = envelope.Type,
                Id = envelope.Id,
                Payload = envelope.Payload ?? new JObject()
            };

            if (VoxRouter.Dispatch(context))
            {
                return;
            }

            // Unhandled requests must be answered, or Flutter waits for its
            // full timeout before failing.
            if (context.IsRequest)
            {
                context.Fail("unhandledType",
                    string.Format("No Unity handler is registered for \"{0}\"", context.Type));
            }
            else
            {
                Debug.LogWarningFormat("[vox] no handler registered for event \"{0}\"", context.Type);
            }
        }

        // ---------------------------------------------------------------------
        // Outbound
        // ---------------------------------------------------------------------

        /// <summary>Sends an envelope to Flutter.</summary>
        public static void Send(VoxEnvelope envelope)
        {
            if (envelope == null)
            {
                return;
            }

            try
            {
                SendToFlutter.Send(envelope.ToJson());
            }
            catch (Exception e)
            {
                // In the Editor SendToFlutter just logs, so this is only
                // reached if the native side genuinely fails. Either way a
                // failed send must not take down the calling handler.
                Debug.LogWarningFormat("[vox] could not send to Flutter: {0}", e.Message);
            }
        }

        /// <summary>
        /// Pushes an unsolicited event to Flutter. <paramref name="payload"/>
        /// may be a JObject or any object Newtonsoft can serialise.
        /// </summary>
        public static void Emit(string type, object payload = null)
        {
            Send(VoxEnvelope.Event(type, payload));
        }

        // ---------------------------------------------------------------------
        // Built-in handlers
        // ---------------------------------------------------------------------

        void RegisterBuiltins()
        {
            VoxRouter.On(VoxTypes.Hello, OnHello);
            VoxRouter.On(VoxTypes.Ping, OnPing);
            VoxRouter.On(VoxTypes.LoadScene, OnLoadScene);
        }

        void OnHello(VoxContext context)
        {
            // Answering every hello, not just the first, is what lets Flutter
            // re-establish the handshake after the Unity route is re-entered.
            EmitReady();
        }

        void OnPing(VoxContext context)
        {
            context.Respond(new JObject
            {
                ["sentAt"] = context.Get<long>("sentAt"),
                ["receivedAt"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
            });
        }

        void OnLoadScene(VoxContext context)
        {
            var sceneName = context.Get<string>("sceneName");
            if (string.IsNullOrEmpty(sceneName))
            {
                context.Fail("invalidPayload", "sceneName is required");
                return;
            }

            var additive = context.Get("additive", false);
            try
            {
                SceneManager.LoadScene(sceneName,
                    additive ? LoadSceneMode.Additive : LoadSceneMode.Single);
            }
            catch (Exception e)
            {
                context.Fail("sceneLoadFailed", e.Message, e.ToString());
                return;
            }

            // Confirms the load was accepted. The scene is not active yet;
            // Flutter learns that from vox.scene.changed.
            context.Respond();
        }

        void OnActiveSceneChanged(Scene from, Scene to)
        {
            Emit(VoxTypes.SceneChanged, new JObject
            {
                ["from"] = from.IsValid() ? from.name : null,
                ["to"] = to.name
            });
        }

        void EmitReady()
        {
            Emit(VoxTypes.Ready, new JObject
            {
                ["activeScene"] = SceneManager.GetActiveScene().name,
                ["unityVersion"] = Application.unityVersion
            });
        }
    }
}
