import 'dart:collection';

import 'vox_state.dart';

/// Tracks *why* Unity is paused rather than simply *whether* it is.
///
/// Several independent sources can want Unity paused at once (the app is
/// backgrounded, a route covered it, the developer called `pause()`). With a
/// single boolean, whichever source resumed last would win and Unity would
/// resume while another source still wanted it stopped. Here Unity resumes only
/// when the last reason is removed.
class PauseCoordinator {
  final Set<VoxPauseReason> _reasons = <VoxPauseReason>{};

  /// The reasons currently holding Unity paused.
  Set<VoxPauseReason> get reasons => UnmodifiableSetView(_reasons);

  /// Whether anything wants Unity paused.
  bool get isPaused => _reasons.isNotEmpty;

  /// Adds [reason].
  ///
  /// Returns true only if this transitioned from running to paused, so the
  /// caller knows whether to actually call into the transport.
  bool add(VoxPauseReason reason) {
    final wasPaused = isPaused;
    _reasons.add(reason);
    return !wasPaused && isPaused;
  }

  /// Removes [reason].
  ///
  /// Returns true only if this transitioned from paused to running.
  bool remove(VoxPauseReason reason) {
    final wasPaused = isPaused;
    _reasons.remove(reason);
    return wasPaused && !isPaused;
  }

  /// Removes every reason. Returns true if that resumed Unity.
  bool clear() {
    final wasPaused = isPaused;
    _reasons.clear();
    return wasPaused;
  }
}
