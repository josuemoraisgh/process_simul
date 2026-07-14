import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/data/datasources/sqlite_datasource.dart';
import 'package:process_simul/data/datasources/xls_import_validator.dart';

Excel _workbook({String address = '1', String commandJson = '[]'}) {
  final excel = Excel.createExcel();
  excel['HART'].appendRow([
    TextCellValue('NAME'),
    TextCellValue('BYTE_SIZE'),
    TextCellValue('TYPE'),
    TextCellValue('DEV1'),
  ]);
  excel['HART'].appendRow([
    TextCellValue('value'),
    TextCellValue('1'),
    TextCellValue('UNSIGNED'),
    TextCellValue('0A'),
  ]);
  excel['MODBUS'].appendRow([
    TextCellValue('NAME'),
    TextCellValue('BYTE_SIZE'),
    TextCellValue('TYPE'),
    TextCellValue('MB_POINT'),
    TextCellValue('ADDRESS'),
    TextCellValue('FORMULA'),
  ]);
  excel['MODBUS'].appendRow([
    TextCellValue('register'),
    TextCellValue('2'),
    TextCellValue('UNSIGNED'),
    TextCellValue('hr'),
    TextCellValue(address),
    TextCellValue('0000'),
  ]);
  excel['COMMANDS'].appendRow([
    TextCellValue('COMMAND'),
    TextCellValue('DESCRIPTION'),
    TextCellValue('REQ_JSON'),
    TextCellValue('RESP_JSON'),
    TextCellValue('WRITE_JSON'),
  ]);
  excel['COMMANDS'].appendRow([
    TextCellValue('01'),
    TextCellValue('test'),
    TextCellValue(commandJson),
    TextCellValue('[]'),
    TextCellValue('[]'),
  ]);
  return excel;
}

void main() {
  group('XLS import validation', () {
    test('accepts the currently supported workbook representation', () {
      expect(() => XlsImportValidator.validate(_workbook()), returnsNormally);
    });

    test('rejects out-of-range Modbus addresses before persistence', () {
      expect(
        () => XlsImportValidator.validate(_workbook(address: '65537')),
        throwsA(isA<XlsImportException>()),
      );
    });

    test('rejects command JSON that is not a list of strings', () {
      expect(
        () => XlsImportValidator.validate(_workbook(commandJson: '{"x":1}')),
        throwsA(isA<XlsImportException>()),
      );
    });

    test('rejects empty and oversized files before decoding', () {
      expect(
        () => XlsImportValidator.validateFileSize(0),
        throwsA(isA<XlsImportException>()),
      );
      expect(
        () => XlsImportValidator.validateFileSize(
          XlsImportValidator.maxFileBytes + 1,
        ),
        throwsA(isA<XlsImportException>()),
      );
    });

    test('rolls back every sheet if a late database write fails', () {
      final temp = Directory.systemTemp.createTempSync('process_simul_import_');
      final datasource = SqliteDatasource();
      try {
        datasource.openAt('${temp.path}${Platform.pathSeparator}test.db');
        final originalMetaCount = datasource.getHartMeta().length;
        final originalDataCount = datasource.getHartData().length;
        datasource.db.execute('''
          CREATE TRIGGER reject_import_command
          BEFORE INSERT ON hart_commands
          BEGIN
            SELECT RAISE(ABORT, 'forced late failure');
          END
        ''');

        final workbookBytes = _workbook().save()!;
        final workbookFile = File(
          '${temp.path}${Platform.pathSeparator}input.xlsx',
        )..writeAsBytesSync(workbookBytes);

        expect(
          () => datasource.importFromXls(workbookFile.path),
          throwsA(anything),
        );
        expect(datasource.getHartMeta().length, originalMetaCount);
        expect(datasource.getHartData().length, originalDataCount);
      } finally {
        datasource.close();
        temp.deleteSync(recursive: true);
      }
    });
  });
}
