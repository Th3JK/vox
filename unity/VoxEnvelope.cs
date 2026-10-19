using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using UnityEngine.Scripting;

namespace Vox
{
    /// <summary>
    /// The four kinds of message that can cross the Flutter/Unity boundary.
    /// Values must match VoxEnvelopeKind on the Dart side.
    /// </summary>
    public static class VoxKind
    {
        public const string Request = "req";
        public const string Response = "res";
        public const string Error = "err";
        public const string Event = "evt";
    }

    /// <summary>
    /// Message types reserved by vox itself. Application types must not use
    /// the "vox." prefix.
    /// </summary>
    public static class VoxTypes
    {
        public const string Hello = "vox.hello";
        public const string Ready = "vox.ready";
        public const string LoadScene = "vox.scene.load";
        public const string SceneChanged = "vox.scene.changed";
        public const string Ping = "vox.ping";
        public const string Error = "vox.error";
    }

    /// <summary>
    /// A single vox message, in the shape it takes on the wire:
    /// { "kind": "req", "type": "scene.load", "id": "c17", "payload": {} }
    /// </summary>
    [Preserve]
    public class VoxEnvelope
    {
        [JsonProperty("kind")] public string Kind;
        [JsonProperty("type")] public string Type;

        [JsonProperty("id", NullValueHandling = NullValueHandling.Ignore)]
        public string Id;

        [JsonProperty("payload", NullValueHandling = NullValueHandling.Ignore)]
        public JObject Payload;

        public static VoxEnvelope Event(string type, object payload = null)
        {
            return new VoxEnvelope
            {
                Kind = VoxKind.Event,
                Type = type,
                Payload = ToPayload(payload)
            };
        }

        /// <summary>
        /// Builds a reply. <paramref name="type"/> echoes the request's type;
        /// Flutter routes on <paramref name="id"/>, but echoing keeps logs
        /// readable.
        /// </summary>
        public static VoxEnvelope Response(string id, string type, object payload = null)
        {
            return new VoxEnvelope
            {
                Kind = VoxKind.Response,
                Type = type,
                Id = id,
                Payload = ToPayload(payload)
            };
        }

        public static VoxEnvelope Error(string id, string code, string message, string details = null)
        {
            var payload = new JObject
            {
                ["code"] = code,
                ["message"] = message
            };
            if (!string.IsNullOrEmpty(details))
            {
                payload["details"] = details;
            }

            return new VoxEnvelope
            {
                Kind = VoxKind.Error,
                Type = VoxTypes.Error,
                Id = id,
                Payload = payload
            };
        }

        public string ToJson()
        {
            return JsonConvert.SerializeObject(this);
        }

        public static VoxEnvelope FromJson(string json)
        {
            return JsonConvert.DeserializeObject<VoxEnvelope>(json);
        }

        static JObject ToPayload(object payload)
        {
            if (payload == null)
            {
                return null;
            }

            var asObject = payload as JObject;
            return asObject ?? JObject.FromObject(payload);
        }
    }
}
