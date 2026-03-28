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

  Future<void> renameHartDevice(String oldName, String newName) =>
      db.update('hart_data', {'device': newName},
          where: 'device=?', whereArgs: [oldName]);

  Future<void> editHartColumn(String oldColName, String newColName,
      int byteSize, String typeStr, String defaultHex) async {
    await db.update('hart_meta',
        {'col_name': newColName, 'byte_size': byteSize, 'type_str': typeStr},
        where: 'col_name=?', whereArgs: [oldColName]);
    if (oldColName != newColName) {
      await db.update('hart_data', {'col': newColName},
          where: 'col=?', whereArgs: [oldColName]);
    }
    if (defaultHex.isNotEmpty) {
      await db.update('hart_data', {'raw_value': defaultHex},
          where: 'col=?', whereArgs: [newColName]);
    }
  }

  Future<void> editModbusVariable(String oldName, String newName, int byteSize,
      String typeStr, String mbPoint, String address, String formula) =>
      db.update('modbus_data', {
        'name':      newName,
        'byte_size': byteSize,
        'type_str':  typeStr,
        'mb_point':  mbPoint,
        'address':   address,
        'formula':   formula,
        'raw_value': formula,
      }, where: 'name=?', whereArgs: [oldName]);

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

  Future<List<String>> getModbusNames() async {
    final rows = await db.query('modbus_data', columns: ['name']);
    return rows.map((r) => r['name'] as String).toList();
  }

  // ── Import from external .db file ──────────────────────────────────────────
  /// Reads HART and Modbus data from [sourcePath].
  /// Supports two schemas:
  ///   • Flutter schema : hart_meta + hart_data + modbus_data
  ///   • Python schema  : HART_tabela + MODBUS_tabela (wide/transposed format)
  Future<int> importFromDb(String sourcePath) async {
    final srcDb = await openDatabase(sourcePath, readOnly: true);
    try {
      // Detect which schema the file uses
      final hasPythonHart = (await _safeQuery(srcDb, 'HART_tabela')) != null;
      if (hasPythonHart) {
        return await _importPythonSchema(srcDb);
      } else {
        return await _importFlutterSchema(srcDb);
      }
    } finally {
      await srcDb.close();
    }
  }

  // ── Flutter-schema import ──────────────────────────────────────────────────
  Future<int> _importFlutterSchema(Database srcDb) async {
    int count = 0;

    final metaRows = await _safeQuery(srcDb, 'hart_meta');
    if (metaRows != null) {
      final batch = db.batch();
      batch.delete('hart_meta');
      for (final r in metaRows) {
        batch.insert('hart_meta', {
          'col_name':  r['col_name'],
          'byte_size': r['byte_size'],
          'type_str':  r['type_str'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }

    final dataRows = await _safeQuery(srcDb, 'hart_data');
    if (dataRows != null) {
      final batch = db.batch();
      batch.delete('hart_data');
      for (final r in dataRows) {
        batch.insert('hart_data', {
          'device':    r['device'],
          'col':       r['col'],
          'raw_value': r['raw_value'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
      await batch.commit(noResult: true);
    }

    final mbRows = await _safeQuery(srcDb, 'modbus_data');
    if (mbRows != null) {
      final batch = db.batch();
      batch.delete('modbus_data');
      for (final r in mbRows) {
        batch.insert('modbus_data', {
          'name':      r['name'],
          'byte_size': r['byte_size'],
          'type_str':  r['type_str'],
          'mb_point':  r['mb_point'],
          'address':   r['address'],
          'formula':   r['formula'] ?? r['raw_value'] ?? '',
          'raw_value': r['raw_value'] ?? r['formula'] ?? '',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
      await batch.commit(noResult: true);
    }
    return count;
  }

  // ── Python-schema import ───────────────────────────────────────────────────
  // Python HART_tabela: transposed — rows are columns (NAME=col_name),
  // each device is a separate TEXT column.
  // Python MODBUS_tabela: NAME, BYTE_SIZE, TYPE, MB_POINT, ADDRESS, CLP100
  static const _hartMetaCols = {'NAME', 'BYTE_SIZE', 'TYPE'};

  /// Reads the actual device column names from HART_tabela's schema (PRAGMA),
  /// so we never miss a device that isn't in the hardcoded list.
  Future<List<String>> _detectPythonDevices(Database srcDb) async {
    try {
      final rows = await srcDb.rawQuery('PRAGMA table_info(HART_tabela)');
      return rows
          .map((r) => r['name'] as String)
          .where((name) => !_hartMetaCols.contains(name.toUpperCase()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<int> _importPythonSchema(Database srcDb) async {
    int count = 0;

    // ── HART ────────────────────────────────────────────────────────────────
    final hartRows = await _safeQuery(srcDb, 'HART_tabela');
    if (hartRows != null && hartRows.isNotEmpty) {
      // Detect ALL device columns from the actual schema (not a hardcoded list)
      final deviceCols = await _detectPythonDevices(srcDb);

      final metaBatch = db.batch();
      final dataBatch = db.batch();
      metaBatch.delete('hart_meta');
      dataBatch.delete('hart_data');

      for (final r in hartRows) {
        // Preserve original case from NAME column — do NOT lowercase
        final colName  = (r['NAME'] as String?) ?? '';
        final byteSize = int.tryParse(r['BYTE_SIZE']?.toString() ?? '') ?? 1;
        final typeStr  = (r['TYPE'] as String?) ?? 'UNSIGNED';

        if (colName.isEmpty) continue;

        metaBatch.insert('hart_meta', {
          'col_name':  colName,
          'byte_size': byteSize,
          'type_str':  typeStr,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        for (final dev in deviceCols) {
          final rawVal = r[dev]?.toString() ?? '00';
          dataBatch.insert('hart_data', {
            'device':    dev,
            'col':       colName,
            'raw_value': rawVal,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }

      await metaBatch.commit(noResult: true);
      await dataBatch.commit(noResult: true);
    }

    // ── Modbus ───────────────────────────────────────────────────────────────
    final mbRows = await _safeQuery(srcDb, 'MODBUS_tabela');
    if (mbRows != null) {
      final batch = db.batch();
      batch.delete('modbus_data');
      for (final r in mbRows) {
        final name     = (r['NAME'] as String?) ?? '';
        final byteSize = int.tryParse(r['BYTE_SIZE']?.toString() ?? '') ?? 4;
        final typeStr  = (r['TYPE'] as String?) ?? 'UNSIGNED';
        final mbPoint  = (r['MB_POINT'] as String?) ?? 'ir';
        final address  = (r['ADDRESS'] as String?) ?? '01';
        final formula  = (r['CLP100'] as String?) ?? '00000000';
        if (name.isEmpty) continue;
        batch.insert('modbus_data', {
          'name':      name,
          'byte_size': byteSize,
          'type_str':  typeStr,
          'mb_point':  mbPoint.toLowerCase(),
          'address':   address,
          'formula':   formula,
          'raw_value': formula,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        count++;
      }
      await batch.commit(noResult: true);
    }

    return count;
  }

  Future<List<Map<String, Object?>>?> _safeQuery(
      Database d, String table) async {
    try {
      final tables = await d.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [table]);
      if (tables.isEmpty) return null;
      return d.query(table);
    } catch (_) {
      return null;
    }
  }

  Future<void> close() => _db?.close() ?? Future.value();
}
