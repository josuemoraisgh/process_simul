import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/domain/hart/hart_command_registry.dart';
import 'package:process_simul/domain/hart/hart_payload_parser.dart';
import 'package:process_simul/infrastructure/hart/hart_comm.dart';
import 'package:process_simul/infrastructure/hart/hart_frame.dart';
import 'package:process_simul/infrastructure/hart/hart_transmitter.dart';
import 'package:process_simul/infrastructure/hart/hart_type_converter.dart';
import 'package:process_simul/infrastructure/modbus/modbus_server.dart';
import 'package:process_simul/infrastructure/modbus/modbus_value_parser.dart';
import 'package:process_simul/infrastructure/network/socket_error_guard.dart';
import 'package:process_simul/infrastructure/simulation/simul_tf.dart';

ReactVar _cell(String name, String value,
        {int size = 1, String type = 'UNSIGNED'}) =>
    ReactVar(
      tableName: 'HART',
      rowName: 'DEVICE',
      colName: name,
      byteSize: size,
      typeStr: type,
      rawValue: value,
    );

final class _EchoFunction implements HartFunction {
  @override
  String get name => 'echo';

  @override
  Object? interpret(HartCommandContext context, HartPayloadReader payload) =>
      payload.readUint8();
}

Future<List<int>> _readFrame(Socket socket) async {
  final bytes = <int>[];
  final done = Completer<List<int>>();
  late StreamSubscription<Uint8List> subscription;
  subscription = socket.listen((chunk) {
    bytes.addAll(chunk);
    if (bytes.length >= 6) {
      final preamble = bytes.takeWhile((b) => b == 0xFF).length;
      if (preamble >= 2 && bytes.length > preamble) {
        final long = (bytes[preamble] & 0x80) != 0;
        final countAt = preamble + 1 + (long ? 5 : 1) + 1;
        if (bytes.length > countAt) {
          final total = countAt + 1 + bytes[countAt] + 1;
          if (bytes.length >= total && !done.isCompleted) {
            subscription.cancel();
            done.complete(bytes.sublist(0, total));
          }
        }
      }
    }
  });
  return done.future.timeout(const Duration(seconds: 2));
}

List<int> _mbap(int transaction, int unit, List<int> pdu) => [
      transaction >> 8,
      transaction & 0xFF,
      0,
      0,
      0,
      pdu.length + 1,
      unit,
      ...pdu,
    ];

Future<List<int>> _readModbus(Socket socket) async {
  final bytes = <int>[];
  final done = Completer<List<int>>();
  late StreamSubscription<Uint8List> subscription;
  subscription = socket.listen((chunk) {
    bytes.addAll(chunk);
    if (bytes.length >= 6) {
      final total = 6 + (bytes[4] << 8 | bytes[5]);
      if (bytes.length >= total && !done.isCompleted) {
        subscription.cancel();
        done.complete(bytes.sublist(0, total));
      }
    }
  });
  return done.future.timeout(const Duration(seconds: 2));
}

void main() {
  test('socket cleanup errors are contained by the lifecycle guard', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clientFuture = Socket.connect(server.address, server.port);
    final acceptedFuture = server.first;
    final client = await clientFuture;
    final accepted = await acceptedFuture;
    final clients = <Socket>[accepted];
    try {
      expect(
        () => SocketErrorGuard(
          channel: 'TEST',
          address: 'local',
          socket: accepted,
          clients: clients,
          destroy: () => throw StateError('forced cleanup failure'),
        ).call(StateError('forced socket failure')),
        returnsNormally,
      );
      expect(clients, isEmpty);
    } finally {
      client.destroy();
      accepted.destroy();
      await server.close();
    }
  });

  group('HartTypeConverter exhaustive public paths', () {
    test('covers numeric, float, date, time, bool and defensive conversions',
        () {
      expect(HartTypeConverter.humanToHex('1.5', 'FLOAT', 4), '3FC00000');
      expect(HartTypeConverter.hexToHuman('00000001', 'FLOAT'), '1.40e-45');
      expect(HartTypeConverter.hexToHuman('7F800000', 'FLOAT'), '0.0000');
      expect(HartTypeConverter.humanToHex('-2', 'UNSIGNED', 2), '0000');
      expect(HartTypeConverter.hexToHuman('', 'UNSIGNED'), '0');
      expect(HartTypeConverter.humanToHex('-2', 'INTEGER', 2), 'FFFE');
      expect(HartTypeConverter.hexToHuman('FFFE', 'INTEGER'), '-2');
      expect(HartTypeConverter.humanToHex('14/07/2026', 'DATE', 3), '0E077E');
      expect(HartTypeConverter.hexToHuman('0E077E', 'DATE'), '14/07/2026');
      expect(HartTypeConverter.hexToHuman('01', 'DATE'), '');
      expect(HartTypeConverter.humanToHex('invalid', 'DATE', 3), '000000');
      expect(HartTypeConverter.hexToHuman('00000000', 'TIME'), '00:00:00');
      expect(HartTypeConverter.hexToHuman('00', 'TIME'), '00:00:00');
      expect(HartTypeConverter.humanToHex('01', 'BOOL', 1), '01');
      expect(HartTypeConverter.hexToHuman('01', 'BOOL'), '01');
      expect(HartTypeConverter.humanToHex('bad', 'FLOAT', 4), 'bad');
      expect(HartTypeConverter.hexToHuman('bad!', 'FLOAT'), 'bad!');
    });

    test('covers enum and bit-enum lookup, ranges and fallbacks', () {
      const enums = {
        '00': 'Zero',
        'F0-F9': 'Reserved',
        'broken-range-x': 'Bad'
      };
      expect(
          HartTypeConverter.hexToHuman('00', 'ENUM00', enumMap: enums), 'Zero');
      expect(HartTypeConverter.hexToHuman('F5', 'ENUM00', enumMap: enums),
          'Reserved');
      expect(
          HartTypeConverter.hexToHuman('AA', 'ENUM00', enumMap: enums), 'AA');
      expect(HartTypeConverter.humanToHex('Zero', 'ENUM00', 1, enumMap: enums),
          '00');
      expect(
          HartTypeConverter.humanToHex('Reserved', 'ENUM00', 1, enumMap: enums),
          'F0');
      expect(HartTypeConverter.humanToHex('0A', 'ENUM00', 1, enumMap: enums),
          '0A');
      expect(HartTypeConverter.humanToHex('Other', 'ENUM00', 1, enumMap: enums),
          'Other');
      expect(HartTypeConverter.hexToHuman('01', 'ENUM00'), '01');
      const bits = {0: 'None', 1: 'Alarm', 2: 'Warning'};
      expect(HartTypeConverter.hexToHuman('00', 'BIT_ENUM02', bitEnumMap: bits),
          'None');
      expect(HartTypeConverter.hexToHuman('03', 'BIT_ENUM02', bitEnumMap: bits),
          'Alarm | Warning');
      expect(HartTypeConverter.hexToHuman('08', 'BIT_ENUM02', bitEnumMap: bits),
          '08');
      expect(
          HartTypeConverter.humanToHex('Alarm | Warning', 'BIT_ENUM02', 1,
              bitEnumMap: bits),
          '03');
      expect(
          HartTypeConverter.humanToHex('0A', 'BIT_ENUM02', 1, bitEnumMap: bits),
          '0A');
      expect(HartTypeConverter.hexToHuman('01', 'BIT_ENUM02'), '01');
      expect(HartTypeConverter.isEnumType('bit_enum02'), isTrue);
      expect(HartTypeConverter.isEnumType('FLOAT'), isFalse);
    });

    test('covers packed ASCII and public helper parsing', () {
      expect(
          HartTypeConverter.humanToHex('AB', 'PACKED ASCII', 2), hasLength(4));
      expect(HartTypeConverter.hexToHuman('', 'PACKED ASCII'), '');
      expect(HartTypeConverter.humanToHex('A', 'PACKED ASCII', 0), '');
      expect(
          HartTypeConverter.humanToHex('~', 'PACKED ASCII', 1), hasLength(2));
      expect(HartTypeConverter.parseEnumIndex('ENUM27'), 27);
      expect(HartTypeConverter.parseEnumIndex('FLOAT'), -1);
      expect(HartTypeConverter.parseBitEnumIndex('BIT_ENUM02'), 2);
      expect(HartTypeConverter.parseBitEnumIndex('ENUM02'), -1);
      expect(HartTypeConverter.hexToDouble('not-hex'), 0);
      expect(HartTypeConverter.hexToDouble('7F800000'), 0);
    });
  });

  group('HART frame/server edge paths', () {
    test('transmitter function facade registers and removes extensions', () {
      final transmitter = HartTransmitter.standard();
      final function = _EchoFunction();
      transmitter.registerFunction(function);
      expect(transmitter.removeFunction('echo'), same(function));
    });

    test('decoder clears noise, a one-byte preamble and an oversized buffer',
        () {
      final decoder = HartFrameDecoder();
      expect(decoder.add([1, 2, 3]), isEmpty);
      expect(decoder.add([0xFF, 0x02]), isEmpty);
      decoder.clear();
      expect(decoder.add(List.filled(HartFrame.maxFrameLength + 1, 0xFF)),
          isEmpty);
      expect(decoder.overflowed, isTrue);
    });

    test('legacy feed queue and clear expose all coalesced frames', () {
      HartFrame.clearBuffer();
      final a = HartFrame(delimiter: 2, address: 1, command: 1).build();
      final b = HartFrame(delimiter: 2, address: 1, command: 2).build();
      expect(HartFrame.feedBytes([...a, ...b])?.command, 1);
      expect(HartFrame.feedBytes(const [])?.command, 2);
      HartFrame.clearBuffer();
      expect(HartFrame.feedBytes(const []), isNull);
    });

    test('validates server configuration and idempotent lifecycle', () async {
      HartCommServer make(int port, int clients) => HartCommServer(
            port: port,
            maxClients: clients,
            getTable: () => {},
            writeCell: (_, __, ___) {},
          );
      await expectLater(make(-1, 1).start(), throwsArgumentError);
      await expectLater(make(0, 0).start(), throwsArgumentError);
      final server = make(0, 1);
      await server.start();
      await server.start();
      expect(server.isRunning, isTrue);
      await server.stop();
      await server.stop();
    });

    test('routes long address and builds response from device identity',
        () async {
      final device = {
        'manufacturer_id': _cell('manufacturer_id', '0A'),
        'device_type': _cell('device_type', '0B'),
        'device_id': _cell('device_id', '010203'),
        'polling_address': _cell('polling_address', '01'),
      };
      final commands = HartCommandRegistry()
        ..register(FunctionalHartCommandHandler(0x70, (_) => [0, 0]));
      final server = HartCommServer(
        port: 0,
        transmitter: HartTransmitter(
            commands: commands, functions: HartFunctionRegistry()),
        getTable: () => {'DEVICE': device},
        writeCell: (_, __, ___) {},
      );
      await server.start();
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      try {
        socket.add(HartFrame(
          delimiter: HartFrame.kDelimLong,
          longAddress: const [0xCA, 0x0B, 1, 2, 3],
          command: 0x70,
        ).build());
        final response =
            HartFrame.parse(Uint8List.fromList(await _readFrame(socket)));
        expect(response?.longAddress, [0xCA, 0x0B, 1, 2, 3]);
      } finally {
        socket.destroy();
        await server.stop();
      }
    });

    test('drops unknown addresses and enforces client/buffer limits', () async {
      final server = HartCommServer(
        port: 0,
        maxClients: 1,
        getTable: () => {},
        writeCell: (_, __, ___) {},
      );
      await server.start();
      final first =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final second =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      final secondClosed = Completer<void>();
      second.listen((_) {}, onDone: secondClosed.complete);
      try {
        await secondClosed.future.timeout(const Duration(seconds: 2));
        first.add(HartFrame(
          delimiter: HartFrame.kDelimShort,
          address: 63,
          command: 0,
        ).build());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final firstClosed = Completer<void>();
        first.listen((_) {}, onDone: firstClosed.complete);
        first.add(List.filled(HartFrame.maxFrameLength + 1, 0xFF));
        await firstClosed.future.timeout(const Duration(seconds: 2));
      } finally {
        first.destroy();
        second.destroy();
        await server.stop();
      }
    });

    test('write handler and short device id padding are transport-visible',
        () async {
      var write = '';
      final commands = HartCommandRegistry()
        ..register(FunctionalHartCommandHandler(0x71, (context) {
          context.onWrite('value', '2A');
          context.device['device_id']!.setRawValue('01');
          return [0, 0];
        }));
      final server = HartCommServer(
        port: 0,
        transmitter: HartTransmitter(
          commands: commands,
          functions: HartFunctionRegistry(),
        ),
        getTable: () => {
          'DEVICE': {
            'manufacturer_id': _cell('manufacturer_id', '0A'),
            'device_type': _cell('device_type', '0B'),
            'device_id': _cell('device_id', '010000'),
          },
        },
        writeCell: (_, column, value) => write = '$column=$value',
      );
      await server.start();
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      try {
        socket.add(HartFrame(
          delimiter: HartFrame.kDelimLong,
          longAddress: const [0x0A, 0x0B, 1, 0, 0],
          command: 0x71,
        ).build());
        final response =
            HartFrame.parse(Uint8List.fromList(await _readFrame(socket)));
        expect(response?.longAddress, [0x0A, 0x0B, 1, 0, 0]);
        expect(write, 'value=2A');
      } finally {
        socket.destroy();
        await server.stop();
      }
    });
  });

  group('Modbus server defensive paths', () {
    ModbusTcpServer make(
            {int port = 0, int clients = 32, ModbusRegGetter? getter}) =>
        ModbusTcpServer(
          port: port,
          maxClients: clients,
          getRegister: getter ?? (_, __) => 0,
          setRegister: (_, __) {},
          getCoil: (_, __) => false,
          setCoil: (_, __) {},
        );

    test('validates configuration and start/stop are idempotent', () async {
      await expectLater(make(port: -1).start(), throwsArgumentError);
      await expectLater(make(clients: 0).start(), throwsArgumentError);
      final server = make();
      await server.start();
      await server.start();
      await server.stop();
      await server.stop();
    });

    test('converts unexpected callback failure to exception 04', () async {
      final server = make(getter: (_, __) => throw StateError('device failed'));
      await server.start();
      final socket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      try {
        socket.add(_mbap(1, 1, [3, 0, 0, 0, 1]));
        expect((await _readModbus(socket)).sublist(7), [0x83, 0x04]);
      } finally {
        socket.destroy();
        await server.stop();
      }
    });

    test('rejects excess client and closes oversized receive buffer', () async {
      final server = make(clients: 1);
      await server.start();
      final first =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final second =
          await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort);
      final secondClosed = Completer<void>();
      second.listen((_) {}, onDone: secondClosed.complete);
      try {
        await secondClosed.future.timeout(const Duration(seconds: 2));
        final firstClosed = Completer<void>();
        first.listen((_) {}, onDone: firstClosed.complete);
        first.add(List.filled(4097, 1));
        await firstClosed.future.timeout(const Duration(seconds: 2));
      } finally {
        first.destroy();
        second.destroy();
        await server.stop();
      }
    });
  });

  test('Modbus literal parser decimal fallback and invalid fallback', () {
    expect(ModbusValueParser.parseLiteral('1.5'), 1.5);
    expect(ModbusValueParser.parseLiteral('invalid'), 0);
  });

  test('shared socket error guard removes and closes a failed client',
      () async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = listener.first;
    final peer = await Socket.connect(listener.address, listener.port);
    final socket = await accepted;
    final clients = <Socket>[socket];
    SocketErrorGuard(
      channel: 'test',
      address: 'loopback',
      socket: socket,
      clients: clients,
    )(StateError('forced'));
    expect(clients, isEmpty);
    peer.destroy();
    await listener.close();
  });

  test('simulation covers both input normalization paths and no-change tick',
      () async {
    final sim = SimulTf(stepMs: 5);
    var changes = 0;
    sim.onChanged = () => changes++;
    for (final entry in [
      (name: 'large', input: 65535.0),
      (name: 'percent', input: 50.0)
    ]) {
      sim.register(
        ReactVar(
          tableName: 'HART',
          rowName: 'DEV',
          colName: entry.name,
          byteSize: 4,
          typeStr: 'FLOAT',
          rawValue: r'$[1],[1],0,x',
        ),
        () => entry.input,
      );
    }
    sim.start();
    sim.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    sim.reset();
    sim.stop();
    expect(changes, greaterThan(0));
  });
}
