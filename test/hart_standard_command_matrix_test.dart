import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/data/templates/db_template.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/infrastructure/hart/hart_transmitter.dart';

const _standardCommands = <int>{
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0x0C,
  0x0D,
  0x0E,
  0x0F,
  0x10,
  0x11,
  0x12,
  0x13,
  0x21,
  0x26,
  0x28,
  0x29,
  0x2A,
  0x2B,
  0x2D,
  0x2E,
  0x48,
  0x50,
  0x80,
  0x82,
  0x84,
  0x85,
  0x87,
  0x88,
  0x8A,
  0x8C,
  0x8E,
  0x98,
  0x9C,
  0xA0,
  0xA2,
  0xA4,
  0xA6,
  0xA8,
  0xAD,
  0xB0,
  0xB1,
  0xB2,
  0xB3,
  0xB4,
  0xB9,
  0xBA,
  0xBB,
  0xBD,
  0xC6,
  0xCC,
  0xDF,
};

Map<String, ReactVar> _completeDevice() => {
      for (final entry in kHartTemplate.entries)
        entry.key: ReactVar(
          tableName: 'HART',
          rowName: 'FIXTURE',
          colName: entry.key,
          byteSize: entry.value.$1,
          typeStr: entry.value.$2,
          rawValue: RegExp(r'^[0-9A-Fa-f]+$').hasMatch(entry.value.$3.first)
              ? entry.value.$3.first
              : '0'.padLeft(entry.value.$1 * 2, '0'),
        ),
    };

List<int> _bodyFor(int command) => switch (command) {
      0x06 => const [0x0A, 0x01],
      0x0B => const [0, 1, 2, 3, 4, 5],
      0x11 => const [1, 2, 3, 4],
      0x12 => List<int>.generate(21, (i) => i),
      0x13 => const [1, 2, 3],
      0x21 => const [3, 0, 4, 7],
      0x85 || 0xA0 => const [1],
      _ => const [1, 2],
    };

void main() {
  group('standard HART command matrix', () {
    test('every advertised standard command dispatches without throwing', () {
      final transmitter = HartTransmitter.standard();
      final device = _completeDevice();

      for (final command in _standardCommands) {
        final writes = <(String, String)>[];
        final response = transmitter.dispatch(
          command: command,
          requestBody: _bodyFor(command),
          device: device,
          onWrite: (field, rawHex) => writes.add((field, rawHex)),
        );

        expect(response, isA<List<int>>(),
            reason: 'command 0x${command.toRadixString(16)}');
        expect(response.every((byte) => byte >= 0 && byte <= 0xFF), isTrue,
            reason:
                'command 0x${command.toRadixString(16)} returned non-byte data');
        expect(() => response.add(0), throwsUnsupportedError,
            reason: 'registry responses are immutable');
        for (final write in writes) {
          expect(write.$1, isNotEmpty);
          expect(write.$2, matches(RegExp(r'^[0-9A-F]*$')));
        }
      }
    });

    test('read-only commands do not invoke the write port', () {
      const writing = {0x06, 0x11, 0x12, 0x13, 0x26};
      final transmitter = HartTransmitter.standard();
      for (final command in _standardCommands.difference(writing)) {
        var writes = 0;
        transmitter.dispatch(
          command: command,
          requestBody: _bodyFor(command),
          device: _completeDevice(),
          onWrite: (_, __) => writes++,
        );
        expect(writes, 0, reason: 'command 0x${command.toRadixString(16)}');
      }
    });

    test('short write payloads are atomic while message accepts its full body',
        () {
      final transmitter = HartTransmitter.standard();
      for (final command in const [0x06, 0x12, 0x13]) {
        final writes = <(String, String)>[];
        transmitter.dispatch(
          command: command,
          requestBody: const [],
          device: _completeDevice(),
          onWrite: (field, value) => writes.add((field, value)),
        );
        expect(writes, isEmpty,
            reason: 'command 0x${command.toRadixString(16)}');
      }

      final messageWrites = <(String, String)>[];
      transmitter.dispatch(
        command: 0x11,
        requestBody: const [0xAB, 0xCD],
        device: _completeDevice(),
        onWrite: (field, value) => messageWrites.add((field, value)),
      );
      expect(messageWrites, [('message', 'ABCD')]);
    });

    test('command 21 covers default, single and counted variable requests', () {
      final transmitter = HartTransmitter.standard();
      for (final body in const <List<int>>[
        [],
        [0],
        [4],
        [9],
        [3, 0, 4, 9]
      ]) {
        final response = transmitter.dispatch(
          command: 0x21,
          requestBody: body,
          device: _completeDevice(),
          onWrite: (_, __) {},
        );
        expect(response, isNotEmpty);
      }
    });

    test('paged vendor commands accept every mapped page and a fallback page',
        () {
      final transmitter = HartTransmitter.standard();
      for (final page in const [0x00, 0x08, 0x10, 0x18, 0x1C, 0xFF]) {
        expect(
          transmitter.dispatch(
            command: 0x85,
            requestBody: [page],
            device: _completeDevice(),
            onWrite: (_, __) {},
          ),
          isNotEmpty,
        );
      }
      for (final page in const [0, 1, 2, 3, 4, 0xFF]) {
        expect(
          transmitter.dispatch(
            command: 0xA0,
            requestBody: [page],
            device: _completeDevice(),
            onWrite: (_, __) {},
          ),
          isNotEmpty,
        );
      }
    });

    test('missing optional cells degrade to bounded responses, not exceptions',
        () {
      final transmitter = HartTransmitter.standard();
      for (final command in _standardCommands) {
        final response = transmitter.dispatch(
          command: command,
          requestBody: _bodyFor(command),
          device: const {},
          onWrite: (_, __) {},
        );
        expect(response.length, lessThan(256));
      }
    });
  });
}
