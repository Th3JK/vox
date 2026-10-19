# vox example

Demonstrates every part of the `vox` API against the `VoxUnity` project.

## Run it on desktop, without Unity

```bash
flutter run -d windows
```

Unity only runs on Android and iOS, so on desktop the app swaps in
[`lib/fake_unity.dart`](lib/fake_unity.dart) — a `VoxTransport` that answers the
handshake, replies to the `example.*` requests, and pushes the occasional event.
The entire UI is live: slider, requests, ping, scene switching, pause, and the
event log.

This is also what the widget tests in [`test/`](test/) drive, which is why they
can cover the whole bridge without a platform view.

## Run it on Android, with Unity

1. In Unity, open `D:\projects\VoxUnity` and check `Assets/Vox/` is present.
2. Add the scenes you want to switch between to **File → Build Settings**:
   `FlutterEmbedExampleScene` and `FlutterEmbedExampleSceneAR`. `loadScene`
   cannot find a scene that is not listed there.
3. Switch the build target to Android, tick **Export project**, and ensure
   ARMv7 + ARM64 are both selected under Player Settings → Target architectures.
4. Run **Flutter Embed → Export project to flutter app (Android)** and select
   `vox/example/android/unityLibrary`.
5. Check the Unity console for the `unityStreamingAssets` value it prints, and
   put it in [`android/gradle.properties`](android/gradle.properties) if it is
   not blank.
6. `flutter run -d <device>` — **on a physical arm64 device**, not an emulator.

### Two things that will bite you

**Use a real device.** Unity exports `arm64-v8a` and `armeabi-v7a` only (see
`AndroidTargetArchitectures` in Unity's Player Settings). The standard Android
emulator images are x86_64, where Unity's native libraries cannot load at all.
Either use a physical device or add x86-64 to Unity's target architectures.

**The Android toolchain is pinned down on purpose.** `gradle-wrapper.properties`
pins Gradle 8.14 and `settings.gradle.kts` pins AGP 8.11.1 / Kotlin 2.2.20.
Unity 2022.3's exported `unityLibrary/build.gradle` calls a script-level
`BuildIl2Cpp()` from a task's `doLast` and uses `Project.exec` inside it, both of
which Gradle 9 broke — you get `Could not find method BuildIl2Cpp()`. Do not let
an IDE "upgrade" these versions.

If IL2CPP itself fails, it is most likely the NDK: Unity 2022.3 is tested
against r23b and AGP picks a newer one. Force it from `android/build.gradle.kts`
(not from `unityLibrary/`, which is regenerated on every export):

```kotlin
subprojects {
    if (name == "unityLibrary") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                ndkVersion = "23.1.7779620"
            }
        }
    }
}
```

`android/settings.gradle.kts` picks up `unityLibrary` only once it exists, so
the app still builds before step 4 — it just fails its handshake and shows the
`FAILED` banner, which is itself worth seeing.

## The Unity render crash, and why the manifest has engine flags

Unity crashed on startup with a null pointer in `ANativeWindow_setBuffersGeometry`
on the `UnityMain` thread. With `kIsolateVoxLifecycle = true` in `lib/main.dart`
— vox issuing no `pauseUnity()`/`resumeUnity()` calls at all — it still crashed,
so vox is not the cause.

The cause is visible in the log:

```
I/PlatformViewsChannel: Using legacy platform view rendering strategy.
I/PlatformViewsController: Hosting view in a virtual display for platform view: 0
D/ViewRootImplStubImpl: surfaceView:com.unity3d.player.f{... app:id/unitySurfaceView}
```

Unity renders through a **SurfaceView**, and Flutter's *legacy* platform-view
strategy hosts platform views in a **VirtualDisplay**, which cannot host a
SurfaceView properly. Unity ends up with a null `ANativeWindow` and segfaults.

`android/app/src/main/AndroidManifest.xml` therefore sets:

```xml
<meta-data android:name="io.flutter.embedding.android.EnableHcpp" android:value="true" />
```

which maps to the engine flag `enable-hcpp-and-surface-control` and switches to
the SurfaceControl-based **HCPP** strategy. Confirm it took effect by looking for
`Using HCPP platform view rendering strategy.` instead of the legacy line.

If it still crashes, the manifest lists the escalation in comments — enable one
at a time: move Impeller off Vulkan (`ImpellerBackend=opengles`), then disable
Impeller (`EnableImpeller=false`), then re-export Unity with OpenGLES3 above
Vulkan. Flutter runs Impeller on Vulkan and this Unity project is Vulkan-first,
so contention between them is the next suspicion.

Once Unity renders, set `kIsolateVoxLifecycle = false` to put vox back in charge
of route/app-lifecycle pausing, and delete the switch.

## What is wired up

| Control | Exercises |
| --- | --- |
| Rotation slider | `vox.send(...)`, fire-and-forget |
| Read speed | `vox.request(...)` with a typed reply |
| Scene info | request returning a decoded object |
| Ping | `vox.ping()` round-trip latency |
| Unknown type | the `unhandledType` error path → `VoxRequestException` |
| Scene buttons | `vox.loadScene(...)` and `VoxSceneChangedEvent` |
| Pause / Resume | `VoxPauseReason.manual` |
| Open details | `VoxPauseReason.routeCovered` via the `RouteObserver` |
| Event log | `vox.events`, including `VoxUnknownEvent` |

Backgrounding the app adds `VoxPauseReason.appBackgrounded`. Because pause
reasons are counted rather than toggled, returning to the foreground while the
details route is still on top leaves Unity paused — the banner shows exactly
which reasons are active.

## Unity side

Handlers live in `VoxUnity/Assets/Vox/Example/VoxExampleHandlers.cs`. It spawns
itself at runtime, so no scene or prefab editing is needed, and it drives the
project's existing `ReceiveFromFlutterRotation` component rather than
duplicating it.
