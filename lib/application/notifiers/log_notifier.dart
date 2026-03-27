import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String   source;
  final String   message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  String get levelLabel => switch (level) {
    LogLevel.debug   => 'DBG',
    LogLevel.info    => 'INF',
    LogLevel.warning => 'WRN',
    LogLevel.error   => 'ERR',
  };

  String get timeStr {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2,'0')}:'
        '${t.minute.toString().padLeft(2,'0')}:'
        '${t.second.toString().padLeft(2,'0')}.'
        '${(t.millisecond ~/ 10).toString().padLeft(2,'0')}';
  }
}

/// Global in-memory log buffer (max 2000 entries).
class LogNotifier extends StateNotifier<List<LogEntry>> {
  static const _maxEntries = 2000;

  LogNotifier() : super([]);

  void _add(LogLevel level, String source, String message) {
    final entry = LogEntry(
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: message);
    final list = [...state, entry];
    state = list.length > _maxEntries
        ? list.sublist(list.length - _maxEntries)
        : list;
  }

  void debug  (String src, String msg) => _add(LogLevel.debug,   src, msg);
  void info   (String src, String msg) => _add(LogLevel.info,    src, msg);
  void warning(String src, String msg) => _add(LogLevel.warning, src, msg);
  void error  (String src, String msg) => _add(LogLevel.error,   src, msg);

  void clear() => state = [];
}

// Global accessor (used by infrastructure layers without Ref)
LogNotifier? _globalLog;
LogNotifier get globalLog => _globalLog ??= LogNotifier();

void initGlobalLog(LogNotifier log) => _globalLog = log;
