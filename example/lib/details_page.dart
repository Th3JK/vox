import 'package:flutter/material.dart';
import 'package:vox/vox.dart';

import 'widgets/state_banner.dart';

/// A route pushed over the Unity page, to demonstrate route-visibility pausing.
///
/// Unity is not unloaded on navigation, so without vox it would keep rendering
/// and burning battery behind this page. The banner here should read
/// `PAUSED — paused by routeCovered` the whole time this route is on top, and
/// return to `READY` once it is popped.
class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key, required this.controller});

  final VoxController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Covering route')),
      body: Column(
        children: [
          StateBanner(controller: controller),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unity is paused while this route covers it.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'VoxView subscribed to the app\'s RouteObserver, so pushing '
                    'this page added the routeCovered pause reason. Unity stays '
                    'in memory — it cannot be unloaded — but its time is '
                    'stopped, so it is not consuming CPU behind this page.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Background the whole app from here and the appBackgrounded '
                    'reason is added too. Pause reasons are counted, not '
                    'toggled, so returning to the foreground while this route is '
                    'still on top leaves Unity paused.',
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Anything sent while paused is queued and flushed on '
                    'resume, so nothing is lost.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
