import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

import '../core/vox_controller.dart';
import '../core/vox_state.dart';
import '../lifecycle/route_visibility_binder.dart';
import 'vox_scope.dart';

/// Renders Unity and wires it to a [VoxController].
///
/// Handles attach/detach, the handshake, route-visibility pausing, and exposes
/// the controller to descendants through a [VoxScope].
///
/// ```dart
/// VoxView(
///   controller: vox,
///   routeObserver: routeObserver,
///   placeholder: const Center(child: CircularProgressIndicator()),
/// )
/// ```
///
/// Only one `VoxView` should be visible at a time: Unity is a single instance
/// and renders into whichever platform view most recently claimed it.
class VoxView extends StatefulWidget {
  /// Creates a Unity view.
  const VoxView({
    super.key,
    this.controller,
    this.routeObserver,
    this.placeholder,
    this.unsupportedPlatformBuilder,
    this.onReady,
  });

  /// The controller to drive. If null, one is created and owned by this widget.
  ///
  /// Because Unity survives for the life of the app, prefer creating a single
  /// controller yourself and passing it in, so state is not lost when the view
  /// is rebuilt on a different route.
  final VoxController? controller;

  /// Route observer used to pause Unity while this route is covered.
  ///
  /// Register the same observer on your `MaterialApp.navigatorObservers`. If
  /// null, route-visibility pausing is disabled.
  final RouteObserver<ModalRoute<void>>? routeObserver;

  /// Shown over Unity until the handshake completes.
  final Widget? placeholder;

  /// Builds the fallback UI on platforms other than Android and iOS.
  ///
  /// `EmbedUnity` throws `UnsupportedError` on desktop and web, so vox renders
  /// this instead — which keeps the rest of an app runnable on a dev machine.
  final WidgetBuilder? unsupportedPlatformBuilder;

  /// Called once when the handshake completes.
  final VoidCallback? onReady;

  @override
  State<VoxView> createState() => _VoxViewState();
}

class _VoxViewState extends State<VoxView> {
  late VoxController _controller;
  bool _ownsController = false;
  RouteVisibilityBinder? _routeBinder;
  bool _notifiedReady = false;

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _adoptController(widget.controller);
  }

  @override
  void didUpdateWidget(VoxView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _releaseController();
      _adoptController(widget.controller);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = widget.routeObserver;
    final route = ModalRoute.of(context);
    if (observer != null && route != null) {
      _routeBinder ??= RouteVisibilityBinder(
        onCovered: () => _controller.addPauseReason(VoxPauseReason.routeCovered),
        onRevealed: () =>
            _controller.removePauseReason(VoxPauseReason.routeCovered),
      );
      _routeBinder!.bind(observer, route);
    }
  }

  void _adoptController(VoxController? provided) {
    _controller = provided ?? VoxController();
    _ownsController = provided == null;
    _notifiedReady = false;
    _controller.addListener(_onControllerChanged);

    // Attached on every platform, including those that cannot render Unity:
    // whether the bridge is live is the transport's business, not the widget's.
    // This is what lets a fake transport drive the whole bridge on desktop.
    //
    // Deferred by one frame because attach() changes controller state
    // synchronously, and notifying listeners from initState would mark widgets
    // that were already built this frame as dirty — a "setState() called during
    // build" crash for anything listening above this view.
    //
    // The ready check is deferred with it: a shared controller that is already
    // connected when this view mounts (a return visit to the Unity route)
    // would otherwise fire onReady from initState, mid-build, and an onReady
    // that calls setState crashes the same way.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.attach();
      _onControllerChanged();
    });
  }

  void _releaseController() {
    _controller.removeListener(_onControllerChanged);
    _controller.detach();
    if (_ownsController) _controller.dispose();
  }

  void _onControllerChanged() {
    if (!_notifiedReady && _controller.state.isConnected) {
      _notifiedReady = true;
      widget.onReady?.call();
    }
  }

  @override
  void dispose() {
    _routeBinder?.unbind();
    _routeBinder = null;
    _releaseController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupportedPlatform) {
      return VoxScope(
        controller: _controller,
        child: Builder(
          builder:
              widget.unsupportedPlatformBuilder ?? _defaultUnsupportedBuilder,
        ),
      );
    }

    return VoxScope(
      controller: _controller,
      child: Stack(
        fit: StackFit.expand,
        children: [
          EmbedUnity(onMessageFromUnity: _controller.handleRawMessage),
          if (widget.placeholder != null)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => _controller.state.isConnected
                  ? const SizedBox.shrink()
                  : child!,
              child: widget.placeholder,
            ),
        ],
      ),
    );
  }

  static Widget _defaultUnsupportedBuilder(BuildContext context) {
    return const Center(
      child: Text(
        'Unity is only available on Android and iOS.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
