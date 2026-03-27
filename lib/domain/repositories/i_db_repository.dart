import '../entities/react_var.dart';

/// Abstract contract for the database storage layer.
abstract class IDbRepository {
  /// Initialises the database (create tables + seed default data if empty).
  Future<void> init();

  /// Returns all ReactVar instances for [tableName].
  Future<Map<String, Map<String, ReactVar>>> getTable(String tableName);

  /// Returns a single ReactVar or null.
  Future<ReactVar?> getCell(String tableName, String rowName, String colName);

  /// Persists [rawValue] for the given cell.
  Future<void> setRawValue(
      String tableName, String rowName, String colName, String rawValue);

  /// Returns ordered list of row keys for a table.
  Future<List<String>> rowKeys(String tableName);

  /// Returns ordered list of column keys for a table.
  Future<List<String>> colKeys(String tableName);

  // ── HART CRUD ───────────────────────────────────────────────────────────────
  Future<void> addHartDevice(String deviceName);
  Future<void> removeHartDevice(String deviceName);
  Future<void> addHartColumn(String colName, int byteSize, String typeStr, String defaultHex);
  Future<void> removeHartColumn(String colName);

  // ── Modbus CRUD ─────────────────────────────────────────────────────────────
  Future<void> addModbusVariable(String name, int byteSize, String typeStr, String mbPoint, String address, String formula);
  Future<void> removeModbusVariable(String name);
}
