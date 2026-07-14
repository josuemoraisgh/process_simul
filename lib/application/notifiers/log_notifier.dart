import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  String get levelLabel => switch (level) {
        LogLevel.debug => 'DBG',
        LogLevel.info => 'INF',
        LogLevel.warning => 'WRN',
        LogLevel.error => 'ERR',
      };

  String get timeStr {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }
}

/// Global in-memory log buffer (max 2000 entries).
class LogNotifier extends StateNotifier<List<LogEntry>> {
  static const _maxEntries = 2000;

  LogNotifier() : super(_ChunkedLogList.empty());

  void _add(LogLevel level, String source, String message) {
    final entry = LogEntry(
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: message);
    final current = state;
    state = current is _ChunkedLogList
        ? current.append(entry, maxLength: _maxEntries)
        : _ChunkedLogList.from(current).append(entry, maxLength: _maxEntries);
  }

  void debug(String src, String msg) => _add(LogLevel.debug, src, msg);
  void info(String src, String msg) => _add(LogLevel.info, src, msg);
  void warning(String src, String msg) => _add(LogLevel.warning, src, msg);
  void error(String src, String msg) => _add(LogLevel.error, src, msg);

  void clear() => state = _ChunkedLogList.empty();
}

/// Immutable, structurally-shared list used by the high-frequency log path.
///
/// Appending copies one small chunk plus the chunk index instead of copying as
/// many as 2,000 entries for every protocol frame. Advancing past [maxLength]
/// moves the logical start of the list and releases fully-consumed chunks.
class _ChunkedLogList extends ListBase<LogEntry> {
  static const int _chunkSize = 64;

  final Map<int, List<LogEntry>> _chunks;
  final int _start;
  final int _length;

  _ChunkedLogList._(this._chunks, this._start, this._length);

  factory _ChunkedLogList.empty() => _ChunkedLogList._(const {}, 0, 0);

  factory _ChunkedLogList.from(Iterable<LogEntry> entries) {
    var result = _ChunkedLogList.empty();
    for (final entry in entries) {
      result = result.append(entry, maxLength: 0x7FFFFFFF);
    }
    return result;
  }

  _ChunkedLogList append(LogEntry entry, {required int maxLength}) {
    final absoluteEnd = _start + _length;
    final chunkId = absoluteEnd ~/ _chunkSize;
    final chunks = Map<int, List<LogEntry>>.of(_chunks);
    final tail = List<LogEntry>.of(chunks[chunkId] ?? const [])..add(entry);
    chunks[chunkId] = List<LogEntry>.unmodifiable(tail);

    var nextStart = _start;
    var nextLength = _length + 1;
    if (nextLength > maxLength) {
      nextStart++;
      nextLength = maxLength;
      if (nextStart % _chunkSize == 0) {
        chunks.remove((nextStart ~/ _chunkSize) - 1);
      }
    }
    return _ChunkedLogList._(
      Map<int, List<LogEntry>>.unmodifiable(chunks),
      nextStart,
      nextLength,
    );
  }

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Log list is immutable');

  @override
  LogEntry operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final absoluteIndex = _start + index;
    return _chunks[absoluteIndex ~/ _chunkSize]![absoluteIndex % _chunkSize];
  }

  @override
  void operator []=(int index, LogEntry value) =>
      throw UnsupportedError('Log list is immutable');
}

// Global accessor (used by infrastructure layers without Ref)
LogNotifier? _globalLog;
LogNotifier get globalLog => _globalLog ??= LogNotifier();

void initGlobalLog(LogNotifier log) => _globalLog = log;
