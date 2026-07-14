import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_simul/application/notifiers/log_notifier.dart';
import 'package:process_simul/application/notifiers/custom_types_notifier.dart';
import 'package:process_simul/application/notifiers/connection_notifier.dart'
    as conn;
import 'package:process_simul/application/notifiers/hart_table_notifier.dart';
import 'package:process_simul/application/notifiers/modbus_table_notifier.dart';
import 'package:process_simul/application/providers/app_providers.dart';
import 'package:process_simul/data/datasources/sqlite_datasource.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/presentation/dialogs/add_column_dialog.dart';
import 'package:process_simul/presentation/dialogs/add_device_dialog.dart';
import 'package:process_simul/presentation/dialogs/custom_type_dialogs.dart';
import 'package:process_simul/presentation/dialogs/edit_cell_dialog.dart';
import 'package:process_simul/presentation/screens/logs/logs_screen.dart';
import 'package:process_simul/presentation/screens/hart_table/hart_table_screen.dart';
import 'package:process_simul/presentation/screens/main_shell.dart';
import 'package:process_simul/presentation/screens/modbus_table/modbus_table_screen.dart';
import 'package:process_simul/presentation/screens/settings/settings_screen.dart';
import 'package:process_simul/presentation/screens/tank_3d/tank_3d_screen.dart'
    show isFullscreenNotifier;
import 'package:process_simul/presentation/widgets/comm_bar_widget.dart';

Widget _host(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        key: UniqueKey(),
        home: Scaffold(body: SizedBox(width: 1200, height: 800, child: child)),
      ),
    );

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pump(const Duration(milliseconds: 500));
}

class _ReadyHartNotifier extends HartTableNotifier {
  _ReadyHartNotifier(super.repo, super.simulation, super.equipmentCatalog) {
    ReactVar cell(String device, String column, String raw,
            {String type = 'FLOAT', int bytes = 4}) =>
        ReactVar(
            tableName: 'HART',
            rowName: device,
            colName: column,
            byteSize: bytes,
            typeStr: type,
            rawValue: raw);
    state = HartTableState(
      loading: false,
      devices: const ['DEV_A', 'dev_b'],
      visibleCols: const ['PV', 'FUNC', 'TF', 'ENUM', 'BITS'],
      enumMaps: const {
        0: {'01': 'On'}
      },
      bitEnumMaps: const {
        2: {1: 'Bit 0'}
      },
      data: {
        for (final device in ['DEV_A', 'dev_b'])
          device: {
            'PV': cell(device, 'PV', '3F800000'),
            'FUNC': cell(device, 'FUNC', '@1+1'),
            'TF': cell(device, 'TF', r'$[1],[1,1],0,x'),
            'ENUM': cell(device, 'ENUM', '01', type: 'ENUM00', bytes: 1),
            'BITS': cell(device, 'BITS', '01', type: 'BIT_ENUM02', bytes: 1),
          }
      },
    );
  }

  void emit(HartTableState value) => state = value;

  int addedDevices = 0;
  int editedDevices = 0;
  int removedDevices = 0;
  int addedColumns = 0;
  int editedColumns = 0;
  int removedColumns = 0;
  int writtenCells = 0;

  @override
  Future<void> addDevice(String deviceName) async => addedDevices++;
  @override
  Future<void> editDevice(String oldName, String newName) async =>
      editedDevices++;
  @override
  Future<void> removeDevice(String deviceName) async => removedDevices++;
  @override
  Future<void> addColumn(String colName, int byteSize, String typeStr,
          String defaultHex) async =>
      addedColumns++;
  @override
  Future<void> editColumn(String oldName, String newName, int byteSize,
          String typeStr, String defaultHex) async =>
      editedColumns++;
  @override
  Future<void> removeColumn(String colName) async => removedColumns++;
  @override
  Future<void> setCellValue(String device, String col, String rawValue) async =>
      writtenCells++;

  @override
  Future<void> load() async {}
}

class _ReadyModbusNotifier extends ModbusTableNotifier {
  _ReadyModbusNotifier(super.repo) {
    state = const ModbusTableState(loading: false, data: {
      'IR': (2, 'UNSIGNED', 'ir', '01', '@1+1'),
      'HR': (2, 'INTEGER', 'hr', '02', '10'),
      'DI': (1, 'UNSIGNED', 'di', '03', '@invalid'),
      'CO': (1, 'UNSIGNED', 'co', '04', '1'),
    });
  }

  void emit(ModbusTableState value) => state = value;

  int added = 0;
  int edited = 0;
  int removed = 0;

  @override
  Future<void> addVariable(String name, int byteSize, String typeStr,
          String mbPoint, String address, String formula) async =>
      added++;
  @override
  Future<void> editVariable(
          String oldName,
          String newName,
          int byteSize,
          String typeStr,
          String mbPoint,
          String address,
          String formula) async =>
      edited++;
  @override
  Future<void> removeVariable(String name) async => removed++;

  @override
  Future<void> load() async {}
}

class _ReadyCustomTypesNotifier extends CustomTypesNotifier {
  _ReadyCustomTypesNotifier(super.repo) {
    state = const CustomTypesState(loading: false, enums: {
      29: {'00': 'Off', '01': 'On'}
    }, bitEnums: {
      5: {1: 'Bit one', 2: 'Bit two'}
    }, commands: {
      '01': {
        'description': 'Read value',
        'req': <String>['request'],
        'resp': <String>['response'],
        'write': <String>['write']
      }
    });
  }

  final calls = <String>[];

  @override
  void load() {}

  @override
  void addEnumEntry(int enumIndex, String hexKey, String description) =>
      calls.add('add-enum');
  @override
  void updateEnumEntry(int enumIndex, String hexKey, String description) =>
      calls.add('edit-enum');
  @override
  void removeEnumEntry(int enumIndex, String hexKey) => calls.add('rm-enum');
  @override
  void removeEnumGroup(int enumIndex) => calls.add('rm-enum-group');
  @override
  void addBitEnumEntry(int bitEnumIndex, int hexMask, String description) =>
      calls.add('add-bit');
  @override
  void updateBitEnumEntry(int bitEnumIndex, int hexMask, String description) =>
      calls.add('edit-bit');
  @override
  void removeBitEnumEntry(int bitEnumIndex, int hexMask) => calls.add('rm-bit');
  @override
  void removeBitEnumGroup(int bitEnumIndex) => calls.add('rm-bit-group');
  @override
  void addCommand(String command, String description, List<String> req,
          List<String> resp, List<String> write) =>
      calls.add('add-command');
  @override
  void updateCommand(String command, String description, List<String> req,
          List<String> resp, List<String> write) =>
      calls.add('edit-command');
  @override
  void removeCommand(String command) => calls.add('rm-command');
}

class _FakeConnectionNotifier extends conn.ConnectionNotifier {
  _FakeConnectionNotifier(super.hart, super.modbus,
      [conn.ConnectionState initial = const conn.ConnectionState()]) {
    state = initial;
  }

  int hartTcpStarts = 0;
  int hartSerialStarts = 0;
  int hartStops = 0;
  int modbusStarts = 0;
  int modbusStops = 0;

  void emit(conn.ConnectionState value) => state = value;

  @override
  Future<void> startHartServer(
      int port, conn.TableGetter getTable, conn.CellWriter writeCell,
      {String bindHost = '127.0.0.1'}) async {
    hartTcpStarts++;
    getTable();
    writeCell('missing', 'missing', '00');
  }

  @override
  Future<void> startHartSerial(String portName, conn.TableGetter getTable,
      conn.CellWriter writeCell) async {
    hartSerialStarts++;
    getTable();
    writeCell('missing', 'missing', '00');
  }

  @override
  Future<void> stopHartServer() async {
    hartStops++;
  }

  @override
  Future<void> startModbus(int port, {String bindHost = '127.0.0.1'}) async {
    modbusStarts++;
  }

  @override
  Future<void> stopModbus() async {
    modbusStops++;
  }
}

(ProviderContainer, SqliteDatasource) _memoryContainer() {
  final datasource = SqliteDatasource()..openAt(':memory:');
  final container = ProviderContainer(overrides: [
    sqliteDatasourceProvider.overrideWithValue(datasource),
    hartTableProvider.overrideWith((ref) => _ReadyHartNotifier(
          ref.watch(dbRepositoryProvider),
          ref.watch(simulTfProvider),
          ref.watch(equipmentCatalogProvider),
        )),
    modbusTableProvider.overrideWith(
        (ref) => _ReadyModbusNotifier(ref.watch(dbRepositoryProvider))),
    customTypesProvider.overrideWith(
        (ref) => _ReadyCustomTypesNotifier(ref.watch(dbRepositoryProvider))),
    connectionProvider.overrideWith((ref) => _FakeConnectionNotifier(
          ref.watch(hartTableProvider.notifier),
          ref.watch(modbusTableProvider.notifier),
        )),
  ]);
  return (container, datasource);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1400, 900);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('presentation dialogs', () {
    testWidgets('AddDeviceDialog validates, submits, edits and cancels',
        (tester) async {
      await tester.pumpWidget(_host(const AddDeviceDialog()));
      await _tapText(tester, 'Add');
      expect(find.byType(AddDeviceDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  FIT-100  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(_host(const AddDeviceDialog(initialName: 'OLD')));
      expect(find.text('Edit Instrument'), findsOneWidget);
      await _tapText(tester, 'Cancel');
    });

    testWidgets('AddColumnDialog handles defaults, invalid initial and submit',
        (tester) async {
      await tester.pumpWidget(_host(
          const AddColumnDialog(initial: ('old', 2, 'NOT_A_TYPE', '00'))));
      expect(find.text('Edit Variable'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '');
      await _tapText(tester, 'Save');
      expect(find.byType(AddColumnDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), ' pressure ');
      await tester.enterText(find.byType(TextField).at(1), 'invalid');
      await tester.enterText(find.byType(TextField).at(2), ' abcd ');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('INTEGER').last);
      await tester.pump(const Duration(milliseconds: 500));
      await _tapText(tester, 'Save');

      await tester.pumpWidget(_host(const AddColumnDialog()));
      expect(find.text('Add Variable (Column)'), findsOneWidget);
      await _tapText(tester, 'Cancel');
    });

    testWidgets('enum dialogs cover create, edit and validation',
        (tester) async {
      await tester.pumpWidget(_host(const EditEnumEntryDialog()));
      await _tapText(tester, 'Salvar');
      expect(find.byType(EditEnumEntryDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), ' 0A ');
      await tester.enterText(find.byType(TextField).at(1), ' Running ');
      await _tapText(tester, 'Salvar');

      await tester.pumpWidget(_host(const EditEnumEntryDialog(
          initialHexKey: '01', initialDescription: 'Old')));
      expect(find.text('Editar Entrada ENUM'), findsOneWidget);
      await _tapText(tester, 'Cancelar');

      await tester.pumpWidget(_host(const EditBitEnumEntryDialog()));
      await tester.enterText(find.byType(TextField).at(0), 'bad');
      await tester.enterText(find.byType(TextField).at(1), 'Bit');
      await _tapText(tester, 'Salvar');
      expect(find.byType(EditBitEnumEntryDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '4');
      await _tapText(tester, 'Salvar');

      await tester.pumpWidget(_host(const EditBitEnumEntryDialog(
          initialMask: 2, initialDescription: 'Old')));
      expect(find.text('Editar Entrada BIT_ENUM'), findsOneWidget);
      await _tapText(tester, 'Cancelar');
    });

    testWidgets('group and command dialogs validate and parse values',
        (tester) async {
      await tester.pumpWidget(_host(const NewGroupDialog(groupType: 'ENUM')));
      expect(find.text('29'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '-1');
      await _tapText(tester, 'Criar');
      expect(find.byType(NewGroupDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), '29');
      await _tapText(tester, 'Criar');

      await tester
          .pumpWidget(_host(const NewGroupDialog(groupType: 'BIT_ENUM')));
      expect(find.text('5'), findsOneWidget);
      await _tapText(tester, 'Cancelar');

      await tester.pumpWidget(_host(const EditCommandDialog()));
      await _tapText(tester, 'Salvar');
      expect(find.byType(EditCommandDialog), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), ' 0b ');
      await tester.enterText(fields.at(1), 'Command');
      await tester.enterText(fields.at(2), ' a, , b ');
      await tester.enterText(fields.at(3), ' c ');
      await tester.enterText(fields.at(4), ' d, e ');
      await _tapText(tester, 'Salvar');

      await tester.pumpWidget(_host(const EditCommandDialog(
        initialCommand: '01',
        initialDescription: 'Existing',
        initialReq: ['request'],
        initialResp: ['response'],
        initialWrite: ['write'],
      )));
      expect(find.text('Editar Comando HART'), findsOneWidget);
      await _tapText(tester, 'Cancelar');
    });

    testWidgets('EditCellDialog submits value, function and transfer function',
        (tester) async {
      ReactVar variable(String raw, {String type = 'FLOAT', int bytes = 4}) =>
          ReactVar(
              tableName: 'HART',
              rowName: 'DEV',
              colName: 'PV',
              byteSize: bytes,
              typeStr: type,
              rawValue: raw);

      await tester.pumpWidget(_host(
          EditCellDialog(variable: variable('3F800000'), showHuman: true)));
      await tester.enterText(find.byType(TextField).first, '2');
      await _tapText(tester, 'Apply');

      await tester.pumpWidget(_host(EditCellDialog(
          variable: variable('@HART.DEV.PV + 1'), showHuman: false)));
      expect(find.text('Function'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await _tapText(tester, 'Apply');

      await tester.pumpWidget(_host(EditCellDialog(
          variable: variable(r'$[1],[1,1],0,x'), showHuman: false)));
      expect(find.text('TF Sim'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await _tapText(tester, 'Apply');

      await tester.pumpWidget(_host(EditCellDialog(
          variable: variable('01', type: 'UNSIGNED', bytes: 1),
          showHuman: false)));
      expect(find.textContaining('1 byte'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'aa');
      await _tapText(tester, 'Apply');
    });

    testWidgets('public dialog show APIs construct routes and close cleanly',
        (tester) async {
      final variable = ReactVar(
          tableName: 'HART',
          rowName: 'DEV',
          colName: 'PV',
          byteSize: 4,
          typeStr: 'FLOAT',
          rawValue: '3F800000');

      Future<void> openAndCancel(
          String label, Future<void> Function(BuildContext) open,
          {String cancel = 'Cancelar'}) async {
        await tester.pumpWidget(_host(Builder(
          builder: (context) => ElevatedButton(
              onPressed: () => open(context), child: Text(label)),
        )));
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text(cancel).last);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await openAndCancel(
          'device-show', (context) async => AddDeviceDialog.show(context),
          cancel: 'Cancel');
      await openAndCancel(
          'column-show', (context) async => AddColumnDialog.show(context),
          cancel: 'Cancel');
      await openAndCancel(
          'enum-show', (context) async => EditEnumEntryDialog.show(context));
      await openAndCancel(
          'bit-show', (context) async => EditBitEnumEntryDialog.show(context));
      await openAndCancel('group-show',
          (context) async => NewGroupDialog.show(context, 'ENUM'));
      await openAndCancel(
          'command-show', (context) async => EditCommandDialog.show(context));

      await tester.pumpWidget(_host(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => EditCellDialog.show(context, variable, true),
          child: const Text('cell-show'),
        ),
      )));
      await tester.tap(find.text('cell-show'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('cell-show'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  testWidgets('LogsScreen renders levels, filters, zooms, copies and clears',
      (tester) async {
    final log = LogNotifier()
      ..debug('DBG', 'debug')
      ..info('INF', 'info')
      ..warning('WRN', 'warning')
      ..error('ERR', 'error');
    await tester.pumpWidget(_host(const LogsScreen(),
        overrides: [logProvider.overrideWith((_) => log)]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('4 entries'), findsOneWidget);
    for (final level in ['Debug', 'Info', 'Warning', 'Error', 'All']) {
      await _tapText(tester, level);
    }
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byTooltip('Diminuir texto'));
    await tester.tap(find.byTooltip('Aumentar texto'));
    await tester.tap(find.byTooltip('Copy all to clipboard'));
    await tester.pump();
    expect(find.text('Copied to clipboard'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear logs'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('No log entries'), findsOneWidget);
  });

  testWidgets('HART and Modbus screens render loaded tables and interactions',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 1400, child: HartTableScreen())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Instrument:'), findsOneWidget);
    final filter = find.byType(TextField).first;
    await tester.enterText(filter, 'definitely-missing-device');
    await tester.pump();
    expect(find.textContaining('0 ×'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.tap(find.text('DEVICE'));
    await tester.pump();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 1400, child: ModbusTableScreen())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MB Point'), findsOneWidget);
    await tester.tap(find.text('Name'));
    await tester.pump();
    final modbusFilter = find.byType(TextField).first;
    await tester.enterText(modbusFilter, 'missing');
    await tester.pump();
    expect(find.textContaining('0 variables'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
  });

  testWidgets('HART screen executes CRUD dialogs, cell edit and state branches',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    final notifier =
        container.read(hartTableProvider.notifier) as _ReadyHartNotifier;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: HartTableScreen())),
    ));
    await tester.pump();

    await tester.tap(find.text('Add').at(0));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'new_device');
    await tester.tap(find.text('Add').last);
    await tester.pump();
    expect(notifier.addedDevices, 1);

    await tester.tap(find.text('Edit').at(0));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.text('dev_b').last);
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'renamed');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(notifier.editedDevices, 1);

    await tester.tap(find.text('Remove').at(0));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.text('dev_b').last);
    await tester.pump();
    await tester.tap(find.text('Remove').last);
    await tester.pump();
    expect(notifier.removedDevices, 1);

    await tester.tap(find.text('Remove').at(0));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Add').at(1));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'NEWCOL');
    await tester.tap(find.text('Add').last);
    await tester.pump();
    expect(notifier.addedColumns, 1);

    await tester.tap(find.text('Edit').at(1));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.text('FUNC').last);
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(notifier.editedColumns, 1);

    await tester.tap(find.text('Remove').at(1));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.text('FUNC').last);
    await tester.pump();
    await tester.tap(find.text('Remove').last);
    await tester.pump();
    expect(notifier.removedColumns, 1);

    // Header edit path and a data-cell edit path.
    await tester.tap(find.text('PV').first);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    final editableCell = find.byType(Tooltip);
    expect(editableCell, findsWidgets);
    await tester.tap(editableCell.last);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(editableCell.last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(notifier.writtenCells, 1);

    final enumCell = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'On');
    expect(enumCell, findsWidgets);
    await tester.tap(enumCell.first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(enumCell.first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 100));

    notifier.emit(const HartTableState(loading: false, error: 'hart failure'));
    await tester.pump();
    expect(find.text('hart failure'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    notifier.emit(const HartTableState(loading: true));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('HART table synchronizes both horizontal and vertical panes',
      (tester) async {
    tester.view.physicalSize = const Size(520, 500);
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    final notifier =
        container.read(hartTableProvider.notifier) as _ReadyHartNotifier;
    final columns = List.generate(15, (index) => 'C$index');
    final devices = List.generate(30, (index) => 'D$index');
    notifier.emit(HartTableState(
      loading: false,
      devices: devices,
      visibleCols: columns,
      data: {
        for (final device in devices)
          device: {
            for (final column in columns)
              column: ReactVar(
                  tableName: 'HART',
                  rowName: device,
                  colName: column,
                  byteSize: 4,
                  typeStr: 'FLOAT',
                  rawValue: '3F800000')
          }
      },
    ));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: HartTableScreen())),
    ));
    await tester.pump();

    final horizontal = find.byType(SingleChildScrollView);
    expect(horizontal, findsNWidgets(2));
    await tester.drag(horizontal.first, const Offset(-250, 0));
    await tester.pump();
    await tester.drag(horizontal.last, const Offset(-250, 0));
    await tester.pump();

    final vertical = find.byType(ListView);
    expect(vertical, findsNWidgets(2));
    await tester.drag(vertical.first, const Offset(0, -250));
    await tester.pump();
    await tester.dragFrom(const Offset(300, 300), const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Modbus screen executes add, edit, remove and error branches',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    final notifier =
        container.read(modbusTableProvider.notifier) as _ReadyModbusNotifier;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: ModbusTableScreen())),
    ));
    await tester.pump();

    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'NEW_MB');
    await tester.enterText(find.byType(TextField).at(2), 'invalid');
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(0));
    await tester.pump();
    await tester.tap(find.text('FLOAT').last);
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pump();
    await tester.tap(find.text('CO').last);
    await tester.pump();
    await tester.tap(find.text('Add').last);
    await tester.pump();
    expect(notifier.added, 1);

    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.text('HR').last);
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(notifier.edited, 1);

    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.tap(find.text('CO').last);
    await tester.pump();
    await tester.tap(find.text('Remove').last);
    await tester.pump();
    expect(notifier.removed, 1);

    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    notifier.emit(const ModbusTableState(loading: false, error: 'mb failure'));
    await tester.pump();
    expect(find.text('Error: mb failure'), findsOneWidget);
    notifier.emit(const ModbusTableState(loading: true));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Settings renders, switches mode and validates save fields',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 1000, child: SettingsScreen())),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Transfer Function (TF)'), findsOneWidget);
    await tester.tap(find.text('Serial'));
    await tester.pump();
    expect(container.read(settingsProvider).hartMode.name, 'serial');
    await tester.tap(find.text('TCP / IP'));
    await tester.pump();
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -900));
    await tester.pump();
    expect(find.text('About'), findsOneWidget);
    tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Settings'))
        .onPressed!();
    await tester.pump();
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets(
      'Settings injects ports and covers import/export success and errors',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    var fail = false;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            enumeratePorts: () async => ['COM9', 'COM2'],
            pickImportPath: () async => r'C:\tmp\input.xlsx',
            pickExportPath: () async => '/tmp/output.xlsx',
            importXls: (_) async {
              if (fail) throw StateError('import failed');
              return 7;
            },
            exportXls: (_) async {
              if (fail) throw StateError('export failed');
            },
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.tap(find.text('Serial'));
    await tester.pump();
    expect(find.text('COM9', skipOffstage: false), findsWidgets);

    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Importar de .xlsx'), 300,
        scrollable: scroll);
    await tester.tap(find.text('Importar de .xlsx'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Importado 7 linhas'), findsOneWidget);
    await tester.tap(find.text('Exportar para .xlsx'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Exportado para output.xlsx'), findsOneWidget);

    fail = true;
    await tester.tap(find.text('Importar de .xlsx'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Falha na importa'), findsOneWidget);
    await tester.tap(find.text('Exportar para .xlsx'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Falha na exporta'), findsOneWidget);
  });

  testWidgets(
      'Settings renders populated custom type groups and validation errors',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SettingsScreen(enumeratePorts: () async => const []),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('ENUMs'), 400,
        scrollable: scroll);
    await tester.tap(find.text('ENUMs'));
    await tester.pump();
    expect(find.text('ENUM29'), findsOneWidget);
    await tester.tap(find.text('ENUM29'));
    await tester.pump();
    expect(find.text('Off'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('BIT_ENUMs'), 300,
        scrollable: scroll);
    await tester.tap(find.text('BIT_ENUMs'));
    await tester.pump();
    expect(find.text('BIT_ENUM05'), findsOneWidget);
    await tester.tap(find.text('BIT_ENUM05'));
    await tester.pump();
    expect(find.text('Bit one'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Commands'), 300,
        scrollable: scroll);
    await tester.tap(find.text('Commands'));
    await tester.pump();
    expect(find.text('0x01'), findsOneWidget);
    await tester.tap(find.text('0x01'));
    await tester.pump();
    expect(find.textContaining('response'), findsOneWidget);

    // Every settings validation branch produces its own explicit message.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(2), '0');
    await tester.scrollUntilVisible(find.text('Save Settings'), 300,
        scrollable: scroll);
    tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Settings'))
        .onPressed!();
    await tester.pump();
    expect(find.textContaining('HART TCP port'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.enterText(fields.at(2), '5094');
    await tester.enterText(fields.at(3), '70000');
    tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Settings'))
        .onPressed!();
    await tester.pump();
    expect(find.textContaining('Modbus port'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.enterText(fields.at(3), '502');
    await tester.enterText(fields.at(0), '1');
    tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Settings'))
        .onPressed!();
    await tester.pump();
    expect(find.textContaining('TF step'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.enterText(fields.at(0), '50');
    await tester.enterText(fields.at(1), 'not-an-ip');
    tester
        .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Settings'))
        .onPressed!();
    await tester.pump();
    expect(find.textContaining('bind address'), findsOneWidget);
  });

  testWidgets('Settings covers serial process output, fallback and failure',
      (tester) async {
    Future<void> render(
        Future<ProcessResult> Function(String, List<String>) runner) async {
      final (container, datasource) = _memoryContainer();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SettingsScreen(runProcess: runner)),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Serial'));
      await tester.pump();
      container.dispose();
      datasource.close();
    }

    await render((_, __) async => ProcessResult(1, 0, 'COM8, COM3', ''));
    expect(find.text('COM3', skipOffstage: false), findsWidgets);
    await render((_, __) async => ProcessResult(1, 0, '', ''));
    await render((_, __) => Future<ProcessResult>.error(StateError('failed')));
  });

  testWidgets('Settings custom type controls execute CRUD callbacks',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    final custom = container.read(customTypesProvider.notifier)
        as _ReadyCustomTypesNotifier;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(
              body: SettingsScreen(enumeratePorts: () async => const []))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('ENUMs'), 500,
        scrollable: scroll);
    await tester.tap(find.text('ENUMs'));
    await tester.pump();
    await tester.tap(find.text('Novo grupo').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.text('Criar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('ENUM29'));
    await tester.pump();
    await tester.tap(find.byTooltip('Inserir entrada').first);
    await tester.pump();
    final enumFields = find.byType(TextField);
    final enumFieldCount = enumFields.evaluate().length;
    await tester.enterText(enumFields.at(enumFieldCount - 2), '02');
    await tester.enterText(enumFields.last, 'Two');
    await tester.tap(find.text('Salvar'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(custom.calls.where((call) => call == 'add-enum').length, 2);
  });

  testWidgets('Settings executes BIT_ENUM and command CRUD callbacks',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    final custom = container.read(customTypesProvider.notifier)
        as _ReadyCustomTypesNotifier;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(
              body: SettingsScreen(enumeratePorts: () async => const []))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(find.text('BIT_ENUMs'), 500,
        scrollable: scroll);
    await tester.tap(find.text('BIT_ENUMs'));
    await tester.pump();
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Novo grupo'))
        .onPressed!();
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '6');
    await tester.tap(find.text('Criar'));
    await tester.pump(const Duration(milliseconds: 300));

    tester
        .widget<IconButton>(find.ancestor(
            of: find.byTooltip('Inserir entrada'),
            matching: find.byType(IconButton)))
        .onPressed!();
    await tester.pump();
    final bitFields = find.byType(TextField);
    final bitCount = bitFields.evaluate().length;
    await tester.enterText(bitFields.at(bitCount - 2), '4');
    await tester.enterText(bitFields.last, 'Four');
    await tester.tap(find.text('Salvar'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('BIT_ENUM05'));
    await tester.pump();
    final bitTile = find.ancestor(
        of: find.text('BIT_ENUM05'), matching: find.byType(ExpansionTile));
    final bitButtons =
        find.descendant(of: bitTile, matching: find.byType(IconButton));
    tester.widget<IconButton>(bitButtons.at(2)).onPressed!();
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump(const Duration(milliseconds: 300));
    tester.widget<IconButton>(bitButtons.at(3)).onPressed!();
    await tester.pump();
    tester
        .widget<IconButton>(find.ancestor(
            of: find.byTooltip('Remover grupo'),
            matching: find.byType(IconButton)))
        .onPressed!();
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.scrollUntilVisible(find.text('Commands'), 400,
        scrollable: scroll);
    await tester.tap(find.text('Commands'));
    await tester.pump();
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Novo cmd'))
        .onPressed!();
    await tester.pump();
    final commandFields = find.byType(TextField);
    await tester.enterText(
        commandFields.at(commandFields.evaluate().length - 5), '02');
    await tester.tap(find.text('Salvar'));
    await tester.pump(const Duration(milliseconds: 300));

    final commandTile = find.ancestor(
        of: find.text('0x01'), matching: find.byType(ExpansionTile));
    final commandButtons =
        find.descendant(of: commandTile, matching: find.byType(IconButton));
    tester.widget<IconButton>(commandButtons.first).onPressed!();
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump(const Duration(milliseconds: 300));
    tester.widget<IconButton>(commandButtons.last).onPressed!();
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await tester.pump();

    expect(
        custom.calls,
        containsAll([
          'add-bit',
          'edit-bit',
          'rm-bit',
          'rm-bit-group',
          'add-command',
          'edit-command',
          'rm-command'
        ]));
  });

  testWidgets('MainShell covers wide, compact, fullscreen and navigation',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.dispose();
      datasource.close();
    });
    final router = GoRouter(
      initialLocation: '/tank3d',
      routes: [
        ShellRoute(
          builder: (_, __, child) => MainShell(child: child),
          routes: [
            for (final path in ['tank3d', 'hart', 'modbus', 'settings', 'logs'])
              GoRoute(path: '/$path', builder: (_, __) => Text(path)),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('ProcessSimul'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.table_chart_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        1);
    await tester.tap(find.byIcon(Icons.refresh_outlined));
    await tester.pump();

    tester.view.physicalSize = const Size(600, 900);
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Logs').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4);

    isFullscreenNotifier.value = true;
    await tester.pump();
    expect(find.text('ProcessSimul'), findsNothing);
    isFullscreenNotifier.value = false;
    await tester.pump();

    await tester.ensureVisible(find.text('Hex'));
    await tester.pump();
    await tester.tap(find.text('Hex'));
    await tester.pump();
    expect(container.read(hartTableProvider).showHuman, isFalse);
  });

  testWidgets('CommBar executes TF, HART TCP/serial and Modbus callbacks',
      (tester) async {
    final (container, datasource) = _memoryContainer();
    addTearDown(() {
      container.read(simulTfProvider).stop();
      container.dispose();
      datasource.close();
    });
    final connection =
        container.read(connectionProvider.notifier) as _FakeConnectionNotifier;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CommBarWidget())),
    ));
    await tester.pump();

    // TF start and stop.
    await tester.tap(find.text('Start').at(0));
    await tester.pump();
    expect(container.read(tfRunningProvider), isTrue);
    await tester.tap(find.text('Stop').first);
    await tester.pump();
    expect(container.read(tfRunningProvider), isFalse);

    // HART TCP, then serial after switching mode.
    await tester.tap(find.text('Start').at(1));
    await tester.pump();
    expect(connection.hartTcpStarts, 1);
    await tester.tap(find.text('Serial'));
    await tester.pump();
    await tester.tap(find.text('Start').at(1));
    await tester.pump();
    expect(connection.hartSerialStarts, 1);

    // Modbus start is at the far right of the scrollable communication bar.
    await tester.ensureVisible(find.text('Modbus'));
    await tester.pump();
    await tester.tap(find.text('Start').at(2));
    await tester.pump();
    expect(connection.modbusStarts, 1);

    connection.emit(const conn.ConnectionState(
      hartServerRunning: true,
      modbusRunning: true,
      hartError: 'hart-error',
      modbusError: 'modbus-error',
      modbusPort: 1502,
    ));
    await tester.pump();
    expect(find.text('hart-error'), findsOneWidget);
    expect(find.text('modbus-error'), findsOneWidget);

    await tester.tap(find.text('TCP'));
    await tester.pump();
    expect(connection.hartStops, 1);
    await tester.tap(find.text('Stop').at(0));
    await tester.pump();
    await tester.tap(find.text('Stop').at(1));
    await tester.pump();
    expect(connection.hartStops, 2);
    expect(connection.modbusStops, 1);
  });
}
