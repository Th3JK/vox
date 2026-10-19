import 'package:flutter/widgets.dart';

/// Pauses Unity while the route hosting it is covered by another route.
///
/// Unity is not unloaded on navigation, so without this it keeps rendering
/// behind whatever was pushed on top of it.
class RouteVisibilityBinder with RouteAware {
  /// Creates a binder. Call [bind] once a [ModalRoute] is available.
  RouteVisibilityBinder({required this.onCovered, required this.onRevealed});

  /// Invoked when another route is pushed over this one.
  final VoidCallback onCovered;

  /// Invoked when this route becomes the top-most one again.
  final VoidCallback onRevealed;

  RouteObserver<ModalRoute<void>>? _observer;

  /// Subscribes to [observer] for [route]. Re-binding to the same route is a
  /// no-op, which makes it safe to call from `didChangeDependencies`.
  void bind(RouteObserver<ModalRoute<void>> observer, ModalRoute<void> route) {
    if (identical(_observer, observer)) return;
    unbind();
    _observer = observer;
    observer.subscribe(this, route);
  }

  /// Unsubscribes from the route observer. Idempotent.
  void unbind() {
    _observer?.unsubscribe(this);
    _observer = null;
  }

  @override
  void didPushNext() => onCovered();

  @override
  void didPopNext() => onRevealed();
}
