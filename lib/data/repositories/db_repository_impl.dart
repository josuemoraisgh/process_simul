import '../../domain/entities/react_var.dart';
import '../../domain/repositories/i_db_repository.dart';
import '../datasources/sqlite_datasource.dart';
import '../templates/db_template.dart';

class DbRepositoryImpl implements IDbRepository {
  final SqliteDatasource _ds;

  DbRepositoryImpl(this._ds);

  @override
  Future<void> init() => _ds.open();

  // ── IDbRepository ───────────────────────────────────────────────────────────
  @override
  Future<Map<String, Map<String, ReactVar>>> getTable(String tableName) async {
    if (tableName == 'HART') return _getHartTable();
    if (tableName == 'MODBUS') return _getModbusTable();
    return {};
  }

  @override
  Future<ReactVar?> getCell(
      String tableName, String rowName, String colName) async {
    if (tableName == 'HART') {
      final raw = _ds.getHartCell(rowName, colName);
      if (raw == null) return null;
      final meta = kHartTemplate[colName];
      if (meta == null) return null;
      final (byteSize, typeStr, _) = meta;
      return ReactVar(
        tableName: tableName,
        rowName: rowName,
        colName: colName,
        byteSize: byteSize,
        typeStr: typeStr,
        rawValue: raw,
      );
    }
    return null;
  }

  @override
  Future<void> setRawValue(
      String tableName, String rowName, String colName, String rawValue) async {
    if (tableName == 'HART') {
      _ds.setHartCell(rowName, colName, rawValue);
    } else if (tableName == 'MODBUS') {
      _ds.setModbusValue(rowName, rawValue);
    }
  }

  @override
  Future<List<String>> rowKeys(String tableName) async {
    if (tableName == 'HART') return _ds.getHartDevices();
    if (tableName == 'MODBUS') return _ds.getModbusNames();
    return [];
  }

  @override
  Future<List<String>> colKeys(String tableName) async {
    if (tableName == 'HART') {
      final meta = _ds.getHartMeta();
      return meta.map((r) => r['col_name'] as String).toList();
    }
    if (tableName == 'MODBUS') {
      return [
        'name',
        'byte_size',
        'type_str',
        'mb_point',
        'address',
        'formula'
      ];
    }
    return [];
  }

  // ── Private helpers ─────────────────────────────────────────────────────────
  Map<String, Map<String, ReactVar>> _getHartTable() {
    final meta = {
      for (final r in _ds.getHartMeta())
        r['col_name'] as String: (
          r['byte_size'] as int,
          r['type_str'] as String
        )
    };
    final data = _ds.getHartData();
    final result = <String, Map<String, ReactVar>>{};
    for (final row in data) {
      final device = row['device'] as String;
      final col = row['col'] as String;
      final raw = row['raw_value'] as String;
      final m = meta[col];
      if (m == null) continue;
      result.putIfAbsent(device, () => {});
      result[device]![col] = ReactVar(
        tableName: 'HART',
        rowName: device,
        colName: col,
        byteSize: m.$1,
        typeStr: m.$2,
        rawValue: raw,
      );
    }
    return result;
  }

  Map<String, Map<String, ReactVar>> _getModbusTable() {
    final rows = _ds.getModbusData();
    final result = <String, Map<String, ReactVar>>{};
    for (final row in rows) {
      final name = row['name'] as String;
      final rawValue = row['raw_value'] as String;
      result[name] = {
        'name': _makeVar('MODBUS', name, 'name', 1, 'PACKED_ASCII', name),
        'byte_size': _makeVar(
            'MODBUS', name, 'byte_size', 1, 'UNSIGNED', '${row['byte_size']}'),
        'type_str': _makeVar('MODBUS', name, 'type_str', 8, 'PACKED_ASCII',
            row['type_str'] as String),
        'mb_point': _makeVar('MODBUS', name, 'mb_point', 2, 'PACKED_ASCII',
            row['mb_point'] as String),
        'address': _makeVar(
            'MODBUS', name, 'address', 2, 'UNSIGNED', row['address'] as String),
        'formula':
            _makeVar('MODBUS', name, 'formula', 32, 'PACKED_ASCII', rawValue),
      };
    }
    return result;
  }

  ReactVar _makeVar(String table, String row, String col, int byteSize,
      String typeStr, String rawValue) {
    return ReactVar(
      tableName: table,
      rowName: row,
      colName: col,
      byteSize: byteSize,
      typeStr: typeStr,
      rawValue: rawValue,
    );
  }

  // ── HART CRUD ───────────────────────────────────────────────────────────────
  @override
  Future<void> addHartDevice(String deviceName) async {
    final colMeta = {
      for (final e in kHartTemplate.entries)
        e.key: (e.value.$1, e.value.$2, e.value.$3.first)
    };
    _ds.addHartDevice(deviceName, colMeta);
  }

  @override
  Future<void> removeHartDevice(String deviceName) async =>
      _ds.removeHartDevice(deviceName);

  @override
  Future<void> renameHartDevice(String oldName, String newName) async =>
      _ds.renameHartDevice(oldName, newName);

  @override
  Future<void> addHartColumn(
      String colName, int byteSize, String typeStr, String defaultHex) async {
    final devices = _ds.getHartDevices();
    _ds.addHartColumn(colName, byteSize, typeStr, defaultHex, devices);
  }

  @override
  Future<void> removeHartColumn(String colName) async =>
      _ds.removeHartColumn(colName);

  @override
  Future<void> editHartColumn(String oldColName, String newColName,
          int byteSize, String typeStr, String defaultHex) async =>
      _ds.editHartColumn(oldColName, newColName, byteSize, typeStr, defaultHex);

  // ── Modbus CRUD ─────────────────────────────────────────────────────────────
  @override
  Future<void> addModbusVariable(String name, int byteSize, String typeStr,
          String mbPoint, String address, String formula) async =>
      _ds.addModbusVariable(name, byteSize, typeStr, mbPoint, address, formula);

  @override
  Future<void> removeModbusVariable(String name) async =>
      _ds.removeModbusVariable(name);

  @override
  Future<void> editModbusVariable(
          String oldName,
          String newName,
          int byteSize,
          String typeStr,
          String mbPoint,
          String address,
          String formula) async =>
      _ds.editModbusVariable(
          oldName, newName, byteSize, typeStr, mbPoint, address, formula);

  // ── HART ENUM CRUD ──────────────────────────────────────────────────────────
  @override
  Map<int, Map<String, String>> getAllEnums() => _ds.getAllEnums();

  @override
  Map<String, String> getEnum(int enumIndex) => _ds.getEnum(enumIndex);

  @override
  List<int> getEnumIndices() => _ds.getEnumIndices();

  @override
  void addEnumEntry(int enumIndex, String hexKey, String description) =>
      _ds.addEnumEntry(enumIndex, hexKey, description);

  @override
  void removeEnumEntry(int enumIndex, String hexKey) =>
      _ds.removeEnumEntry(enumIndex, hexKey);

  @override
  void removeEnumGroup(int enumIndex) => _ds.removeEnumGroup(enumIndex);

  @override
  void updateEnumEntry(int enumIndex, String hexKey, String description) =>
      _ds.updateEnumEntry(enumIndex, hexKey, description);

  // ── HART BIT_ENUM CRUD ──────────────────────────────────────────────────────
  @override
  Map<int, Map<int, String>> getAllBitEnums() => _ds.getAllBitEnums();

  @override
  Map<int, String> getBitEnum(int bitEnumIndex) => _ds.getBitEnum(bitEnumIndex);

  @override
  List<int> getBitEnumIndices() => _ds.getBitEnumIndices();

  @override
  void addBitEnumEntry(int bitEnumIndex, int hexMask, String description) =>
      _ds.addBitEnumEntry(bitEnumIndex, hexMask, description);

  @override
  void removeBitEnumEntry(int bitEnumIndex, int hexMask) =>
      _ds.removeBitEnumEntry(bitEnumIndex, hexMask);

  @override
  void removeBitEnumGroup(int bitEnumIndex) =>
      _ds.removeBitEnumGroup(bitEnumIndex);

  @override
  void updateBitEnumEntry(int bitEnumIndex, int hexMask, String description) =>
      _ds.updateBitEnumEntry(bitEnumIndex, hexMask, description);

  // ── HART COMMANDS CRUD ──────────────────────────────────────────────────────
  @override
  Map<String, Map<String, dynamic>> getAllCommands() => _ds.getAllCommands();

  @override
  Map<String, dynamic>? getCommand(String command) => _ds.getCommand(command);

  @override
  List<String> getCommandKeys() => _ds.getCommandKeys();

  @override
  void addCommand(String command, String description, List<String> req,
          List<String> resp, List<String> write) =>
      _ds.addCommand(command, description, req, resp, write);

  @override
  void updateCommand(String command, String description, List<String> req,
          List<String> resp, List<String> write) =>
      _ds.updateCommand(command, description, req, resp, write);

  @override
  void removeCommand(String command) => _ds.removeCommand(command);

  // ── XLS Import / Export ─────────────────────────────────────────────────────
  @override
  Future<int> importFromXls(String sourcePath) async =>
      _ds.importFromXls(sourcePath);

  @override
  Future<void> exportToXls(String destPath) async => _ds.exportToXls(destPath);
}
