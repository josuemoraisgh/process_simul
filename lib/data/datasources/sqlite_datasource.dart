import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../templates/db_template.dart';

/// Low-level SQLite operations.
///
/// Schema:
///   hart_meta  (col_name TEXT PK, byte_size INT, type_str TEXT)
///   hart_data  (device TEXT, col TEXT, raw_value TEXT, PRIMARY KEY(device,col))
///   modbus_data(name TEXT PK, byte_size INT, type_str TEXT,
///               mb_point TEXT, address TEXT, formula TEXT, raw_value TEXT)
class SqliteDatasource {
  Database? _db;

  // ── Open / init ────────────────────────────────────────────────────────────
  Future<void> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'process_simul.db');
    _db = await openDatabase(dbPath, version: 1, onCreate: _onCreate);
  }

  Database get db {
    if (_db == null) throw StateError('Database not opened');
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hart_meta (
        col_name  TEXT PRIMARY KEY,
        byte_size INTEGER NOT NULL,
        type_str  TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hart_data (
        device    TEXT NOT NULL,
        col       TEXT NOT NULL,
        raw_value TEXT NOT NULL,
        PRIMARY KEY (device, col)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS modbus_data (
        name      TEXT PRIMARY KEY,
        byte_size INTEGER NOT NULL,
        type_str  TEXT NOT NULL,
        mb_point  TEXT NOT NULL,
        address   TEXT NOT NULL,
        formula   TEXT NOT NULL,
        raw_value TEXT NOT NULL
      )
    ''');
    await _seed(db);
  }

  Future<void> _seed(Database db) async {
    final batch = db.batch();
    // Hart meta
    for (final entry in kHartTemplate.entries) {
      final (byteSize, typeStr, _) = entry.value;
      batch.insert('hart_meta', {
        'col_name': entry.key,
        'byte_size': byteSize,
        'type_str': typeStr,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    // Hart data
    for (final entry in kHartTemplate.entries) {
      final (_, _, values) = entry.value;
      for (int i = 0; i < kHartDevices.length; i++) {
        batch.insert('hart_data', {
          'device': kHartDevices[i],
          'col': entry.key,
          'raw_value': values[i],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    // Modbus data
    for (final entry in kModbusTemplate.entries) {
      final (byteSize, typeStr, mbPoint, address, formula) = entry.value;
      batch.insert('modbus_data', {
        'name': entry.key,
        'byte_size': byteSize,
        'type_str': typeStr,
        'mb_point': mbPoint,
        'address': address,
        'formula': formula,
        'raw_value': formula,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ── HART queries ────────────────────────────────────────────────────────────
  Future<List<Map<String, Object?>>> getHartMeta() =>
      db.query('hart_meta');

  Future<List<Map<String, Object?>>> getHartData() =>
      db.query('hart_data');

  Future<void> setHartCell(String device, String col, String rawValue) =>
      db.update(
        'hart_data',
        {'raw_value': rawValue},
        where: 'device=? AND col=?',
        whereArgs: [device, col],
      );

  Future<String?> getHartCell(String device, String col) async {
    final rows = await db.query('hart_data',
        where: 'device=? AND col=?', whereArgs: [device, col]);
    return rows.isEmpty ? null : rows.first['raw_value'] as String;
  }

  // ── Modbus queries ──────────────────────────────────────────────────────────
  Future<List<Map<String, Object?>>> getModbusData() =>
      db.query('modbus_data');

  Future<void> setModbusValue(String name, String rawValue) =>
      db.update(
        'modbus_data',
        {'raw_value': rawValue},
        where: 'name=?',
        whereArgs: [name],
      );

  // ── HART CRUD ───────────────────────────────────────────────────────────────
  Future<void> addHartDevice(String deviceName, Map<String, (int, String, String)> colMeta) async {
    final batch = db.batch();
    for (final entry in colMeta.entries) {
      final col = entry.key;
      final defaultVal = entry.value.$3;
      batch.insert('hart_data', {
        'device': deviceName, 'col': col, 'raw_value': defaultVal
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeHartDevice(String deviceName) =>
      db.delete('hart_data', where: 'device=?', whereArgs: [deviceName]);

  Future<void> addHartColumn(String colName, int byteSize, String typeStr,
      String defaultHex, List<String> devices) async {
    await db.insert('hart_meta', {
      'col_name': colName, 'byte_size': byteSize, 'type_str': typeStr
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final batch = db.batch();
    for (final dev in devices) {
      batch.insert('hart_data', {
        'device': dev, 'col': colName, 'raw_value': defaultHex
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeHartColumn(String colName) async {
    await db.delete('hart_meta', where: 'col_name=?', whereArgs: [colName]);
    await db.delete('hart_data', where: 'col=?', whereArgs: [colName]);
  }

  Future<List<String>> getHartDevices() async {
    final rows = await db.rawQuery('SELECT DISTINCT device FROM hart_data');
    return rows.map((r) => r['device'] as String).toList();
  }

  // ── Modbus CRUD ─────────────────────────────────────────────────────────────
  Future<void> addModbusVariable(String name, int byteSize, String typeStr,
      String mbPoint, String address, String formula) =>
      db.insert('modbus_data', {
        'name': name, 'byte_size': byteSize, 'type_str': typeStr,
        'mb_point': mbPoint, 'address': address, 'formula': formula,
        'raw_value': formula
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> removeModbusVariable(String name) =>
      db.delete('modbus_data', where: 'name=?', whereArgs: [name]);

  Future<void> close() => _db?.close() ?? Future.value();
}
