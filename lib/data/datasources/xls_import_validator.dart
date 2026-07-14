import 'dart:convert';

import 'package:excel/excel.dart';

class XlsImportException implements FormatException {
  @override
  final String message;
  @override
  final dynamic source;
  @override
  final int? offset;

  const XlsImportException(this.message, {this.source, this.offset});

  @override
  String toString() => 'Invalid XLS import: $message';
}

/// Pure validation boundary for workbooks supplied by users.
class XlsImportValidator {
  static const int maxFileBytes = 10 * 1024 * 1024;
  static const int maxRowsPerSheet = 10000;
  static const int maxColumnsPerSheet = 512;
  static const int maxTotalCells = 500000;
  static const int maxCellCharacters = 4096;

  static final RegExp _identifier = RegExp(r'^[A-Za-z0-9_. -]{1,128}$');
  static final RegExp _hex = RegExp(r'^[0-9A-Fa-f]+$');
  static final RegExp _enumHex = RegExp(r'^[0-9A-Fa-f]+(?:-[0-9A-Fa-f]+)?$');
  static final RegExp _customType = RegExp(r'^(?:BIT_)?ENUM\d+$');
  static const Set<String> _baseTypes = {
    'UNSIGNED',
    'INTEGER',
    'FLOAT',
    'SREAL',
    'PACKED_ASCII',
    'DATE',
    'PROCESS_VARIABLE',
  };
  static const Set<String> _modbusPoints = {'hr', 'ir', 'co', 'di'};

  static void validateFileSize(int byteLength) {
    if (byteLength <= 0 || byteLength > maxFileBytes) {
      throw const XlsImportException(
        'file size must be between 1 and $maxFileBytes bytes',
      );
    }
  }

  static void validate(Excel excel) {
    var totalCells = 0;
    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.length > maxRowsPerSheet) {
        throw XlsImportException(
          'sheet ${entry.key} exceeds $maxRowsPerSheet rows',
        );
      }
      for (final row in sheet.rows) {
        if (row.length > maxColumnsPerSheet) {
          throw XlsImportException(
            'sheet ${entry.key} exceeds $maxColumnsPerSheet columns',
          );
        }
        totalCells += row.length;
        if (totalCells > maxTotalCells) {
          throw const XlsImportException('workbook contains too many cells');
        }
        for (final cell in row) {
          final value = cell?.value?.toString() ?? '';
          if (value.length > maxCellCharacters) {
            throw XlsImportException(
              'sheet ${entry.key} contains a cell longer than '
              '$maxCellCharacters characters',
            );
          }
        }
      }
    }

    final hart = excel.tables['HART'] ?? excel.tables['HART_tabela'];
    if (hart != null && hart.rows.length > 1) _validateHart(hart.rows);
    final modbus = excel.tables['MODBUS'] ?? excel.tables['MODBUS_tabela'];
    if (modbus != null && modbus.rows.length > 1) {
      _validateModbus(modbus.rows);
    }
    final enums = excel.tables['ENUM'];
    if (enums != null) _validateEnums(enums.rows);
    final bitEnums = excel.tables['BIT_ENUM'];
    if (bitEnums != null) _validateBitEnums(bitEnums.rows);
    final commands = excel.tables['COMMANDS'];
    if (commands != null) _validateCommands(commands.rows);
  }

  static void _validateHart(List<List<Data?>> rows) {
    final headers = _values(rows.first);
    final name = _column(headers, 'NAME');
    final size = _column(headers, 'BYTE_SIZE');
    final type = _column(headers, 'TYPE');
    if (name < 0 || size < 0 || type < 0) {
      throw const XlsImportException(
        'HART sheet requires NAME, BYTE_SIZE and TYPE columns',
      );
    }
    final meta = {name, size, type};
    for (var column = 0; column < headers.length; column++) {
      if (!meta.contains(column) && headers[column].isNotEmpty) {
        _validateIdentifier(headers[column], 'HART device');
      }
    }
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = _values(rows[rowIndex]);
      final columnName = _at(row, name);
      if (columnName.isEmpty) continue;
      _validateIdentifier(columnName, 'HART column');
      _validateByteSize(_at(row, size), 'HART row ${rowIndex + 1}');
      _validateType(_at(row, type), 'HART row ${rowIndex + 1}');
      for (var column = 0; column < row.length; column++) {
        if (meta.contains(column) || row[column].isEmpty) continue;
        final value = row[column];
        if (!value.startsWith('@') &&
            !value.startsWith(r'$') &&
            !_hex.hasMatch(value)) {
          throw XlsImportException(
            'HART row ${rowIndex + 1} has a non-hex raw value',
          );
        }
      }
    }
  }

  static void _validateModbus(List<List<Data?>> rows) {
    final headers = _values(rows.first).map((e) => e.toUpperCase()).toList();
    final name = _column(headers, 'NAME');
    if (name < 0) {
      throw const XlsImportException('MODBUS sheet requires a NAME column');
    }
    final size = _column(headers, 'BYTE_SIZE');
    final type = _column(headers, 'TYPE');
    final point = _column(headers, 'MB_POINT');
    final address = _column(headers, 'ADDRESS');
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = _values(rows[rowIndex]);
      final variable = _at(row, name);
      if (variable.isEmpty) continue;
      _validateIdentifier(variable, 'MODBUS variable');
      if (size >= 0 && _at(row, size).isNotEmpty) {
        _validateByteSize(_at(row, size), 'MODBUS row ${rowIndex + 1}');
      }
      if (type >= 0 && _at(row, type).isNotEmpty) {
        _validateType(_at(row, type), 'MODBUS row ${rowIndex + 1}');
      }
      final pointValue = point < 0 || _at(row, point).isEmpty
          ? 'ir'
          : _at(row, point).toLowerCase();
      if (!_modbusPoints.contains(pointValue)) {
        throw XlsImportException(
          'MODBUS row ${rowIndex + 1} has invalid MB_POINT',
        );
      }
      final addressValue =
          address < 0 || _at(row, address).isEmpty ? '1' : _at(row, address);
      final parsedAddress = int.tryParse(addressValue);
      if (parsedAddress == null || parsedAddress < 1 || parsedAddress > 65536) {
        throw XlsImportException(
          'MODBUS row ${rowIndex + 1} address must be between 1 and 65536',
        );
      }
    }
  }

  static void _validateEnums(List<List<Data?>> rows) {
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = _values(rows[rowIndex]);
      if (row.every((value) => value.isEmpty)) continue;
      if (row.length < 3 || int.tryParse(row[0]) == null) {
        throw XlsImportException('ENUM row ${rowIndex + 1} is invalid');
      }
      if (!_enumHex.hasMatch(row[1])) {
        throw XlsImportException(
            'ENUM row ${rowIndex + 1} has invalid hex key');
      }
    }
  }

  static void _validateBitEnums(List<List<Data?>> rows) {
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = _values(rows[rowIndex]);
      if (row.every((value) => value.isEmpty)) continue;
      if (row.length < 3 ||
          int.tryParse(row[0]) == null ||
          int.tryParse(row[1]) == null) {
        throw XlsImportException('BIT_ENUM row ${rowIndex + 1} is invalid');
      }
    }
  }

  static void _validateCommands(List<List<Data?>> rows) {
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = _values(rows[rowIndex]);
      if (row.every((value) => value.isEmpty)) continue;
      if (row.length < 5 || row[0].length > 2 || !_hex.hasMatch(row[0])) {
        throw XlsImportException(
            'COMMANDS row ${rowIndex + 1} has invalid command');
      }
      for (var column = 2; column <= 4; column++) {
        try {
          final decoded = jsonDecode(row[column]);
          if (decoded is! List || decoded.any((item) => item is! String)) {
            throw const FormatException();
          }
        } on FormatException {
          throw XlsImportException(
            'COMMANDS row ${rowIndex + 1} requires JSON string lists',
          );
        }
      }
    }
  }

  static void _validateIdentifier(String value, String label) {
    if (!_identifier.hasMatch(value)) {
      throw XlsImportException('$label has invalid characters or length');
    }
  }

  static void _validateByteSize(String value, String label) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 255) {
      throw XlsImportException('$label BYTE_SIZE must be between 1 and 255');
    }
  }

  static void _validateType(String value, String label) {
    final normalized = value.toUpperCase();
    if (!_baseTypes.contains(normalized) && !_customType.hasMatch(normalized)) {
      throw XlsImportException('$label has unsupported TYPE $value');
    }
  }

  static List<String> _values(List<Data?> row) =>
      row.map((cell) => cell?.value?.toString().trim() ?? '').toList();

  static int _column(List<String> headers, String name) =>
      headers.indexWhere((header) => header.toUpperCase() == name);

  static String _at(List<String> row, int index) =>
      index >= 0 && index < row.length ? row[index] : '';
}
