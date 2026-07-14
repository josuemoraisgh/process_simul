import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/infrastructure/hart/hart_frame.dart';
import 'package:process_simul/infrastructure/modbus/modbus_server.dart';

Future<List<int>> _readModbusFrame(Socket socket) async {
  final bytes = <int>[];
  final completer = Completer<List<int>>();
  late StreamSubscription<Uint8List> subscription;
  subscription = socket.listen((chunk) {
    bytes.addAll(chunk);
    if (bytes.length >= 6) {
      final total = 6 + ((bytes[4] << 8) | bytes[5]);
      if (bytes.length >= total && !completer.isCompleted) {
        subscription.cancel();
        completer.complete(bytes.sublist(0, total));
      }
    }
  });
  return completer.future.timeout(const Duration(seconds: 5));
}

List<int> _request(int function, List<int> data, {int protocol = 0}) {
  final length = 2 + data.length;
  return [
    0,
    1,
    (protocol >> 8) & 0xff,
    protocol & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
    1,
    function,
    ...data,
  ];
}

void main() {
  group('HART frame security', () {
    test('rejects a frame with a modified checksum', () {
      final valid = HartFrame(
        delimiter: HartFrame.kDelimShort,
        command: 6,
        address: 1,
        body: const [2],
      ).build();
      final tampered = Uint8List.fromList(valid)..[valid.length - 1] ^= 0xff;

      expect(HartFrame.parse(valid), isNotNull);
      expect(HartFrame.parse(tampered), isNull);
    });

    test('rejects trailing bytes not covered by the declared byte count', () {
      final valid = HartFrame(
        delimiter: HartFrame.kDelimShort,
        command: 1,
        address: 1,
      ).build();
      final withTrailingByte = Uint8List.fromList([...valid, 0]);

      expect(HartFrame.parse(withTrailingByte), isNull);
    });
  });

  group('Modbus TCP security', () {
    late ModbusTcpServer server;
    late Map<int, int> registers;
    late Map<int, bool> coils;

    setUp(() async {
      registers = {};
      coils = {};
      server = ModbusTcpServer(
        port: 0,
        getRegister: (address, _) => registers[address] ?? 0,
        setRegister: (address, value) => registers[address] = value,
        getCoil: (address, _) => coils[address] ?? false,
        setCoil: (address, value) => coils[address] = value,
      );
      await server.start();
    });

    tearDown(() => server.stop());

    test('rejects an excessive read quantity without invoking getters',
        () async {
      var getterCalls = 0;
      await server.stop();
      server = ModbusTcpServer(
        port: 0,
        getRegister: (_, __) {
          getterCalls++;
          return 0;
        },
        setRegister: (_, __) {},
        getCoil: (_, __) => false,
        setCoil: (_, __) {},
      );
      await server.start();

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.boundPort,
      );
      socket.add(_request(3, [0, 0, 0xff, 0xff]));
      final response = await _readModbusFrame(socket);
      socket.destroy();

      expect(response.sublist(7), [0x83, 0x03]);
      expect(getterCalls, 0);
    });

    test('invalid FC05 value does not mutate a coil', () async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.boundPort,
      );
      socket.add(_request(5, [0, 3, 0x12, 0x34]));
      final response = await _readModbusFrame(socket);
      socket.destroy();

      expect(response.sublist(7), [0x85, 0x03]);
      expect(coils, isEmpty);
    });

    test('inconsistent FC10 byte count causes no partial writes', () async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.boundPort,
      );
      socket.add(_request(0x10, [0, 0, 0, 2, 2, 0x12, 0x34]));
      final response = await _readModbusFrame(socket);
      socket.destroy();

      expect(response.sublist(7), [0x90, 0x03]);
      expect(registers, isEmpty);
    });
  });
}
