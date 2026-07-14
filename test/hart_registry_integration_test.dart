import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/domain/hart/hart_command_registry.dart';
import 'package:process_simul/infrastructure/hart/hart_comm.dart';
import 'package:process_simul/infrastructure/hart/hart_frame.dart';
import 'package:process_simul/infrastructure/hart/hart_transmitter.dart';

ReactVar _cell(String name, String value) => ReactVar(
      tableName: 'HART',
      rowName: 'DEVICE',
      colName: name,
      byteSize: 1,
      typeStr: 'UNSIGNED',
      rawValue: value,
    );

void main() {
  test('TCP transport dispatches through the injected command registry',
      () async {
    final transmitter = HartTransmitter(
      commands: HartTransmitter.standardCommandRegistry(),
      functions: HartFunctionRegistry(),
    )..registerCommand(FunctionalHartCommandHandler(
        0x7E,
        (context) => [0, 0, ...context.requestBody],
      ));
    final server = HartCommServer(
      port: 0,
      transmitter: transmitter,
      getTable: () => {
        'DEVICE': {
          'polling_address': _cell('polling_address', '01'),
        },
      },
      writeCell: (_, __, ___) {},
    );

    await server.start();
    Socket? socket;
    try {
      socket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      socket.add(HartFrame(
        delimiter: HartFrame.kDelimShort,
        address: 1,
        command: 0x7E,
        body: const [0x2A],
      ).build());
      await socket.flush();

      final bytes = await socket.first.timeout(const Duration(seconds: 2));
      final response = HartFrame.parse(Uint8List.fromList(bytes));
      expect(response, isNotNull);
      expect(response!.command, 0x7E);
      expect(response.body, [0, 0, 0x2A]);
    } finally {
      socket?.destroy();
      await server.stop();
    }
  });
}
