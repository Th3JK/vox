import 'package:flutter/material.dart';

/// One line in the log.
class LogEntry {
  LogEntry(this.text, {this.isError = false}) : at = DateTime.now();

  final String text;
  final bool isError;
  final DateTime at;

  String get timestamp =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}

/// A scrolling log of events and request results, newest first.
class EventLog extends StatelessWidget {
  const EventLog({super.key, required this.entries});

  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No events yet.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.timestamp,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.text,
                  style: TextStyle(
                    color: entry.isError
                        ? Colors.red.shade300
                        : Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
