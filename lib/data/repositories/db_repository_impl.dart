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
      final raw = await _ds.getHartCell(rowName, colName);
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
      await _ds.setHartCell(rowName, colName, rawValue);
    } else if (tableName == 'MODBUS') {
      await _ds.setModbusValue(rowName, rawValue);
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
      final meta = await _ds.getHartMeta();
      return meta.map((r) => r['col_name'] as String).toList();
    }
    if (tableName == 'MODBUS') {
      return ['name', 'byte_size', 'type_str', 'mb_point', 'address', 'formula'];
    }
    return [];
  }

  // ── Private helpers ─────────────────────────────────────────────────────────
  Future<Map<String, Map<String, ReactVar>>> _getHartTable() async {
    final meta = {
      for (final r in await _ds.getHartMeta())
        r['col_name'] as String: (r['byte_size'] as int, r['type_str'] as String)
    };
    final data = await _ds.getHartData();
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

  Future<Map<String, Map<String, ReactVar>>> _getModbusTable() async {
    final rows = await _ds.getModbusData();
    final result = <String, Map<String, ReactVar>>{};
    for (final row in rows) {
      final name = row['name'] as String;
      final rawValue = row['raw_value'] as String;
      result[name] = {
        'name':      _makeVar('MODBUS', name, 'name',      1, 'PACKED_ASCII', name),
        'byte_size': _makeVar('MODBUS', name, 'byte_size', 1, 'UNSIGNED',     '${row['byte_size']}'),
        'type_str':  _makeVar('MODBUS', name, 'type_str',  8, 'PACKED_ASCII', row['type_str'] as String),
        'mb_point':  _makeVar('MODBUS', name, 'mb_point',  2, 'PACKED_ASCII', row['mb_point'] as String),
        'address':   _makeVar('MODBUS', name, 'address',   2, 'UNSIGNED',     row['address'] as String),
        'formula':   _makeVar('MODBUS', name, 'formula',   32, 'PACKED_ASCII', rawValue),
      };
    }
    return result;
  }

  ReactVar _makeVar(String table, String row, String col,
      int byteSize, String typeStr, String rawValue) {
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
    await _ds.addHartDevice(deviceName, colMeta);
  }

  @override
  Future<void> removeHartDevice(String deviceName) =>
      _ds.removeHartDevice(deviceName);

  @override
  Future<void> addHartColumn(String colName, int byteSize, String typeStr,
      String defaultHex) async {
    final devices = await _ds.getHartDevices();
    await _ds.addHartColumn(colName, byteSize, typeStr, defaultHex, devices);
  }

  @override
  Future<void> removeHartColumn(String colName) =>
      _ds.removeHartColumn(colName);

  // ── Modbus CRUD ─────────────────────────────────────────────────────────────
  @override
  Future<void> addModbusVariable(String name, int byteSize, String typeStr,
      String mbPoint, String address, String formula) =>
      _ds.addModbusVariable(name, byteSize, typeStr, mbPoint, address, formula);

  @override
  Future<void> removeModbusVariable(String name) =>
      _ds.removeModbusVariable(name);

  // ── Import ──────────────────────────────────────────────────────────────────
  @override
  Future<int> importFromDb(String sourcePath) => _ds.importFromDb(sourcePath);
}
