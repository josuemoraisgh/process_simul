import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/application/notifiers/log_notifier.dart';

void main() {
  group('LogNotifier bounded persistent buffer', () {
    test('keeps the newest 2000 entries in insertion order', () {
      final notifier = LogNotifier();
      addTearDown(notifier.dispose);

      for (var i = 0; i < 2105; i++) {
        notifier.debug('perf', 'entry-$i');
      }

      expect(notifier.state, hasLength(2000));
      expect(notifier.state.first.message, 'entry-105');
      expect(notifier.state.last.message, 'entry-2104');
    });

    test('previously published snapshots remain stable and immutable', () {
      final notifier = LogNotifier();
      addTearDown(notifier.dispose);
      notifier.info('perf', 'first');
      final snapshot = notifier.state;

      notifier.info('perf', 'second');

      expect(snapshot.map((entry) => entry.message), ['first']);
      expect(
        () => snapshot.add(LogEntry(
          timestamp: DateTime(2020),
          level: LogLevel.info,
          source: 'test',
          message: 'mutation',
        )),
        throwsUnsupportedError,
      );
    });

    test('clear resets the bounded buffer', () {
      final notifier = LogNotifier();
      addTearDown(notifier.dispose);
      notifier.warning('perf', 'before-clear');

      notifier.clear();
      notifier.error('perf', 'after-clear');

      expect(notifier.state.map((entry) => entry.message), ['after-clear']);
    });
  });
}
