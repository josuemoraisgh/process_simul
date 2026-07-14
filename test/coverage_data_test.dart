import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/application/equipment/equipment_catalog.dart';
import 'package:process_simul/data/datasources/sqlite_datasource.dart';
import 'package:process_simul/data/datasources/xls_import_validator.dart';
import 'package:process_simul/data/repositories/db_repository_impl.dart';
import 'package:process_simul/data/repositories/sqlite_equipment_repository.dart';
import 'package:process_simul/domain/equipment/equipment.dart';

Excel _bookWith(String sheet, List<List<String>> rows) {
  final book = Excel.createExcel();
  for (final row in rows) {
    book[sheet].appendRow(row.map(TextCellValue.new).toList());
  }
  return book;
}

Uint8List _patchCentralEntry(
    List<int> source, void Function(Uint8List, int) edit) {
  final bytes = Uint8List.fromList(source);
  for (var i = 0; i + 46 <= bytes.length; i++) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x01 &&
        bytes[i + 3] == 0x02) {
      edit(bytes, i);
      return bytes;
    }
  }
  throw StateError('central directory not found in fixture');
}

void _writeU32(Uint8List bytes, int offset, int value) {
  bytes.buffer.asByteData().setUint32(offset, value, Endian.little);
}

void main() {
  group('XLSX archive boundary', () {
    test('accepts a normal XLSX and rejects malformed containers', () {
      final valid = Excel.createExcel().save()!;
      expect(
        () => XlsImportValidator.validateXlsxArchive(valid),
        returnsNormally,
      );
      expect(
        () => XlsImportValidator.validateXlsxArchive(List.filled(32, 0)),
        throwsA(isA<XlsImportException>()),
      );
      expect(
        () => XlsImportValidator.validateXlsxArchive([1]),
        throwsA(isA<XlsImportException>()),
      );
      expect(
        () => XlsImportValidator.validateSourcePath('legacy.xls'),
        throwsA(isA<XlsImportException>()),
      );
      expect(
        () => XlsImportValidator.validateSourcePath('valid.XLSX'),
        returnsNormally,
      );
      expect(const XlsImportException('reason').toString(), contains('reason'));
    });

    test('rejects declared expansion bombs and encrypted entries', () {
      final valid = Excel.createExcel().save()!;
      final bomb = _patchCentralEntry(valid, (bytes, offset) {
        _writeU32(bytes, offset + 24, XlsImportValidator.maxExpandedBytes + 1);
      });
      expect(
        () => XlsImportValidator.validateXlsxArchive(bomb),
        throwsA(isA<XlsImportException>()),
      );

      final encrypted = _patchCentralEntry(valid, (bytes, offset) {
        bytes.buffer.asByteData().setUint16(offset + 8, 1, Endian.little);
      });
      expect(
        () => XlsImportValidator.validateXlsxArchive(encrypted),
        throwsA(isA<XlsImportException>()),
      );

      final zeroCompressed = _patchCentralEntry(valid, (bytes, offset) {
        _writeU32(bytes, offset + 20, 0);
        _writeU32(bytes, offset + 24, 1);
      });
      expect(
        () => XlsImportValidator.validateXlsxArchive(zeroCompressed),
        throwsA(isA<XlsImportException>()),
      );
    });
  });

  group('workbook schema rejection matrix', () {
    test('rejects HART schema, identifiers, sizes, types and raw values', () {
      final cases = <Excel>[
        _bookWith('HART', [
          ['NAME', 'TYPE'],
          ['x', 'UNSIGNED'],
        ]),
        _bookWith('HART', [
          ['NAME', 'BYTE_SIZE', 'TYPE', 'bad/device'],
          ['x', '1', 'UNSIGNED', '00'],
        ]),
        _bookWith('HART', [
          ['NAME', 'BYTE_SIZE', 'TYPE', 'D'],
          ['bad/name', '1', 'UNSIGNED', '00'],
        ]),
        _bookWith('HART', [
          ['NAME', 'BYTE_SIZE', 'TYPE', 'D'],
          ['x', '0', 'UNSIGNED', '00'],
        ]),
        _bookWith('HART', [
          ['NAME', 'BYTE_SIZE', 'TYPE', 'D'],
          ['x', '1', 'UNKNOWN', '00'],
        ]),
        _bookWith('HART', [
          ['NAME', 'BYTE_SIZE', 'TYPE', 'D'],
          ['x', '1', 'UNSIGNED', 'not-hex'],
        ]),
      ];
      for (final book in cases) {
        expect(() => XlsImportValidator.validate(book),
            throwsA(isA<XlsImportException>()));
      }
    });

    test('rejects malformed Modbus, enum, bit enum and command rows', () {
      final cases = <Excel>[
        _bookWith('MODBUS', [
          ['TYPE'],
          ['UNSIGNED'],
        ]),
        _bookWith('MODBUS', [
          ['NAME', 'MB_POINT'],
          ['bad/name', 'hr'],
        ]),
        _bookWith('MODBUS', [
          ['NAME', 'BYTE_SIZE'],
          ['x', '999'],
        ]),
        _bookWith('MODBUS', [
          ['NAME', 'TYPE'],
          ['x', 'bad'],
        ]),
        _bookWith('MODBUS', [
          ['NAME', 'MB_POINT'],
          ['x', 'bad'],
        ]),
        _bookWith('MODBUS', [
          ['NAME', 'ADDRESS'],
          ['x', 'abc'],
        ]),
        _bookWith('ENUM', [
          ['INDEX', 'HEX', 'DESCRIPTION'],
          ['x', '01', 'bad'],
        ]),
        _bookWith('ENUM', [
          ['INDEX', 'HEX', 'DESCRIPTION'],
          ['1', 'GG', 'bad'],
        ]),
        _bookWith('BIT_ENUM', [
          ['INDEX', 'MASK', 'DESCRIPTION'],
          ['1', 'x', 'bad'],
        ]),
        _bookWith('COMMANDS', [
          ['COMMAND', 'DESCRIPTION', 'REQ', 'RESP', 'WRITE'],
          ['XYZ', '', '[]', '[]', '[]'],
        ]),
        _bookWith('COMMANDS', [
          ['COMMAND', 'DESCRIPTION', 'REQ', 'RESP', 'WRITE'],
          ['01', '', '[1]', '[]', '[]'],
        ]),
      ];
      for (final book in cases) {
        expect(() => XlsImportValidator.validate(book),
            throwsA(isA<XlsImportException>()));
      }
    });

    test('enforces sheet dimensions and cell length', () {
      final tooWide = Excel.createExcel();
      tooWide['Sheet1'].appendRow(List.generate(
        XlsImportValidator.maxColumnsPerSheet + 1,
        (index) => TextCellValue('$index'),
      ));
      expect(() => XlsImportValidator.validate(tooWide),
          throwsA(isA<XlsImportException>()));

      final longCell = _bookWith('Sheet1', [
        ['x' * (XlsImportValidator.maxCellCharacters + 1)],
      ]);
      expect(() => XlsImportValidator.validate(longCell),
          throwsA(isA<XlsImportException>()));

      final tooTall = Excel.createExcel();
      tooTall['Sheet1']
          .cell(CellIndex.indexByColumnRow(
            columnIndex: 0,
            rowIndex: XlsImportValidator.maxRowsPerSheet,
          ))
          .value = TextCellValue('last');
      expect(() => XlsImportValidator.validate(tooTall),
          throwsA(isA<XlsImportException>()));
    });
  });

  group('repository facade coverage', () {
    late Directory temp;
    late SqliteDatasource datasource;
    late DbRepositoryImpl repository;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('data-coverage-');
      datasource = SqliteDatasource()..openAt('${temp.path}/data.db');
      repository = DbRepositoryImpl(datasource);
    });

    tearDown(() {
      datasource.close();
      temp.deleteSync(recursive: true);
    });

    test('delegates all public CRUD families', () async {
      await repository.addHartDevice('FACADE');
      expect(await repository.rowKeys('HART'), contains('FACADE'));
      expect(await repository.colKeys('HART'), isNotEmpty);
      expect(await repository.getTable('HART'), contains('FACADE'));
      expect(await repository.getCell('HART', 'missing', 'PV'), isNull);
      datasource.db.execute(
        "INSERT INTO hart_data(device,col,raw_value) VALUES('FACADE','ORPHAN','00')",
      );
      expect(await repository.getCell('HART', 'FACADE', 'ORPHAN'), isNull);

      await repository.addHartColumn('CUSTOM', 1, 'UNSIGNED', '00');
      await repository.editHartColumn(
          'CUSTOM', 'CUSTOM2', 2, 'INTEGER', '0001');
      await repository.renameHartDevice('FACADE', 'FACADE2');
      await repository.removeHartColumn('CUSTOM2');
      await repository.removeHartDevice('FACADE2');

      await repository.addModbusVariable(
          'MB_FACADE', 2, 'UNSIGNED', 'hr', '9', '0001');
      await repository.setRawValue('MODBUS', 'MB_FACADE', 'formula', '0002');
      expect(await repository.rowKeys('MODBUS'), contains('MB_FACADE'));
      expect(await repository.colKeys('MODBUS'), contains('address'));
      expect(await repository.getTable('MODBUS'), contains('MB_FACADE'));
      await repository.editModbusVariable(
          'MB_FACADE', 'MB_FACADE2', 4, 'FLOAT', 'ir', '10', '3F800000');
      await repository.removeModbusVariable('MB_FACADE2');
      await repository.setRawValue('UNKNOWN', 'x', 'y', 'z');

      repository.addEnumEntry(121, '01', 'one');
      expect(repository.getEnum(121), containsPair('01', 'one'));
      expect(repository.getEnumIndices(), contains(121));
      expect(repository.getAllEnums(), contains(121));
      repository.updateEnumEntry(121, '01', 'updated');
      repository.removeEnumEntry(121, '01');
      repository.removeEnumGroup(121);

      repository.addBitEnumEntry(122, 1, 'one');
      expect(repository.getBitEnum(122), containsPair(1, 'one'));
      expect(repository.getBitEnumIndices(), contains(122));
      expect(repository.getAllBitEnums(), contains(122));
      repository.updateBitEnumEntry(122, 1, 'updated');
      repository.removeBitEnumEntry(122, 1);
      repository.removeBitEnumGroup(122);

      repository.addCommand('FD', 'one', [], [], []);
      expect(repository.getCommand('FD'), isNotNull);
      expect(repository.getCommandKeys(), contains('FD'));
      expect(repository.getAllCommands(), contains('FD'));
      repository.updateCommand('FD', 'two', ['x'], [], []);
      repository.removeCommand('FD');
    });

    test('delegates workbook export and import', () async {
      final path = '${temp.path}/facade.xlsx';
      await repository.exportToXls(path);
      expect(await repository.importFromXls(path), greaterThan(0));
    });

    test('repository init uses the injected documents directory', () async {
      final isolated = Directory('${temp.path}/documents')..createSync();
      final initializedDatasource = SqliteDatasource(
        documentsDirectory: () async => isolated,
      );
      final initializedRepository = DbRepositoryImpl(initializedDatasource);
      await initializedRepository.init();
      try {
        expect(File('${isolated.path}/process_simul.db').existsSync(), isTrue);
      } finally {
        initializedDatasource.close();
      }
    });

    test('equipment repository covers compatibility and failure paths',
        () async {
      final equipment = SqliteEquipmentRepository(datasource);
      datasource.addHartDevice('LEGACY', const {
        'legacy': (1, 'UNSIGNED', '00'),
      });
      expect((await equipment.find(EquipmentId('LEGACY')))!.protocols,
          {EquipmentProtocol.hart});
      expect(
          (await equipment.list()).map((e) => e.id.value), contains('LEGACY'));

      final definition = EquipmentDefinition(
        id: EquipmentId('PROFILED'),
        protocols: const {EquipmentProtocol.modbus},
        profile: EquipmentProfile(
          key: 'p',
          label: 'Profile',
          values: {'unit': 7},
        ),
        attributes: const {'area': 'A'},
      );
      await equipment.add(definition);
      final loaded = await equipment.find(definition.id);
      expect(loaded!.profile!.values, {'unit': 7});
      expect(loaded.attributes, {'area': 'A'});
      expect(() => equipment.add(definition),
          throwsA(isA<DuplicateEquipmentException>()));
      expect(() => equipment.remove(EquipmentId('ABSENT')),
          throwsA(isA<EquipmentNotFoundException>()));
      await equipment.remove(definition.id);
    });
  });
}
