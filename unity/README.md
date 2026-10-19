# vox — Unity side

Drop-in bridge scripts that pair with the `vox` Flutter package.

## 1. Install the JSON dependency

vox uses the official Newtonsoft Json Unity package. In Unity:

**Window → Package Manager → + → Add package by name…** and enter:

```
com.unity.nuget.newtonsoft-json
```

Or add it to `Packages/manifest.json`:

```json
"com.unity.nuget.newtonsoft-json": "3.2.2"
```

Notes:

- **It may already be there.** Unity Version Control, Unity Gaming Services and
  some Addressables versions depend on it. Check the Package Manager before
  adding it.
- **Duplicate assembly errors** mean the project also has a hand-imported
  `Newtonsoft.Json.dll` (usually under `Assets/Plugins`). Delete the manual copy
  and keep the UPM package.
- Use the `Newtonsoft.Json` namespace, **not** `Unity.Plastic.Newtonsoft.Json` —
  that is a separate, internally renamed copy bundled with Version Control.

## 2. Add the scripts

Copy `VoxBridge.cs`, `VoxRouter.cs`, `VoxEnvelope.cs` and `link.xml` into your
Unity project, e.g. `Assets/Vox/Runtime/`.

These files are the canonical source; the copy inside a Unity project is exactly
that, a copy. If you change one, change both.

This assumes `SendToFlutter.cs` from `flutter_embed_unity` is already installed
(it ships in `flutter_embed_unity_2022_3.unitypackage`). vox calls
`SendToFlutter.Send(string)` to reach Flutter.

## 3. The bridge game object — nothing to do

`VoxBridge` creates itself on startup via `[RuntimeInitializeOnLoadMethod]`, in
every scene, so there is no scene setup and nothing to forget when you add a
scene later.

If you would rather see it in the hierarchy, add an empty game object named
`VoxBridge` with the `VoxBridge` component attached. A hand-placed bridge wins:
the bootstrap runs `AfterSceneLoad`, by which point your object has already
claimed the singleton.

The name matters either way — Flutter addresses messages to a game object by
name. If you rename it, pass the new name to
`VoxController(gameObjectName: ...)`.

## 4. Handle messages

The explicit form, which is safest under IL2CPP because no reflection is
involved:

```csharp
using Vox;
using UnityEngine;

public class PlayerController : MonoBehaviour
{
    void Awake()
    {
        VoxRouter.On("game.setSpeed", ctx =>
        {
            speed = ctx.Get<float>("speed");
            ctx.Respond(); // only needed if Flutter used request()
        });

        VoxRouter.On("game.getHealth", ctx =>
        {
            ctx.Respond(new { health = currentHealth });
        });
    }

    void OnDestroy()
    {
        VoxRouter.Off("game.setSpeed");
        VoxRouter.Off("game.getHealth");
    }
}
```

The attribute form, if you prefer handlers as methods:

```csharp
public class PlayerController : MonoBehaviour
{
    void Awake() => VoxRouter.RegisterHandlers(this);
    void OnDestroy() => VoxRouter.UnregisterHandlers(this);

    [VoxHandler("game.setSpeed")]
    void SetSpeed(VoxContext ctx)
    {
        speed = ctx.Get<float>("speed");
        ctx.Respond();
    }
}
```

`RegisterHandlers` uses reflection, so keep the `link.xml` entries if you ship
a stripped IL2CPP build.

## 5. Push events to Flutter

```csharp
VoxBridge.Emit("game.playerDied", new { score = 1200 });
```

Register a decoder for it on the Flutter side, or it arrives as a
`VoxUnknownEvent`.

## Replying

- `ctx.Respond(payload)` — success. Ignored for one-way events.
- `ctx.Fail(code, message, details)` — surfaces as `VoxRequestException` in Dart.
- A handler that throws is caught and auto-converted to a `handlerThrew` error,
  so a Dart `await` never hangs on a C# exception.
- A request with no registered handler is answered with `unhandledType` rather
  than being ignored, so Flutter fails immediately instead of waiting out its
  timeout.

## Built-in message types

| Type | Direction | Purpose |
| --- | --- | --- |
| `vox.hello` | Flutter → Unity | Handshake probe, sent on every attach |
| `vox.ready` | Unity → Flutter | Sent on `Start()` and for every `vox.hello` |
| `vox.ping` | Flutter → Unity | Round-trip liveness check |
| `vox.scene.load` | Flutter → Unity | `SceneManager.LoadScene` |
| `vox.scene.changed` | Unity → Flutter | Emitted from `activeSceneChanged` |

Do not prefix your own types with `vox.`.
