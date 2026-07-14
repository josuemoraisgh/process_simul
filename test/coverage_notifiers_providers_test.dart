import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:process_simul/application/equipment/equipment_catalog.dart';
import 'package:process_simul/application/notifiers/connection_notifier.dart';
import 'package:process_simul/application/notifiers/custom_types_notifier.dart';
import 'package:process_simul/application/notifiers/hart_table_notifier.dart';
import 'package:process_simul/application/notifiers/modbus_table_notifier.dart';
import 'package:process_simul/application/providers/app_providers.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/domain/equipment/equipment.dart';
import 'package:process_simul/domain/enums/db_model.dart' show DbModel;
import 'package:process_simul/domain/repositories/i_db_repository.dart';
import 'package:process_simul/infrastructure/simulation/simul_tf.dart';
import 'package:process_simul/infrastructure/hart/hart_comm.dart';
import 'package:process_simul/infrastructure/hart/hart_serial_comm.dart';

ReactVar rv(String table, String row, String col, String raw,
        {int size = 1, String type = 'UNSIGNED'}) =>
    ReactVar(
      tableName: table,
      rowName: row,
      colName: col,
      byteSize: size,
      typeStr: type,
      rawValue: raw,
    );

class ThrowingReactVar extends ReactVar {
  ThrowingReactVar()
      : super(
          tableName: 'HART',
          rowName: 'dev',
          colName: 'throwing',
          byteSize: 1,
          typeStr: 'UNSIGNED',
          rawValue: '@1',
        );

  @override
  String get funcBody => throw StateError('synthetic expression failure');
}

class RejectingSimulTf extends SimulTf {
  @override
  bool register(ReactVar variable, double Function() getInput) => false;
}

class ThrowingStopHartServer extends HartCommServer {
  ThrowingStopHartServer({required super.port, required super.bindAddress})
      : super(getTable: () => {}, writeCell: (_, __, ___) {});

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => throw StateError('tcp stop failure');
}

class SuccessfulThrowingStopSerial extends HartSerialServer {
  SuccessfulThrowingStopSerial(String name)
      : super(portName: name, getTable: () => {}, writeCell: (_, __, ___) {});

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => throw StateError('serial stop failure');
}

class FakeDb implements IDbRepository {
  Map<String, Map<String, ReactVar>> hart = {};
  Map<String, Map<String, ReactVar>> modbus = {};
  Map<int, Map<String, String>> enums = {};
  Map<int, Map<int, String>> bits = {};
  Map<String, Map<String, dynamic>> commands = {};
  bool failGet = false;
  final List<String> calls = [];

  @override
  Future<Map<String, Map<String, ReactVar>>> getTable(String name) async {
    if (failGet) throw StateError('database unavailable');
    return name == 'HART' ? hart : modbus;
  }

  @override
  Future<List<String>> rowKeys(String name) async =>
      (name == 'HART' ? hart : modbus).keys.toList();
  @override
  Future<List<String>> colKeys(String name) async =>
      (name == 'HART' ? hart : modbus).values.firstOrNull?.keys.toList() ?? [];
  @override
  Map<int, Map<String, String>> getAllEnums() => enums;
  @override
  Map<int, Map<int, String>> getAllBitEnums() => bits;
  @override
  Map<String, Map<String, dynamic>> getAllCommands() => commands;

  @override
  Future<void> setRawValue(String t, String r, String c, String v) async {
    calls.add('set:$t:$r:$c:$v');
    (t == 'HART' ? hart : modbus)[r]?[c]?.setRawValue(v);
  }

  @override
  Future<void> addHartColumn(String n, int b, String t, String d) async =>
      calls.add('addHartColumn');
  @override
  Future<void> removeHartColumn(String n) async =>
      calls.add('removeHartColumn');
  @override
  Future<void> renameHartDevice(String a, String b) async =>
      calls.add('renameHartDevice');
  @override
  Future<void> editHartColumn(
          String a, String b, int c, String d, String e) async =>
      calls.add('editHartColumn');
  @override
  Future<void> addModbusVariable(
          String a, int b, String c, String d, String e, String f) async =>
      calls.add('addModbus');
  @override
  Future<void> removeModbusVariable(String n) async =>
      calls.add('removeModbus');
  @override
  Future<void> editModbusVariable(String a, String b, int c, String d, String e,
          String f, String g) async =>
      calls.add('editModbus');

  @override
  void addEnumEntry(int i, String k, String d) {
    calls.add('addEnum');
    enums.putIfAbsent(i, () => {})[k] = d;
  }

  @override
  void updateEnumEntry(int i, String k, String d) {
    calls.add('updateEnum');
    enums[i]?[k] = d;
  }

  @override
  void removeEnumEntry(int i, String k) {
    calls.add('removeEnum');
    enums[i]?.remove(k);
  }

  @override
  void removeEnumGroup(int i) {
    calls.add('removeEnumGroup');
    enums.remove(i);
  }

  @override
  void addBitEnumEntry(int i, int k, String d) {
    calls.add('addBit');
    bits.putIfAbsent(i, () => {})[k] = d;
  }

  @override
  void updateBitEnumEntry(int i, int k, String d) {
    calls.add('updateBit');
    bits[i]?[k] = d;
  }

  @override
  void removeBitEnumEntry(int i, int k) {
    calls.add('removeBit');
    bits[i]?.remove(k);
  }

  @override
  void removeBitEnumGroup(int i) {
    calls.add('removeBitGroup');
    bits.remove(i);
  }

  @override
  void addCommand(
      String c, String d, List<String> q, List<String> r, List<String> w) {
    calls.add('addCommand');
    commands[c] = {'description': d, 'req': q, 'resp': r, 'write': w};
  }

  @override
  void updateCommand(
      String c, String d, List<String> q, List<String> r, List<String> w) {
    calls.add('updateCommand');
    commands[c] = {'description': d};
  }

  @override
  void removeCommand(String c) {
    calls.add('removeCommand');
    commands.remove(c);
  }

  @override
  Future<void> init() async {}
  @override
  Future<ReactVar?> getCell(String t, String r, String c) async =>
      (t == 'HART' ? hart : modbus)[r]?[c];
  @override
  Future<void> addHartDevice(String n) async {}
  @override
  Future<void> removeHartDevice(String n) async {}
  @override
  Map<String, String> getEnum(int i) => enums[i] ?? {};
  @override
  List<int> getEnumIndices() => enums.keys.toList();
  @override
  Map<int, String> getBitEnum(int i) => bits[i] ?? {};
  @override
  List<int> getBitEnumIndices() => bits.keys.toList();
  @override
  Map<String, dynamic>? getCommand(String c) => commands[c];
  @override
  List<String> getCommandKeys() => commands.keys.toList();
  @override
  Future<int> importFromXls(String p) async => 0;
  @override
  Future<void> exportToXls(String p) async {}
}

Future<int> freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

void main() {
  test('state objects copy defaults and expose all display forms', () {
    const cs = ConnectionState();
    final copied = cs.copyWith(
        hartServerRunning: true,
        modbusRunning: true,
        hartError: 'h',
        modbusError: 'm',
        hartPort: 1,
        hartSerialPort: 'x',
        modbusPort: 2);
    expect((
      copied.hartServerRunning,
      copied.modbusRunning,
      copied.hartError,
      copied.modbusError,
      copied.hartPort,
      copied.hartSerialPort,
      copied.modbusPort
    ), (
      true,
      true,
      'h',
      'm',
      1,
      'x',
      2
    ));
    expect(copied.copyWith().hartError, isNull);

    const custom = CustomTypesState();
    expect(custom.copyWith().loading, true);
    expect(
        custom.copyWith(enums: const {
          1: {'01': 'one'}
        }, bitEnums: const {
          2: {1: 'bit'}
        }, commands: const {
          '1': {}
        }, loading: false).loading,
        false);
    const mb = ModbusTableState();
    expect(mb.copyWith().loading, true);
    expect(
        mb.copyWith(
            data: const {'x': (1, 'U', 'ir', '1', '0')},
            loading: false,
            error: 'e').error,
        'e');

    final value = rv('HART', 'd', 'v', '0a');
    final func = rv('HART', 'd', 'f', '@1');
    final en = rv('HART', 'd', 'e', '01', type: 'ENUM1');
    final bit = rv('HART', 'd', 'b', '03', type: 'BIT_ENUM2');
    final state = HartTableState(data: {
      'd': {'v': value, 'f': func, 'e': en, 'b': bit}
    }, enumMaps: const {
      1: {'01': 'One'}
    }, bitEnumMaps: const {
      2: {1: 'A', 2: 'B'}
    });
    expect(state.cellDisplay('missing', 'x'), '');
    expect(state.cellDisplay('d', 'f'), '?');
    expect(state.cellDisplay('d', 'e'), contains('One'));
    expect(state.cellDisplay('d', 'b'), contains('A'));
    expect(state.cellModel('d', 'v'), DbModel.value);
    expect(state.cellModel('x', 'x'), DbModel.value);
    expect(state.copyWith(showHuman: false).cellDisplay('d', 'v'), '0A');
  });

  test('custom types notifier delegates every mutation and reloads', () {
    final db = FakeDb();
    final n = CustomTypesNotifier(db);
    n.load();
    n.addEnumEntry(1, '01', 'one');
    n.updateEnumEntry(1, '01', 'uno');
    n.removeEnumEntry(1, '01');
    n.removeEnumGroup(1);
    n.addBitEnumEntry(2, 1, 'bit');
    n.updateBitEnumEntry(2, 1, 'changed');
    n.removeBitEnumEntry(2, 1);
    n.removeBitEnumGroup(2);
    n.addCommand('1', 'c', const [], const [], const []);
    n.updateCommand('1', 'u', const [], const [], const []);
    n.removeCommand('1');
    expect(n.state.loading, false);
    expect(
        db.calls,
        containsAll([
          'addEnum',
          'updateEnum',
          'removeEnum',
          'removeEnumGroup',
          'addBit',
          'updateBit',
          'removeBit',
          'removeBitGroup',
          'addCommand',
          'updateCommand',
          'removeCommand'
        ]));
    n.dispose();
  });

  test('modbus notifier covers load fallbacks, errors and CRUD', () async {
    final db = FakeDb()
      ..modbus = {
        'complete': {
          'byte_size': rv('MODBUS', 'complete', 'byte_size', '2'),
          'type_str': rv('MODBUS', 'complete', 'type_str', 'SIGNED'),
          'mb_point': rv('MODBUS', 'complete', 'mb_point', 'hr'),
          'address': rv('MODBUS', 'complete', 'address', '7'),
          'formula': rv('MODBUS', 'complete', 'formula', '12'),
        },
        'fallback': {'byte_size': rv('MODBUS', 'fallback', 'byte_size', 'bad')},
      };
    final n = ModbusTableNotifier(db);
    await n.load();
    expect(n.state.data['complete'], (2, 'SIGNED', 'hr', '7', '12'));
    expect(n.state.data['fallback'], (4, 'UNSIGNED', 'ir', '01', ''));
    await n.addVariable('a', 1, 'U', 'ir', '1', '0');
    await n.removeVariable('a');
    await n.editVariable('a', 'b', 1, 'U', 'co', '2', '1');
    expect(db.calls, containsAll(['addModbus', 'removeModbus', 'editModbus']));
    db.failGet = true;
    await n.load();
    expect(n.state.error, contains('database unavailable'));
    n.dispose();
  });

  test('hart notifier covers load, expressions, TF, cell notifiers and CRUD',
      () async {
    final db = FakeDb()
      ..enums = {
        1: {'01': 'one'}
      }
      ..bits = {
        2: {1: 'bit'}
      }
      ..hart = {
        'dev': {
          'tag': rv('HART', 'dev', 'tag', '01'),
          'process_variable': rv('HART', 'dev', 'process_variable', '02'),
          'other': rv('HART', 'dev', 'other', '02'),
          'good': rv('HART', 'dev', 'good', '@1+2', size: 2),
          'float': rv('HART', 'dev', 'float', '@1.5', size: 4, type: 'FLOAT'),
          'bad': rv('HART', 'dev', 'bad', '@1/0'),
          'throwing': ThrowingReactVar(),
          'tf':
              rv('HART', 'dev', 'tf', r'$[1],[1],0,@1', size: 4, type: 'FLOAT'),
          'badTf':
              rv('HART', 'dev', 'badTf', r'$invalid', size: 4, type: 'FLOAT'),
        }
      };
    final simul = SimulTf(stepMs: 5)..start();
    final memory = InMemoryEquipmentRepository();
    final n = HartTableNotifier(db, simul, EquipmentCatalog(memory));
    final before = n.cellNotifier('dev', 'tag');
    await n.load();
    final cell = n.cellNotifier('dev', 'tag');
    expect(n.state.visibleCols.take(3), ['tag', 'process_variable', 'other']);
    expect(n.state.data['dev']!['good']!.hasEvaluated, true);
    expect(n.state.data['dev']!['bad']!.hasEvaluated, true);
    expect(n.state.data['dev']!['throwing']!.evaluatedHex, '7FC00000');
    await n.setCellValue('dev', 'tag', '0a');
    expect(cell.value, isNotEmpty);
    expect(n.state.dataVersion, 1);
    n.toggleDisplay();
    n.setShowHuman(true);
    expect(before, isNot(same(cell)));
    await n.addDevice('new');
    expect(await memory.find(EquipmentId('new')), isNotNull);
    await n.removeDevice('new');
    await n.addColumn('c', 1, 'U', '00');
    await n.removeColumn('c');
    await n.editDevice('dev', 'renamed');
    await n.editColumn('a', 'b', 1, 'U', '00');
    expect(
        db.calls,
        containsAll([
          'addHartColumn',
          'removeHartColumn',
          'renameHartDevice',
          'editHartColumn'
        ]));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    db.failGet = true;
    await n.load();
    expect(n.state.error, contains('database unavailable'));
    n.dispose();

    db.failGet = false;
    final rejecting = HartTableNotifier(db, RejectingSimulTf(),
        EquipmentCatalog(InMemoryEquipmentRepository()));
    await rejecting.load();
    rejecting.dispose();
  });

  test('connection notifier synchronizes points and exercises server lifecycle',
      () async {
    final db = FakeDb()
      ..hart = {
        'dev': {'x': rv('HART', 'dev', 'x', '0002', size: 2)}
      }
      ..modbus = {
        'ir': _mbRow('ir', 'ir', '1', '3'),
        'di': _mbRow('di', 'di', '2', '1'),
        'hr': _mbRow('hr', 'hr', '3', '@dev.x'),
        'co': _mbRow('co', 'co', '4', '1'),
        'zero': _mbRow('zero', 'ir', '0', '4'),
        'badAddress': _mbRow('badAddress', 'ir', 'no', '4'),
        'ignored': _mbRow('ignored', 'xx', '5', '1'),
      };
    final hart = HartTableNotifier(
        db, SimulTf(), EquipmentCatalog(InMemoryEquipmentRepository()));
    final mb = ModbusTableNotifier(db);
    await hart.load();
    final n = ConnectionNotifier(hart, mb);
    await mb.load();
    await hart.setCellValue('dev', 'x', '0003');
    n.syncHrRegister(8, 9);
    n.syncIrRegister(9, 10);

    var port = await freePort();
    await n.startHartServer(port, () => db.hart, (_, __, ___) {});
    expect(n.state.hartServerRunning, true);
    await n.stopHartServer();
    await n.startHartServer(-1, () => db.hart, (_, __, ___) {});
    expect(n.state.hartError, isNotNull);
    await n.startHartSerial(
        '__definitely_missing_serial__', () => db.hart, (_, __, ___) {});
    expect(n.state.hartError, isNotNull);

    port = await freePort();
    await n.startModbus(port);
    expect(n.state.modbusRunning, true);
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final responses = <List<int>>[];
    final sub = socket.listen((d) => responses.add(d));
    socket.add(_modbusRequest(1, 3, 2, 1));
    socket.add(_modbusRequest(2, 4, 0, 1));
    socket.add(_modbusRequest(3, 1, 3, 1));
    socket.add(_modbusRequest(4, 2, 1, 1));
    socket.add(Uint8List.fromList([0, 5, 0, 0, 0, 6, 1, 6, 0, 8, 0, 12]));
    socket.add(Uint8List.fromList([0, 6, 0, 0, 0, 6, 1, 5, 0, 3, 0xFF, 0]));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(responses, isNotEmpty);
    await sub.cancel();
    socket.destroy();
    await n.stopModbus();
    await n.startModbus(-1);
    expect(n.state.modbusError, isNotNull);
    n.dispose();

    final exceptional = ConnectionNotifier(
      hart,
      mb,
      hartServerFactory: (port, address, table, writer, transmitter) =>
          ThrowingStopHartServer(port: port, bindAddress: address),
      hartSerialFactory: (name, table, writer, transmitter) =>
          SuccessfulThrowingStopSerial(name),
    );
    await exceptional.startHartServer(1, () => db.hart, (_, __, ___) {});
    await exceptional.startHartSerial('FAKE', () => db.hart, (_, __, ___) {});
    expect(exceptional.state.hartSerialPort, 'FAKE');
    await exceptional.stopHartServer();
    exceptional.dispose();
    hart.dispose();
    mb.dispose();
  });

  test('all application providers compose and dispose with overrides', () {
    final db = FakeDb();
    final equipment = InMemoryEquipmentRepository();
    final container = ProviderContainer(overrides: [
      dbRepositoryProvider.overrideWithValue(db),
      equipmentRepositoryProvider.overrideWithValue(equipment),
    ]);
    addTearDown(container.dispose);
    expect(container.read(equipmentCatalogProvider), isA<EquipmentCatalog>());
    expect(container.read(hartFunctionRegistryProvider), isNotNull);
    expect(container.read(hartCommandRegistryProvider), isNotNull);
    expect(container.read(hartTransmitterProvider), isNotNull);
    expect(container.read(settingsProvider), isNotNull);
    expect(container.read(simulTfProvider), isA<SimulTf>());
    expect(container.read(tfRunningProvider), false);
    expect(container.read(hartTableProvider), isA<HartTableState>());
    expect(container.read(modbusTableProvider), isA<ModbusTableState>());
    expect(container.read(customTypesProvider), isA<CustomTypesState>());
    expect(container.read(connectionProvider), isA<ConnectionState>());
    expect(container.read(logProvider), isEmpty);

    final infrastructure = ProviderContainer();
    expect(infrastructure.read(sqliteDatasourceProvider), isNotNull);
    expect(infrastructure.read(dbRepositoryProvider), isNotNull);
    expect(infrastructure.read(equipmentRepositoryProvider), isNotNull);
    infrastructure.dispose();
  });
}

Map<String, ReactVar> _mbRow(
        String name, String point, String address, String formula) =>
    {
      'byte_size': rv('MODBUS', name, 'byte_size', '2'),
      'type_str': rv('MODBUS', name, 'type_str', 'UNSIGNED'),
      'mb_point': rv('MODBUS', name, 'mb_point', point),
      'address': rv('MODBUS', name, 'address', address),
      'formula': rv('MODBUS', name, 'formula', formula),
    };

Uint8List _modbusRequest(int tx, int function, int address, int quantity) =>
    Uint8List.fromList([
      tx >> 8,
      tx & 0xff,
      0,
      0,
      0,
      6,
      1,
      function,
      address >> 8,
      address & 0xff,
      quantity >> 8,
      quantity & 0xff,
    ]);
