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
  Future<void> renameHartDevice(String oldName, String newName);
  Future<void> addHartColumn(
      String colName, int byteSize, String typeStr, String defaultHex);
  Future<void> removeHartColumn(String colName);
  Future<void> editHartColumn(String oldColName, String newColName,
      int byteSize, String typeStr, String defaultHex);

  // ── Modbus CRUD ─────────────────────────────────────────────────────────────
  Future<void> addModbusVariable(String name, int byteSize, String typeStr,
      String mbPoint, String address, String formula);
  Future<void> removeModbusVariable(String name);
  Future<void> editModbusVariable(String oldName, String newName, int byteSize,
      String typeStr, String mbPoint, String address, String formula);

  // ── HART ENUM CRUD ──────────────────────────────────────────────────────────
  Map<int, Map<String, String>> getAllEnums();
  Map<String, String> getEnum(int enumIndex);
  List<int> getEnumIndices();
  void addEnumEntry(int enumIndex, String hexKey, String description);
  void removeEnumEntry(int enumIndex, String hexKey);
  void removeEnumGroup(int enumIndex);
  void updateEnumEntry(int enumIndex, String hexKey, String description);

  // ── HART BIT_ENUM CRUD ──────────────────────────────────────────────────────
  Map<int, Map<int, String>> getAllBitEnums();
  Map<int, String> getBitEnum(int bitEnumIndex);
  List<int> getBitEnumIndices();
  void addBitEnumEntry(int bitEnumIndex, int hexMask, String description);
  void removeBitEnumEntry(int bitEnumIndex, int hexMask);
  void removeBitEnumGroup(int bitEnumIndex);
  void updateBitEnumEntry(int bitEnumIndex, int hexMask, String description);

  // ── HART COMMANDS CRUD ──────────────────────────────────────────────────────
  Map<String, Map<String, dynamic>> getAllCommands();
  Map<String, dynamic>? getCommand(String command);
  List<String> getCommandKeys();
  void addCommand(String command, String description, List<String> req,
      List<String> resp, List<String> write);
  void updateCommand(String command, String description, List<String> req,
      List<String> resp, List<String> write);
  void removeCommand(String command);

  // ── XLS Import / Export ─────────────────────────────────────────────────────
  /// Imports HART/Modbus/ENUM data from an XLSX file. Returns rows imported.
  Future<int> importFromXls(String sourcePath);

  /// Exports all data to an XLSX file.
  Future<void> exportToXls(String destPath);
}
