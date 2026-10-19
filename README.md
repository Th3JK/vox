# vox

Typed messaging, lifecycle management and state handling for Unity embedded in
Flutter.

`vox` sits on top of [`flutter_embed_unity`](https://pub.dev/packages/flutter_embed_unity),
which gives you a single raw string channel in each direction. vox adds the
parts you would otherwise write yourself:

- **Typed request/response.** `await vox.request(GetHealth())` instead of firing
  a string and hoping a matching one comes back.
- **A lifecycle state machine.** Unity cannot be unloaded once started, so
  readiness, re-attachment and pausing need real handling.
- **Automatic pause/resume** when the app is backgrounded or the route hosting
  Unity is covered.
- **Message queuing** so calls made before Unity is ready are delivered rather
  than dropped.

No state-management dependency: the API is `Stream`s plus a `ChangeNotifier`, so
it works from bloc, riverpod, provider or plain `setState`.

## Getting started

```yaml
dependencies:
  vox: ^0.1.0
  # Pick the implementation matching your Unity version. vox deliberately does
  # not choose for you, and this must go in your *app's* pubspec: a transitive
  # dependency loses to flutter_embed_unity's endorsed default.
  flutter_embed_unity_2022_3_android: ^2.0.0   # Unity 2022.3
  # flutter_embed_unity_6000_0_android is the endorsed default (Unity 6),
  # so omit the line above if that is what you are on.
```

Include exactly one Android implementation. Two will resolve without error and
then misbehave at runtime, because the endorsed default silently wins. Check
which one you actually got with:

```bash
grep -o '"name":"flutter_embed_unity[^"]*"' .flutter-plugins-dependencies
```

iOS needs nothing extra — `flutter_embed_unity_2022_3_ios` is the endorsed
default and works for both Unity 2022.3 and Unity 6.

Then set up the Unity side — see [`unity/README.md`](unity/README.md) for the
scripts, the `com.unity.nuget.newtonsoft-json` dependency and the `VoxBridge`
game object.

## Usage

Create one controller for the app and hand it to a `VoxView`:

```dart
final vox = VoxController();
final routeObserver = RouteObserver<ModalRoute<void>>();

MaterialApp(
  navigatorObservers: [routeObserver],
  home: Scaffold(
    body: VoxView(
      controller: vox,
      routeObserver: routeObserver,
      placeholder: const Center(child: CircularProgressIndicator()),
    ),
  ),
);
```

### Calling Unity

```dart
class SetSpeed extends VoxCommand {
  const SetSpeed(this.speed);
  final double speed;

  @override
  String get type => 'game.setSpeed';

  @override
  Map<String, Object?> toPayload() => {'speed': speed};
}

class GetHealth extends VoxRequest<int> {
  const GetHealth();

  @override
  String get type => 'game.getHealth';

  @override
  int decodeResponse(Map<String, Object?> payload) => payload['health'] as int;
}

vox.send(const SetSpeed(1.5));           // fire and forget
final health = await vox.request(const GetHealth());
```

### Listening to Unity

```dart
class PlayerDied extends VoxEvent {
  const PlayerDied(this.score);
  final int score;

  factory PlayerDied.fromPayload(Map<String, Object?> p) =>
      PlayerDied(p['score'] as int);
}

vox.registry.register<PlayerDied>('game.playerDied', PlayerDied.fromPayload);
vox.on<PlayerDied>().listen((event) => print(event.score));
```

Events with no registered decoder arrive as `VoxUnknownEvent` rather than being
dropped, so a Flutter/Unity mismatch is visible at runtime.

### Reacting to state

```dart
AnimatedBuilder(
  animation: vox,
  builder: (context, _) => switch (vox.state.lifecycle) {
    VoxLifecycle.ready => const GameHud(),
    VoxLifecycle.failed => ErrorView(onRetry: vox.retry),
    _ => const LoadingView(),
  },
);
```

Descendants of a `VoxView` can reach the controller with
`VoxScope.of(context)`.

## Wire protocol

One JSON object per message, in both directions:

```json
{ "kind": "req", "type": "game.getHealth", "id": "c17", "payload": {} }
```

| Field | Notes |
| --- | --- |
| `kind` | `req`, `res`, `err` or `evt` |
| `type` | Message type; `vox.*` is reserved |
| `id` | Correlation id. Present on `req`/`res`/`err`, absent on `evt` |
| `payload` | Always an object; omitted when empty |

`err` payloads carry `code`, `message` and optional `details`, surfacing in Dart
as `VoxRequestException`.

### The handshake

Unity's `Start()` fires exactly once for the entire life of the app, because
embedded Unity is never unloaded. A view mounted a second time would therefore
wait forever for a `vox.ready` that never comes again. So:

- Unity emits `vox.ready` on `Start()` **and** in reply to every `vox.hello`.
- Flutter sends `vox.hello` on every attach, retrying with backoff until it
  gets a reply.

Both sides treat this as idempotent, which makes it order-independent.

## Lifecycle

`VoxState.lifecycle` moves through `idle → attaching → ready`, with `paused` and
`failed` branches.

Pausing is **reference counted** by `VoxPauseReason`, not a boolean. Several
sources can want Unity paused at once — the app is backgrounded, a route covers
it, you called `pause()` — and Unity resumes only when the last reason is
removed. With a single flag, returning to a route would wrongly resume Unity
while the app was still in the background.

While Unity is paused or not yet ready, outbound messages are queued (bounded,
oldest dropped when full) and flushed on resume. This is deliberate: `pauseUnity()`
zeroes Unity's time scale, so a handler replying from a coroutine would never
run and the request would time out for no good reason. Pass
`sendWhilePaused: true` for handlers known to reply synchronously.

Request timeouts start when the message is actually written to the transport,
not when it is enqueued, so time spent waiting out a pause is not charged
against the caller.

### What vox deliberately does not do

On Android the platform plugin already drives Unity's pause/resume itself: it
pauses and resumes on every activity `ON_RESUME`, again whenever the player's
window becomes visible, and pauses when the Flutter view detaches. Its own
comments describe `UnityPlayer` as fragile in this mode.

So vox stays out of that window:

- `AppLifecycleState.inactive` does **not** pause Unity. It fires transiently on
  window-focus changes, during startup and around platform-view attachment.
  Only `paused`, `hidden` and `detached` count as backgrounded.
- No pause or resume is issued **before the handshake completes**. Reasons
  raised earlier are recorded and applied once Unity reports in, so vox never
  touches Unity while its surface is still being set up.
- Pause and resume are never issued twice in a row for the same state.

## Platform setup

vox depends on the Android and iOS implementations of `flutter_embed_unity`.
Follow that package's setup, in particular:

- **Android** — Unity 2022.3.62f2+ or 6000.0.58f2+; the `unityLibrary` Gradle
  dependency; and `android:configChanges` on your activity must include the
  orientation and screen flags, or the app crashes on rotation.
- **iOS** — iOS 12+ (Unity 2022.3) or 13+ (Unity 6); embed
  `UnityFramework.framework` in Xcode.
- Only one `VoxView` should be visible at a time. Unity is a single instance and
  renders into whichever platform view most recently claimed it.
- On platforms other than Android and iOS, `VoxView` renders a fallback instead
  of throwing, so the rest of your app still runs on a dev machine.

## Example

[`example/`](example/) is a complete demo: connection banner, rotation slider,
typed request/response, ping latency, scene switching, manual pause, and a live
event log. Pushing a route over Unity shows route-visibility pausing in action.

It runs on the desktop with no Unity export at all — `example/lib/fake_unity.dart`
is a `VoxTransport` that simulates Unity, so the whole UI works on a dev machine:

```bash
cd example && flutter run -d windows
```

The Unity-side counterpart lives in `Assets/Vox/Example/VoxExampleHandlers.cs`.

## Testing without Unity

`VoxTransport` is a plain interface, and inbound messages are delivered by
calling `controller.handleRawMessage(json)`. A fake transport that records what
was sent is enough to drive the whole bridge in a unit test — see
`test/vox_test.dart`.
