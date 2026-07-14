// Protocol-level specs for [ModbusTcpServer].
//
// These exercise the server over a real TCP loopback connection to catch
// wire-format regressions (e.g. a missing function code byte) that a purely
// in-memory unit test of the PDU builders would not surface.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/infrastructure/modbus/modbus_server.dart';

/// Reads exactly one full Modbus TCP frame (MBAP header + PDU) from [socket],
/// buffering across multiple TCP chunks if necessary.
Future<List<int>> _readOneFrame(Socket socket) async {
  final buf = <int>[];
  final completer = Completer<List<int>>();
  late StreamSubscription sub;
  sub = socket.listen((data) {
    buf.addAll(data);
    if (buf.length >= 6) {
      final pduLen = (buf[4] << 8) | buf[5];
      final total = 6 + pduLen;
      if (buf.length >= total) {
        sub.cancel();
        completer.complete(buf.sublist(0, total));
      }
    }
  });
  return completer.future.timeout(const Duration(seconds: 5));
}

List<int> _mbapRequest({
  required int transId,
  required int unitId,
  required List<int> pdu,
}) {
  final len = pdu.length + 1; // unitId + pdu
  return [
    (transId >> 8) & 0xFF, transId & 0xFF,
    0x00, 0x00,
    (len >> 8) & 0xFF, len & 0xFF,
    unitId,
    ...pdu,
  ];
}

void main() {
  group('ModbusTcpServer', () {
    late ModbusTcpServer server;
    late int port;
    final Map<int, int> hrMap = {};
    final Map<int, int> irMap = {};
    final Map<int, bool> coilMap = {};
    final Map<int, bool> diMap = {};

    setUp(() async {
      hrMap.clear();
      irMap.clear();
      coilMap.clear();
      diMap.clear();
      port = 15500 + (DateTime.now().microsecondsSinceEpoch % 500);
      server = ModbusTcpServer(
        port: port,
        getRegister: (addr, isInput) =>
            (isInput ? irMap[addr] : hrMap[addr]) ?? 0,
        setRegister: (addr, val) => hrMap[addr] = val,
        getCoil: (addr, isInput) =>
            isInput ? (diMap[addr] ?? false) : (coilMap[addr] ?? false),
        setCoil: (addr, val) => coilMap[addr] = val,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    test('Read Holding Registers (0x03) response includes the function code',
        () async {
      irMap[0] = 0;
      hrMap[10] = 0x1234;
      hrMap[11] = 0x5678;

      final socket = await Socket.connect('127.0.0.1', port);
      final request = _mbapRequest(
        transId: 0x0007,
        unitId: 1,
        pdu: [0x03, 0x00, 0x0A, 0x00, 0x02], // read 2 HR from addr 10
      );
      socket.add(request);
      final response = await _readOneFrame(socket);
      socket.destroy();

      // MBAP header echoes the transaction id and unit id.
      expect(response[0], 0x00);
      expect(response[1], 0x07);
      expect(response[6], 1); // unit id

      // This is the regression this suite guards against: the function
      // code byte must be present right after the unit id.
      expect(response[7], 0x03, reason: 'function code must be echoed');
      expect(response[8], 4); // byte count = 2 regs * 2
      expect(response[9], 0x12);
      expect(response[10], 0x34);
      expect(response[11], 0x56);
      expect(response[12], 0x78);
      expect(response.length, 13);
    });

    test('Write Single Register (0x06) echoes request and updates the map',
        () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final request = _mbapRequest(
        transId: 0x0001,
        unitId: 1,
        pdu: [0x06, 0x00, 0x05, 0x00, 0x2A], // write reg 5 = 42
      );
      socket.add(request);
      final response = await _readOneFrame(socket);
      socket.destroy();

      expect(response[7], 0x06);
      expect(response.sublist(8), [0x00, 0x05, 0x00, 0x2A]);
      expect(hrMap[5], 42);
    });

    test('Write Single Coil (0x05) sets the coil map and echoes the request',
        () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final request = _mbapRequest(
        transId: 0x0002,
        unitId: 1,
        pdu: [0x05, 0x00, 0x03, 0xFF, 0x00], // coil 3 = ON
      );
      socket.add(request);
      final response = await _readOneFrame(socket);
      socket.destroy();

      expect(response[7], 0x05);
      expect(response.sublist(8), [0x00, 0x03, 0xFF, 0x00]);
      expect(coilMap[3], true);
    });

    test('Read Coils (0x01) packs bits into bytes correctly', () async {
      coilMap[0] = true;
      coilMap[1] = false;
      coilMap[2] = true;

      final socket = await Socket.connect('127.0.0.1', port);
      final request = _mbapRequest(
        transId: 0x0003,
        unitId: 1,
        pdu: [0x01, 0x00, 0x00, 0x00, 0x03], // read 3 coils from 0
      );
      socket.add(request);
      final response = await _readOneFrame(socket);
      socket.destroy();

      expect(response[7], 0x01);
      expect(response[8], 1); // byte count
      expect(response[9], 0x05); // bits 0 and 2 set -> 0b101
    });

    test('Unsupported function code returns a well-formed exception PDU',
        () async {
      final socket = await Socket.connect('127.0.0.1', port);
      final request = _mbapRequest(
        transId: 0x0004,
        unitId: 1,
        pdu: [0x99], // illegal function
      );
      socket.add(request);
      final response = await _readOneFrame(socket);
      socket.destroy();

      expect(response[7], 0x99 | 0x80); // function code with error bit set
      expect(response[8], 0x01); // illegal function exception code
      expect(response.length, 9);
    });

    test('malformed frame (declared length < 2) is dropped without crashing '
        'the connection', () async {
      final socket = await Socket.connect('127.0.0.1', port);
      // Length field of 1 is invalid (can't even hold unitId+function code).
      socket.add([0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00]);
      await Future.delayed(const Duration(milliseconds: 100));

      // The server should still be able to serve a subsequent, valid
      // request on a fresh connection.
      final socket2 = await Socket.connect('127.0.0.1', port);
      final request = _mbapRequest(
        transId: 0x0005,
        unitId: 1,
        pdu: [0x03, 0x00, 0x00, 0x00, 0x01],
      );
      socket2.add(request);
      final response = await _readOneFrame(socket2);
      socket.destroy();
      socket2.destroy();

      expect(response[7], 0x03);
      expect(server.isRunning, isTrue);
    });
  });
}
