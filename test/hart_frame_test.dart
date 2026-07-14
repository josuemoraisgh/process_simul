import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/infrastructure/hart/hart_frame.dart';

void main() {
  tearDown(HartFrame.clearBuffer);

  group('HartFrame wire characterization', () {
    test('builds and parses a short-address frame with deterministic XOR', () {
      final frame = HartFrame(
        delimiter: HartFrame.kDelimShort,
        address: 3,
        command: 1,
        body: const [0xAA, 0x55],
      );
      final bytes = frame.build(preambleCount: 2);

      expect(bytes, [0xFF, 0xFF, 0x02, 0x03, 0x01, 0x02, 0xAA, 0x55, 0xFD]);
      expect(HartFrame.verifyChecksum(bytes), isTrue);
      final parsed = HartFrame.parse(bytes);
      expect(parsed, isNotNull);
      expect(parsed!.delimiter, HartFrame.kDelimShort);
      expect(parsed.address, 3);
      expect(parsed.command, 1);
      expect(parsed.body, [0xAA, 0x55]);
      expect(parsed.isLongAddress, isFalse);
      expect(parsed.isMasterToSlave, isTrue);
    });

    test('round-trips a five-byte long address', () {
      final built = HartFrame(
        delimiter: HartFrame.kDelimLong,
        longAddress: const [0x11, 0x22, 0x33, 0x44, 0x55],
        command: 0x21,
        body: const [0x04],
      ).build(preambleCount: 4);

      final parsed = HartFrame.parse(built);
      expect(parsed, isNotNull);
      expect(parsed!.isLongAddress, isTrue);
      expect(parsed.longAddress, [0x11, 0x22, 0x33, 0x44, 0x55]);
      expect(parsed.command, 0x21);
      expect(parsed.body, [0x04]);
      expect(HartFrame.verifyChecksum(built), isTrue);
    });

    test('response selects the current short and long response delimiters', () {
      final short = HartFrame.response(
        command: 1,
        longAddress: false,
        address: 7,
        responseBody: const [0, 0],
      );
      final long = HartFrame.response(
        command: 1,
        longAddress: true,
        address: 0,
        longAddr: const [1, 2, 3, 4, 5],
        responseBody: const [0, 0],
      );

      expect(short.delimiter, 0x06);
      expect(short.address, 7);
      expect(long.delimiter, 0x86);
      expect(long.longAddress, [1, 2, 3, 4, 5]);
    });

    test('rejects structurally truncated frames', () {
      expect(HartFrame.parse(Uint8List.fromList([])), isNull);
      expect(HartFrame.parse(Uint8List.fromList([0xFF, 0xFF])), isNull);
      expect(
        HartFrame.parse(Uint8List.fromList([0xFF, 0xFF, 0x02, 0x01, 0x03])),
        isNull,
      );
      expect(
        HartFrame.parse(Uint8List.fromList(
          [0xFF, 0xFF, 0x82, 1, 2, 3, 4, 5, 1, 2, 0xAA],
        )),
        isNull,
      );
    });

    test('checksum helper detects a corrupted payload byte', () {
      final bytes = HartFrame(
        delimiter: HartFrame.kDelimShort,
        command: 3,
      ).build(preambleCount: 2);
      final corrupt = Uint8List.fromList(bytes)..[4] ^= 0x01;

      expect(HartFrame.verifyChecksum(bytes), isTrue);
      expect(HartFrame.verifyChecksum(corrupt), isFalse);
      expect(HartFrame.verifyChecksum(Uint8List(0)), isFalse);
    });

    test('stream accumulator handles fragmentation and leading noise', () {
      final bytes = HartFrame(
        delimiter: HartFrame.kDelimShort,
        address: 2,
        command: 7,
        body: const [9, 8],
      ).build(preambleCount: 2);

      expect(HartFrame.feedBytes([0x00, 0x12, ...bytes.sublist(0, 4)]), isNull);
      final parsed = HartFrame.feedBytes(bytes.sublist(4));
      expect(parsed, isNotNull);
      expect(parsed!.address, 2);
      expect(parsed.command, 7);
      expect(parsed.body, [9, 8]);
    });

    test('stream accumulator retains a following complete frame', () {
      final first = HartFrame(
        delimiter: HartFrame.kDelimShort,
        address: 1,
        command: 1,
      ).build(preambleCount: 2);
      final second = HartFrame(
        delimiter: HartFrame.kDelimShort,
        address: 2,
        command: 2,
      ).build(preambleCount: 2);

      expect(HartFrame.feedBytes([...first, ...second])?.command, 1);
      expect(HartFrame.feedBytes(const [])?.command, 2);
    });
  });
}
