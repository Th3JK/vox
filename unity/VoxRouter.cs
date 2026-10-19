using System;
using System.Collections.Generic;
using System.Reflection;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace Vox
{
    /// <summary>
    /// Marks a method as the handler for a vox message type. The method must
    /// take a single <see cref="VoxContext"/> parameter.
    ///
    /// Attribute discovery uses reflection, so handler types must survive
    /// managed code stripping on IL2CPP builds. Either keep the entries in
    /// link.xml, or prefer the explicit <see cref="VoxRouter.On"/> form.
    /// </summary>
    [AttributeUsage(AttributeTargets.Method, AllowMultiple = true)]
    public class VoxHandlerAttribute : Attribute
    {
        public readonly string Type;

        public VoxHandlerAttribute(string type)
        {
            Type = type;
        }
    }

    /// <summary>
    /// Everything a handler needs to read a message and reply to it.
    /// </summary>
    public class VoxContext
    {
        public string Type { get; internal set; }

        /// <summary>Correlation id, or null when this is a one-way event.</summary>
        public string Id { get; internal set; }

        public JObject Payload { get; internal set; }

        /// <summary>Whether Flutter is waiting for a reply.</summary>
        public bool IsRequest
        {
            get { return !string.IsNullOrEmpty(Id); }
        }

        internal bool Replied { get; private set; }

        /// <summary>Deserialises the payload into a typed object.</summary>
        public T PayloadAs<T>()
        {
            return Payload == null ? default(T) : Payload.ToObject<T>();
        }

        /// <summary>Reads a single payload field, with a fallback.</summary>
        public T Get<T>(string key, T fallback = default(T))
        {
            if (Payload == null)
            {
                return fallback;
            }

            JToken token;
            return Payload.TryGetValue(key, out token) ? token.ToObject<T>() : fallback;
        }

        /// <summary>
        /// Replies successfully. No-op for one-way events, and for a context
        /// that has already been replied to.
        /// </summary>
        public void Respond(object payload = null)
        {
            if (!IsRequest || Replied)
            {
                return;
            }

            Replied = true;
            VoxBridge.Send(VoxEnvelope.Response(Id, Type, payload));
        }

        /// <summary>Replies with an error.</summary>
        public void Fail(string code, string message, string details = null)
        {
            if (!IsRequest || Replied)
            {
                return;
            }

            Replied = true;
            VoxBridge.Send(VoxEnvelope.Error(Id, code, message, details));
        }
    }

    /// <summary>
    /// Maps message types onto handlers.
    /// </summary>
    public static class VoxRouter
    {
        static readonly Dictionary<string, Action<VoxContext>> Handlers =
            new Dictionary<string, Action<VoxContext>>();

        /// <summary>
        /// Registers <paramref name="handler"/> for <paramref name="type"/>,
        /// replacing any previous registration.
        ///
        /// This is the IL2CPP-safe form: no reflection is involved.
        /// </summary>
        public static void On(string type, Action<VoxContext> handler)
        {
            if (string.IsNullOrEmpty(type) || handler == null)
            {
                Debug.LogWarning("[vox] ignoring handler registration with a null type or handler");
                return;
            }

            Handlers[type] = handler;
        }

        /// <summary>Removes the handler for <paramref name="type"/>.</summary>
        public static void Off(string type)
        {
            Handlers.Remove(type);
        }

        /// <summary>Whether a handler exists for <paramref name="type"/>.</summary>
        public static bool Has(string type)
        {
            return Handlers.ContainsKey(type);
        }

        /// <summary>
        /// Registers every <see cref="VoxHandlerAttribute"/>-marked method on
        /// <paramref name="target"/>. Call from Awake or Start, and call
        /// <see cref="UnregisterHandlers"/> from OnDestroy.
        /// </summary>
        public static void RegisterHandlers(object target)
        {
            if (target == null)
            {
                return;
            }

            // No DeclaredOnly: handlers declared on a base class must be
            // picked up too.
            const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public |
                                       BindingFlags.NonPublic;

            foreach (var method in target.GetType().GetMethods(flags))
            {
                var attributes = method.GetCustomAttributes(typeof(VoxHandlerAttribute), true);
                if (attributes.Length == 0)
                {
                    continue;
                }

                var parameters = method.GetParameters();
                if (parameters.Length != 1 || parameters[0].ParameterType != typeof(VoxContext))
                {
                    Debug.LogErrorFormat(
                        "[vox] {0}.{1} is marked [VoxHandler] but does not take a single VoxContext parameter",
                        target.GetType().Name, method.Name);
                    continue;
                }

                var bound = (Action<VoxContext>)Delegate.CreateDelegate(
                    typeof(Action<VoxContext>), target, method);

                foreach (VoxHandlerAttribute attribute in attributes)
                {
                    On(attribute.Type, bound);
                }
            }
        }

        /// <summary>
        /// Removes every handler registered from <paramref name="target"/>.
        /// </summary>
        public static void UnregisterHandlers(object target)
        {
            if (target == null)
            {
                return;
            }

            var stale = new List<string>();
            foreach (var entry in Handlers)
            {
                if (ReferenceEquals(entry.Value.Target, target))
                {
                    stale.Add(entry.Key);
                }
            }

            foreach (var type in stale)
            {
                Handlers.Remove(type);
            }
        }

        /// <summary>
        /// Runs the handler for <paramref name="context"/>. Returns false when
        /// no handler is registered.
        /// </summary>
        internal static bool Dispatch(VoxContext context)
        {
            Action<VoxContext> handler;
            if (!Handlers.TryGetValue(context.Type, out handler))
            {
                return false;
            }

            try
            {
                handler(context);
            }
            catch (Exception e)
            {
                Debug.LogException(e);
                context.Fail("handlerThrew", e.Message, e.ToString());
            }

            return true;
        }
    }
}
