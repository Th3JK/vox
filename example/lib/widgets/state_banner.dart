import 'package:flutter/material.dart';
import 'package:vox/vox.dart';

/// Shows the live bridge state: lifecycle, active scene and pause reasons.
class StateBanner extends StatelessWidget {
  const StateBanner({super.key, required this.controller});

  final VoxController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: _colorFor(state.lifecycle).withValues(alpha: 0.92),
          child: Row(
            children: [
              Icon(_iconFor(state.lifecycle), size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.lifecycle.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      _detailFor(state),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (state.lifecycle == VoxLifecycle.failed)
                TextButton(
                  onPressed: controller.retry,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _detailFor(VoxState state) {
    if (state.lifecycle == VoxLifecycle.failed) {
      return '${state.lastError}';
    }
    final scene = state.activeScene ?? 'unknown scene';
    if (state.pauseReasons.isEmpty) return scene;
    return '$scene — paused by ${state.pauseReasons.map((r) => r.name).join(', ')}';
  }

  static Color _colorFor(VoxLifecycle lifecycle) => switch (lifecycle) {
    VoxLifecycle.ready => Colors.green.shade700,
    VoxLifecycle.paused => Colors.orange.shade800,
    VoxLifecycle.failed => Colors.red.shade700,
    _ => Colors.blueGrey.shade700,
  };

  static IconData _iconFor(VoxLifecycle lifecycle) => switch (lifecycle) {
    VoxLifecycle.ready => Icons.check_circle_outline,
    VoxLifecycle.paused => Icons.pause_circle_outline,
    VoxLifecycle.failed => Icons.error_outline,
    _ => Icons.hourglass_empty,
  };
}
