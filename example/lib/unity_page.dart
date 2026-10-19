import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vox/vox.dart';

import 'details_page.dart';
import 'messages.dart';
import 'widgets/event_log.dart';
import 'widgets/state_banner.dart';

/// Unity plus a control panel exercising every part of the vox API.
class UnityPage extends StatefulWidget {
  const UnityPage({
    super.key,
    required this.controller,
    required this.routeObserver,
  });

  final VoxController controller;

  /// Null disables route-visibility pausing, as [VoxView] documents.
  final RouteObserver<ModalRoute<void>>? routeObserver;

  @override
  State<UnityPage> createState() => _UnityPageState();
}

class _UnityPageState extends State<UnityPage> {
  static const int _maxLogEntries = 100;

  final List<LogEntry> _log = [];
  StreamSubscription<VoxEvent>? _eventSub;
  double _speed = 20;

  VoxController get _vox => widget.controller;

  @override
  void initState() {
    super.initState();
    _eventSub = _vox.events.listen((event) {
      _append(switch (event) {
        LogoTouched(:final objectName) => 'touched: $objectName',
        VoxSceneChangedEvent(:final from, :final to) => 'scene: $from -> $to',
        VoxReadyEvent(:final unityVersion) => 'ready (Unity $unityVersion)',
        VoxUnknownEvent(:final type) => 'unknown event: $type',
        _ => '$event',
      });
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _append(String text, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, LogEntry(text, isError: isError));
      if (_log.length > _maxLogEntries) _log.removeLast();
    });
  }

  /// Runs [action], logging whatever it produces or throws.
  ///
  /// Every vox failure mode is a typed exception, so the example can report
  /// them meaningfully instead of showing a bare "something went wrong".
  Future<void> _run(String label, Future<String> Function() action) async {
    try {
      _append('$label...');
      _append('$label -> ${await action()}');
    } on VoxRequestException catch (e) {
      _append('$label failed: Unity reported ${e.code} (${e.message})', isError: true);
    } on VoxTimeoutException catch (e) {
      _append('$label timed out after ${e.timeout.inMilliseconds}ms', isError: true);
    } on VoxException catch (e) {
      _append('$label failed: ${e.message}', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StateBanner(controller: _vox),
            Expanded(
              flex: 3,
              child: VoxView(
                controller: _vox,
                routeObserver: widget.routeObserver,
                placeholder: const ColoredBox(
                  color: Color(0xFF12161C),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            Expanded(flex: 4, child: _buildControls()),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: const Color(0xFF12161C),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Rotation speed — send(), fire and forget'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _speed,
                        min: 0,
                        max: 200,
                        divisions: 40,
                        label: _speed.round().toString(),
                        onChanged: (value) {
                          setState(() => _speed = value);
                          _vox.send(SetRotationSpeed(value));
                        },
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        _speed.round().toString(),
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _label('Requests — await a typed reply'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _button('Read speed', () async {
                      await _run('getRotationSpeed', () async {
                        final speed = await _vox.request(const GetRotationSpeed());
                        if (mounted) setState(() => _speed = speed);
                        return speed.toStringAsFixed(1);
                      });
                    }),
                    _button('Scene info', () async {
                      await _run(
                        'getSceneInfo',
                        () async => '${await _vox.request(const GetSceneInfo())}',
                      );
                    }),
                    _button('Ping', () async {
                      await _run(
                        'ping',
                        () async => '${(await _vox.ping()).inMilliseconds}ms',
                      );
                    }),
                    _button('Unknown type', () async {
                      // Shows the unhandledType error path end to end.
                      await _run(
                        'nonexistent',
                        () => _vox.request(const _Nonexistent()),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                _label('Scenes and lifecycle'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scene in ExampleScenes.all)
                      _button(scene.replaceFirst('FlutterEmbedExampleScene', 'Scene'), () async {
                        await _run('loadScene($scene)', () async {
                          await _vox.loadScene(scene);
                          return 'accepted';
                        });
                      }),
                    AnimatedBuilder(
                      animation: _vox,
                      builder: (context, _) {
                        final manuallyPaused = _vox.state.pauseReasons.contains(
                          VoxPauseReason.manual,
                        );
                        return _button(
                          manuallyPaused ? 'Resume' : 'Pause',
                          () {
                            manuallyPaused ? _vox.resume() : _vox.pause();
                            _append(manuallyPaused ? 'resumed' : 'paused (manual)');
                          },
                        );
                      },
                    ),
                    _button('Open details', () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DetailsPage(controller: _vox),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(child: _label('Event log')),
                if (_log.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_log.clear),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Expanded(child: EventLog(entries: _log)),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Colors.white38,
      fontSize: 11,
      letterSpacing: 0.8,
      fontWeight: FontWeight.bold,
    ),
  );

  Widget _button(String label, VoidCallback onPressed) =>
      FilledButton.tonal(onPressed: onPressed, child: Text(label));
}

/// A request Unity has no handler for, used to demonstrate the error path.
class _Nonexistent extends VoxRequest<String> {
  const _Nonexistent();

  @override
  String get type => 'example.nonexistent';

  @override
  String decodeResponse(Map<String, Object?> payload) => 'unexpected success';
}
