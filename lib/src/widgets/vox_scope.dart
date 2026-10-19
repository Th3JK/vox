import 'package:flutter/widgets.dart';

import '../core/vox_controller.dart';

/// Makes a [VoxController] available to descendants and rebuilds them when its
/// state changes.
///
/// [VoxView] installs one automatically around its subtree, so widgets drawn
/// over Unity can call `VoxScope.of(context)` without any extra wiring.
class VoxScope extends InheritedNotifier<VoxController> {
  /// Provides [controller] to [child].
  const VoxScope({
    super.key,
    required VoxController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The nearest controller, or null if there is none.
  static VoxController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoxScope>()?.notifier;

  /// The nearest controller.
  ///
  /// Throws if called outside a [VoxScope] or [VoxView].
  static VoxController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No VoxScope found above this widget.');
    return controller!;
  }
}
