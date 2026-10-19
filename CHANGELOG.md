## 0.1.0

Initial release.

- Typed request/response messaging over a JSON envelope with correlation ids.
- `VoxController`: handshake, message routing, state, and a `ChangeNotifier` /
  `Stream` API with no state-management dependency.
- Automatic pause/resume on app background/foreground and route visibility,
  reference counted by `VoxPauseReason`.
- Outbound message queuing while Unity is not ready or is paused.
- Scene tracking via `vox.scene.load` and `vox.scene.changed`.
- `VoxView` and `VoxScope` widgets, with a fallback on non-mobile platforms.
- Unity-side scripts (`VoxBridge`, `VoxRouter`, `VoxEnvelope`) built on the
  Newtonsoft Json Unity package, plus a `link.xml` for IL2CPP stripping.
  `VoxBridge` bootstraps itself at runtime, so no scene setup is required.
- Example app with a simulated-Unity transport, so the demo runs on desktop
  without exporting a Unity project.
- The Android implementation of `flutter_embed_unity` is chosen by the consuming
  app, not pinned by vox, so the package works with both Unity 2022.3 and
  Unity 6.
- vox no longer pauses Unity on `AppLifecycleState.inactive`, and issues no
  pause/resume at all before the handshake completes, to avoid competing with
  the Android plugin's own pause/resume handling during Unity startup.
