import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/infrastructure/hart/hart_type_converter.dart';

void main() {
  group('HartTypeConverter — SREAL (IEEE-754 float)', () {
    test('doubleToHex/hexToDouble round-trip', () {
      expect(HartTypeConverter.doubleToHex(1.0), '3F800000');
      expect(HartTypeConverter.hexToDouble('3F800000'), 1.0);
      expect(HartTypeConverter.hexToDouble('00000000'), 0.0);
    });

    test('hexToHuman formats FLOAT with 4 decimals', () {
      expect(HartTypeConverter.hexToHuman('3F800000', 'FLOAT'), '1.0000');
    });
  });

  group('HartTypeConverter — UNSIGNED', () {
    test('hex <-> decimal round-trip', () {
      expect(HartTypeConverter.hexToHuman('00FF', 'UNSIGNED'), '255');
      expect(HartTypeConverter.humanToHex('255', 'UNSIGNED', 2), '00FF');
    });
  });

  group('HartTypeConverter — INTEGER (signed 16-bit)', () {
    test('negative values use twos complement', () {
      expect(HartTypeConverter.hexToHuman('FFFF', 'INTEGER'), '-1');
      expect(HartTypeConverter.humanToHex('-1', 'INTEGER', 2), 'FFFF');
    });

    test('positive values are unaffected', () {
      expect(HartTypeConverter.hexToHuman('0010', 'INTEGER'), '16');
      expect(HartTypeConverter.humanToHex('16', 'INTEGER', 2), '0010');
    });
  });

  group('HartTypeConverter — PACKED_ASCII', () {
    test('round-trips a short tag', () {
      final hex = HartTypeConverter.humanToHex('TEST', 'PACKED_ASCII', 4);
      expect(HartTypeConverter.hexToHuman(hex, 'PACKED_ASCII'), 'TEST');
    });
  });

  group('HartTypeConverter — ENUM', () {
    test('exact hex key lookup', () {
      final map = {'01': 'Open', '02': 'Closed'};
      expect(
        HartTypeConverter.hexToHuman('01', 'ENUM00', enumMap: map),
        'Open',
      );
    });

    test('range key lookup (e.g. "F0-F9")', () {
      final map = {'F0-F9': 'Reserved'};
      expect(
        HartTypeConverter.hexToHuman('F5', 'ENUM00', enumMap: map),
        'Reserved',
      );
    });

    test('falls back to raw hex when no match', () {
      final map = {'01': 'Open'};
      expect(
        HartTypeConverter.hexToHuman('FF', 'ENUM00', enumMap: map),
        'FF',
      );
    });
  });

  group('HartTypeConverter — BIT_ENUM', () {
    test('OR-combines every matching bit', () {
      final map = {0x01: 'A', 0x02: 'B', 0x04: 'C'};
      expect(
        HartTypeConverter.hexToHuman('03', 'BIT_ENUM00', bitEnumMap: map),
        'A | B',
      );
    });

    test('zero maps to the explicit zero entry when present', () {
      final map = {0x00: 'Normal', 0x01: 'Fault'};
      expect(
        HartTypeConverter.hexToHuman('00', 'BIT_ENUM00', bitEnumMap: map),
        'Normal',
      );
    });
  });

  group('HartTypeConverter — ENUM/BIT_ENUM index parsing', () {
    test('parseEnumIndex extracts the numeric suffix', () {
      expect(HartTypeConverter.parseEnumIndex('ENUM27'), 27);
      expect(HartTypeConverter.parseEnumIndex('UNSIGNED'), -1);
    });

    test('parseBitEnumIndex extracts the numeric suffix', () {
      expect(HartTypeConverter.parseBitEnumIndex('BIT_ENUM02'), 2);
      expect(HartTypeConverter.parseBitEnumIndex('ENUM02'), -1);
    });
  });
}
