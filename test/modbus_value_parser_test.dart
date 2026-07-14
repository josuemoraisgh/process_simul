import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/infrastructure/modbus/modbus_value_parser.dart';

void main() {
  group('ModbusValueParser.parseLiteral', () {
    test('parses raw hex, matching the app-wide rawValue convention', () {
      // "3F000000" is the IEEE-754 hex encoding for 0.5, used verbatim as a
      // literal default in kModbusTemplate — it must not silently become 0.
      expect(ModbusValueParser.parseLiteral('3F000000'), 0x3F000000.toDouble());
      expect(ModbusValueParser.parseLiteral('0064'), 100.0);
      expect(ModbusValueParser.parseLiteral('00000000'), 0.0);
    });

    test('falls back to decimal when the string is not valid hex', () {
      expect(ModbusValueParser.parseLiteral('12.5'), 12.5);
    });

    test('returns 0 for empty/unparsable input', () {
      expect(ModbusValueParser.parseLiteral(''), 0.0);
      expect(ModbusValueParser.parseLiteral('not-a-number'), 0.0);
    });
  });
}
