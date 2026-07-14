import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/data/datasources/sqlite_datasource.dart';
import 'package:process_simul/data/repositories/db_repository_impl.dart';

void main() {
  late Directory temp;
  late SqliteDatasource datasource;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('process_simul_db_crud_');
    datasource = SqliteDatasource()..openAt('${temp.path}/source.db');
  });

  tearDown(() {
    datasource.close();
    temp.deleteSync(recursive: true);
  });

  group('SqliteDatasource public CRUD', () {
    test('HART device, cell and column operations persist coherently', () {
      datasource.addHartDevice('TEST', {
        'alpha': (1, 'UNSIGNED', '01'),
        'beta': (2, 'UNSIGNED', '0002'),
      });
      expect(datasource.getHartDevices(), contains('TEST'));
      expect(datasource.getHartCell('TEST', 'alpha'), '01');

      datasource.setHartCell('TEST', 'alpha', '0A');
      expect(datasource.getHartCell('TEST', 'alpha'), '0A');

      datasource.addHartColumn('extra', 2, 'UNSIGNED', '00FF', ['TEST']);
      expect(datasource.getHartCell('TEST', 'extra'), '00FF');
      expect(
        datasource.getHartMeta().where((row) => row['col_name'] == 'extra'),
        hasLength(1),
      );

      datasource.editHartColumn('extra', 'renamed', 4, 'FLOAT', '3F800000');
      expect(datasource.getHartCell('TEST', 'extra'), isNull);
      expect(datasource.getHartCell('TEST', 'renamed'), '3F800000');

      datasource.renameHartDevice('TEST', 'TEST2');
      expect(datasource.getHartDevices(), contains('TEST2'));
      expect(datasource.getHartCell('TEST2', 'renamed'), '3F800000');

      datasource.removeHartColumn('renamed');
      expect(datasource.getHartCell('TEST2', 'renamed'), isNull);
      datasource.removeHartDevice('TEST2');
      expect(datasource.getHartDevices(), isNot(contains('TEST2')));
    });

    test('Modbus variables support add, raw update, edit and removal', () {
      datasource.addModbusVariable(
          'TEST_MB', 2, 'UNSIGNED', 'hr', '20', '0011');
      expect(datasource.getModbusNames(), contains('TEST_MB'));
      datasource.setModbusValue('TEST_MB', '0022');
      expect(
        datasource
            .getModbusData()
            .singleWhere((r) => r['name'] == 'TEST_MB')['raw_value'],
        '0022',
      );

      datasource.editModbusVariable(
          'TEST_MB', 'TEST_MB_2', 4, 'FLOAT', 'ir', '21', '3F800000');
      final edited = datasource
          .getModbusData()
          .singleWhere((r) => r['name'] == 'TEST_MB_2');
      expect(edited['byte_size'], 4);
      expect(edited['mb_point'], 'ir');
      expect(edited['raw_value'], '3F800000');

      datasource.removeModbusVariable('TEST_MB_2');
      expect(datasource.getModbusNames(), isNot(contains('TEST_MB_2')));
    });

    test('ENUM and BIT_ENUM operations expose groups, indices and updates', () {
      datasource.addEnumEntry(99, '01', 'one');
      datasource.addEnumEntry(99, '02', 'two');
      expect(datasource.getEnumIndices(), contains(99));
      expect(datasource.getEnum(99), {'01': 'one', '02': 'two'});
      expect(datasource.getAllEnums()[99], containsPair('01', 'one'));
      datasource.updateEnumEntry(99, '01', 'updated');
      expect(datasource.getEnum(99)['01'], 'updated');
      datasource.removeEnumEntry(99, '02');
      expect(datasource.getEnum(99), isNot(contains('02')));
      datasource.removeEnumGroup(99);
      expect(datasource.getEnum(99), isEmpty);

      datasource.addBitEnumEntry(98, 1, 'bit one');
      datasource.addBitEnumEntry(98, 2, 'bit two');
      expect(datasource.getBitEnumIndices(), contains(98));
      expect(datasource.getBitEnum(98), {1: 'bit one', 2: 'bit two'});
      expect(datasource.getAllBitEnums()[98], containsPair(1, 'bit one'));
      datasource.updateBitEnumEntry(98, 1, 'updated bit');
      expect(datasource.getBitEnum(98)[1], 'updated bit');
      datasource.removeBitEnumEntry(98, 2);
      expect(datasource.getBitEnum(98), isNot(contains(2)));
      datasource.removeBitEnumGroup(98);
      expect(datasource.getBitEnum(98), isEmpty);
    });

    test('custom command definitions round-trip and can be removed', () {
      datasource.addCommand('FE', 'fixture', ['a'], ['b'], ['c']);
      expect(datasource.getCommandKeys(), contains('FE'));
      expect(datasource.getCommand('FE'), {
        'description': 'fixture',
        'req': ['a'],
        'resp': ['b'],
        'write': ['c'],
      });
      expect(datasource.getAllCommands(), contains('FE'));

      datasource.updateCommand('FE', 'updated', ['x'], [], ['y']);
      expect(datasource.getCommand('FE')!['description'], 'updated');
      expect(datasource.getCommand('FE')!['req'], ['x']);
      datasource.removeCommand('FE');
      expect(datasource.getCommand('FE'), isNull);
    });

    test(
        'equipment definition is atomic on duplicate and optionally provisions HART',
        () {
      datasource.addEquipmentDefinition(
        id: 'EQ-CRUD',
        protocolsJson: '["hart","modbus"]',
        profileJson: '{"key":"generic"}',
        attributesJson: '{"site":"lab"}',
        provisionHart: true,
      );
      expect(datasource.getEquipmentDefinition('EQ-CRUD'), isNotNull);
      expect(datasource.getEquipmentDefinitions().map((e) => e['id']),
          contains('EQ-CRUD'));
      expect(datasource.getHartDevices(), contains('EQ-CRUD'));

      expect(
        () => datasource.addEquipmentDefinition(
          id: 'EQ-CRUD',
          protocolsJson: '["hart"]',
          profileJson: null,
          attributesJson: '{}',
          provisionHart: true,
        ),
        throwsStateError,
      );
      expect(
          datasource
              .getEquipmentDefinitions()
              .where((e) => e['id'] == 'EQ-CRUD'),
          hasLength(1));

      datasource.removeEquipmentDefinition('EQ-CRUD', removeHart: true);
      expect(datasource.getEquipmentDefinition('EQ-CRUD'), isNull);
      expect(datasource.getHartDevices(), isNot(contains('EQ-CRUD')));
    });

    test('close is idempotent', () {
      datasource.close();
      datasource.close();
    });
  });

  group('SQLite import/export and repository facade', () {
    test('exports a decodable workbook and imports every supported sheet', () {
      datasource.addEnumEntry(99, '01', 'fixture');
      datasource.addBitEnumEntry(99, 1, 'fixture bit');
      datasource.addCommand('FE', 'fixture', [], [], []);
      datasource.addModbusVariable(
          'EXPORT_MB', 2, 'UNSIGNED', 'hr', '123', '0007');

      final path = '${temp.path}/export.xlsx';
      datasource.exportToXls(path);
      expect(File(path).lengthSync(), greaterThan(0));
      final workbook = Excel.decodeBytes(File(path).readAsBytesSync());
      expect(workbook.tables.keys,
          containsAll(['HART', 'MODBUS', 'ENUM', 'BIT_ENUM', 'COMMANDS']));

      final imported = SqliteDatasource()..openAt('${temp.path}/imported.db');
      try {
        final count = imported.importFromXls(path);
        expect(count, greaterThan(0));
        expect(imported.getModbusNames(), contains('EXPORT_MB'));
        expect(imported.getEnum(99), containsPair('01', 'fixture'));
        expect(imported.getBitEnum(99), containsPair(1, 'fixture bit'));
        expect(imported.getCommand('FE')!['description'], 'fixture');
      } finally {
        imported.close();
      }
    });

    test(
        'DbRepositoryImpl maps HART and Modbus rows and handles unknown tables',
        () async {
      final repository = DbRepositoryImpl(datasource);
      final hart = await repository.getTable('HART');
      final modbus = await repository.getTable('MODBUS');
      expect(hart, isNotEmpty);
      expect(modbus, isNotEmpty);
      expect(await repository.getTable('UNKNOWN'), isEmpty);
      expect(await repository.rowKeys('UNKNOWN'), isEmpty);
      expect(await repository.colKeys('UNKNOWN'), isEmpty);
      expect(await repository.getCell('UNKNOWN', 'x', 'y'), isNull);

      final device = (await repository.rowKeys('HART')).first;
      final column = (await repository.colKeys('HART')).first;
      await repository.setRawValue('HART', device, column, 'AA');
      expect(datasource.getHartCell(device, column), 'AA');
      expect(
          (await repository.getCell('HART', device, column))?.rawValue, 'AA');
      expect(await repository.getCell('HART', device, 'missing'), isNull);
    });
  });
}
