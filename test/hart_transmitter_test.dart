import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/domain/hart/hart_command_registry.dart';
import 'package:process_simul/domain/hart/hart_payload_parser.dart';
import 'package:process_simul/infrastructure/hart/hart_transmitter.dart';

final class _ReadByteFunction implements HartFunction {
  @override
  String get name => 'readByte';

  @override
  Object interpret(HartCommandContext context, HartPayloadReader payload) =>
      payload.readUint8();
}

ReactVar _cell(String name, String hex,
    {String type = 'UNSIGNED', int size = 1}) {
  return ReactVar(
    tableName: 'HART',
    rowName: 'DEV',
    colName: name,
    byteSize: size,
    typeStr: type,
    rawValue: hex,
  );
}

void main() {
  test('removing a standard command disables legacy fallback until re-added',
      () {
    final transmitter = HartTransmitter.standard();
    final device = <String, ReactVar>{
      'error_code': _cell('error_code', '0000', size: 2),
      'process_variable_unit_code': _cell('process_variable_unit_code', '2A'),
      'PROCESS_VARIABLE': _cell(
        'PROCESS_VARIABLE',
        '3FC00000',
        type: 'FLOAT',
        size: 4,
      ),
    };

    transmitter.removeCommand(0x01);
    expect(
      transmitter.processCommand(
        command: 0x01,
        requestBody: const [],
        device: device,
        onWrite: (_, __) {},
      ),
      [64, 0],
    );

    transmitter.registerCommand(FunctionalHartCommandHandler(
      0x01,
      (_) => const [0, 0, 0xAA],
    ));
    expect(
      transmitter.processCommand(
        command: 0x01,
        requestBody: const [],
        device: device,
        onWrite: (_, __) {},
      ),
      [0, 0, 0xAA],
    );
  });

  group('HartTransmitter.evaluateExpr characterization', () {
    late Map<String, Map<String, ReactVar>> devices;

    setUp(() {
      devices = {
        'DEV': {
          'COUNT': _cell('COUNT', '000A', size: 2),
          'PV': _cell('PV', '3FC00000', type: 'FLOAT', size: 4),
        },
      };
    });

    test('honours arithmetic precedence, parentheses and unary signs', () {
      expect(HartTransmitter.evaluateExpr('2 + 3 * 4', devices), 14);
      expect(HartTransmitter.evaluateExpr('(2 + 3) * 4', devices), 20);
      expect(HartTransmitter.evaluateExpr('-2 + +5', devices), 3);
      expect(HartTransmitter.evaluateExpr('2 ** 3', devices), 8);
    });

    test('resolves unsigned and floating HART references', () {
      expect(HartTransmitter.evaluateExpr('HART.DEV.COUNT + 2', devices), 12);
      expect(HartTransmitter.evaluateExpr('HART.DEV.PV * 2', devices), 3);
    });

    test('uses the latest evaluated value when one exists', () {
      devices['DEV']!['COUNT']!.setEvaluatedHex('0014');
      expect(HartTransmitter.evaluateExpr('HART.DEV.COUNT', devices), 20);
    });

    test('supports current math functions and int conversion', () {
      expect(HartTransmitter.evaluateExpr('sqrt(9) + abs(-2)', devices), 5);
      expect(HartTransmitter.evaluateExpr('pow(2, 4)', devices), 16);
      expect(HartTransmitter.evaluateExpr('int(3.9) + 1', devices), 4);
    });

    test('currently maps missing/malformed inputs and division by zero to zero',
        () {
      expect(HartTransmitter.evaluateExpr('HART.MISSING.PV', devices), 0);
      expect(HartTransmitter.evaluateExpr('not-a-number', devices), 0);
      expect(HartTransmitter.evaluateExpr('10 / 0', devices), 0);
    });
  });

  group('HartTransmitter.process characterization', () {
    late Map<String, ReactVar> device;
    late List<(String, String)> writes;

    setUp(() {
      device = {
        'error_code': _cell('error_code', '0000', size: 2),
        'process_variable_unit_code': _cell('process_variable_unit_code', '2A'),
        'PROCESS_VARIABLE': _cell(
          'PROCESS_VARIABLE',
          '3FC00000',
          type: 'FLOAT',
          size: 4,
        ),
        'polling_address': _cell('polling_address', '00'),
        'loop_current_mode': _cell('loop_current_mode', '01'),
      };
      writes = [];
    });

    List<int> process(int command, [List<int> body = const []]) =>
        HartTransmitter.process(
          command: command,
          requestBody: body,
          device: device,
          onWrite: (col, rawHex) => writes.add((col, rawHex)),
        );

    test('command 01 concatenates status, unit and process value bytes', () {
      expect(process(0x01), [0x00, 0x00, 0x2A, 0x3F, 0xC0, 0x00, 0x00]);
      expect(writes, isEmpty);
    });

    test('unknown command returns the current not-implemented response', () {
      expect(process(0xFE), [64, 0]);
      expect(writes, isEmpty);
    });

    test('command 06 emits normalized writes only for a complete body', () {
      expect(process(0x06, [0x0A, 0x00]), [0, 0, 0, 1]);
      expect(writes, [('polling_address', '0A'), ('loop_current_mode', '00')]);

      writes.clear();
      expect(process(0x06, [0x0A]), [0, 0, 0, 1]);
      expect(writes, isEmpty);
    });

    test('command 11 writes and echoes the complete message body', () {
      expect(process(0x11, [0x12, 0xAB]), [0, 0, 0x12, 0xAB]);
      expect(writes, [('message', '12AB')]);
    });

    test('command 12 does not perform partial writes for a short body', () {
      expect(process(0x12, List<int>.filled(20, 1)), [0, 0]);
      expect(writes, isEmpty);
    });
  });

  test('injected registry extends transmitter without transport or switch', () {
    final functions = HartFunctionRegistry()..register(_ReadByteFunction());
    final transmitter = HartTransmitter(
      commands: HartTransmitter.standardCommandRegistry(),
      functions: functions,
    )..registerCommand(FunctionalHartCommandHandler(
        0x123,
        (context) => [context.interpret<int>('readByte')],
      ));

    expect(
      transmitter.dispatch(
        command: 0x01,
        requestBody: const [],
        device: {'error_code': _cell('error_code', '0000', size: 2)},
        onWrite: (_, __) {},
      ),
      [0, 0],
    );

    expect(
      transmitter.dispatch(
        command: 0x123,
        requestBody: [0x2A],
        device: const {},
        onWrite: (_, __) {},
      ),
      [0x2A],
    );
    transmitter.removeCommand(0x123);
    expect(
      transmitter.dispatch(
        command: 0x123,
        requestBody: const [],
        device: const {},
        onWrite: (_, __) {},
      ),
      [64, 0],
    );
  });
}
