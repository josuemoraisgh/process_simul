import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'dart:convert';
import '../templates/db_template.dart';
import '../templates/hart_types_template.dart';
import '../templates/hart_commands_template.dart';

/// Low-level SQLite operations using the sqlite3 package (native FFI).
///
/// Schema:
///   hart_meta     (col_name TEXT PK, byte_size INT, type_str TEXT)
///   hart_data     (device TEXT, col TEXT, raw_value TEXT, PK(device,col))
///   modbus_data   (name TEXT PK, byte_size INT, type_str TEXT,
///                  mb_point TEXT, address TEXT, formula TEXT, raw_value TEXT)
///   hart_enum     (enum_index INT, hex_key TEXT, description TEXT, PK(enum_index,hex_key))
///   hart_bitenum  (bitenum_index INT, hex_mask INT, description TEXT, PK(bitenum_index,hex_mask))
///   hart_commands (command TEXT PK, description TEXT, req_json TEXT, resp_json TEXT, write_json TEXT)
class SqliteDatasource {
  late Database _db;

  // ── Open / init ────────────────────────────────────────────────────────────
  Future<void> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'process_simul.db');
    _db = sqlite3.open(dbPath);
    _db.execute('PRAGMA journal_mode=WAL');
    _db.execute('PRAGMA foreign_keys=ON');
    _onCreate();
  }

  Database get db => _db;

  void _onCreate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS hart_meta (
        col_name  TEXT PRIMARY KEY,
        byte_size INTEGER NOT NULL,
        type_str  TEXT NOT NULL
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS hart_data (
        device    TEXT NOT NULL,
        col       TEXT NOT NULL,
        raw_value TEXT NOT NULL,
        PRIMARY KEY (device, col)
      )
    ''');
    _db.execute('''
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
    _db.execute('''
      CREATE TABLE IF NOT EXISTS hart_enum (
        enum_index  INTEGER NOT NULL,
        hex_key     TEXT NOT NULL,
        description TEXT NOT NULL,
        PRIMARY KEY (enum_index, hex_key)
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS hart_bitenum (
        bitenum_index INTEGER NOT NULL,
        hex_mask      INTEGER NOT NULL,
        description   TEXT NOT NULL,
        PRIMARY KEY (bitenum_index, hex_mask)
      )
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS hart_commands (
        command     TEXT PRIMARY KEY,
        description TEXT NOT NULL,
        req_json    TEXT NOT NULL DEFAULT '[]',
        resp_json   TEXT NOT NULL DEFAULT '[]',
        write_json  TEXT NOT NULL DEFAULT '[]'
      )
    ''');

    // Seed if tables are empty
    final hartMetaCount = _db.select('SELECT COUNT(*) AS c FROM hart_meta');
    if (hartMetaCount.first['c'] as int == 0) _seed();

    final enumCount = _db.select('SELECT COUNT(*) AS c FROM hart_enum');
    if (enumCount.first['c'] as int == 0) _seedEnums();

    final bitEnumCount = _db.select('SELECT COUNT(*) AS c FROM hart_bitenum');
    if (bitEnumCount.first['c'] as int == 0) _seedBitEnums();

    final cmdCount = _db.select('SELECT COUNT(*) AS c FROM hart_commands');
    if (cmdCount.first['c'] as int == 0) _seedCommands();
  }

  void _seed() {
    _db.execute('BEGIN');
    try {
      // Hart meta
      final metaStmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_meta (col_name, byte_size, type_str) VALUES (?, ?, ?)',
      );
      for (final entry in kHartTemplate.entries) {
        final (byteSize, typeStr, _) = entry.value;
        metaStmt.execute([entry.key, byteSize, typeStr]);
      }
      metaStmt.dispose();

      // Hart data
      final dataStmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_data (device, col, raw_value) VALUES (?, ?, ?)',
      );
      for (final entry in kHartTemplate.entries) {
        final (_, _, values) = entry.value;
        for (int i = 0; i < kHartDevices.length; i++) {
          dataStmt.execute([kHartDevices[i], entry.key, values[i]]);
        }
      }
      dataStmt.dispose();

      // Modbus data
      final mbStmt = _db.prepare(
        'INSERT OR IGNORE INTO modbus_data (name, byte_size, type_str, mb_point, address, formula, raw_value) VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      for (final entry in kModbusTemplate.entries) {
        final (byteSize, typeStr, mbPoint, address, formula) = entry.value;
        mbStmt.execute(
            [entry.key, byteSize, typeStr, mbPoint, address, formula, formula]);
      }
      mbStmt.dispose();

      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _seedEnums() {
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_enum (enum_index, hex_key, description) VALUES (?, ?, ?)',
      );
      for (final group in kHartEnumSeed.entries) {
        for (final entry in group.value.entries) {
          stmt.execute([group.key, entry.key, entry.value]);
        }
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _seedBitEnums() {
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_bitenum (bitenum_index, hex_mask, description) VALUES (?, ?, ?)',
      );
      for (final group in kHartBitEnumSeed.entries) {
        for (final entry in group.value.entries) {
          stmt.execute([group.key, entry.key, entry.value]);
        }
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _seedCommands() {
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_commands (command, description, req_json, resp_json, write_json) VALUES (?, ?, ?, ?, ?)',
      );
      for (final entry in kHartCommandsSeed.entries) {
        final m = entry.value;
        stmt.execute([
          entry.key,
          m['description'] as String,
          jsonEncode(m['req']),
          jsonEncode(m['resp']),
          jsonEncode(m['write']),
        ]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ── HART meta queries ─────────────────────────────────────────────────────
  List<Map<String, Object?>> getHartMeta() {
    return _db
        .select('SELECT * FROM hart_meta')
        .map((r) => {
              'col_name': r['col_name'],
              'byte_size': r['byte_size'],
              'type_str': r['type_str'],
            })
        .toList();
  }

  // ── HART data queries ─────────────────────────────────────────────────────
  List<Map<String, Object?>> getHartData() {
    return _db
        .select('SELECT * FROM hart_data')
        .map((r) => {
              'device': r['device'],
              'col': r['col'],
              'raw_value': r['raw_value'],
            })
        .toList();
  }

  void setHartCell(String device, String col, String rawValue) {
    _db.execute(
      'UPDATE hart_data SET raw_value=? WHERE device=? AND col=?',
      [rawValue, device, col],
    );
  }

  String? getHartCell(String device, String col) {
    final rows = _db.select(
      'SELECT raw_value FROM hart_data WHERE device=? AND col=?',
      [device, col],
    );
    return rows.isEmpty ? null : rows.first['raw_value'] as String;
  }

  // ── Modbus queries ────────────────────────────────────────────────────────
  List<Map<String, Object?>> getModbusData() {
    return _db
        .select('SELECT * FROM modbus_data')
        .map((r) => {
              'name': r['name'],
              'byte_size': r['byte_size'],
              'type_str': r['type_str'],
              'mb_point': r['mb_point'],
              'address': r['address'],
              'formula': r['formula'],
              'raw_value': r['raw_value'],
            })
        .toList();
  }

  void setModbusValue(String name, String rawValue) {
    _db.execute(
      'UPDATE modbus_data SET raw_value=? WHERE name=?',
      [rawValue, name],
    );
  }

  // ── HART CRUD ─────────────────────────────────────────────────────────────
  void addHartDevice(
      String deviceName, Map<String, (int, String, String)> colMeta) {
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_data (device, col, raw_value) VALUES (?, ?, ?)',
      );
      for (final entry in colMeta.entries) {
        stmt.execute([deviceName, entry.key, entry.value.$3]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void removeHartDevice(String deviceName) {
    _db.execute('DELETE FROM hart_data WHERE device=?', [deviceName]);
  }

  void addHartColumn(String colName, int byteSize, String typeStr,
      String defaultHex, List<String> devices) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'INSERT OR REPLACE INTO hart_meta (col_name, byte_size, type_str) VALUES (?, ?, ?)',
        [colName, byteSize, typeStr],
      );
      final stmt = _db.prepare(
        'INSERT OR IGNORE INTO hart_data (device, col, raw_value) VALUES (?, ?, ?)',
      );
      for (final dev in devices) {
        stmt.execute([dev, colName, defaultHex]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void removeHartColumn(String colName) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM hart_meta WHERE col_name=?', [colName]);
      _db.execute('DELETE FROM hart_data WHERE col=?', [colName]);
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<String> getHartDevices() {
    final rows = _db.select('SELECT DISTINCT device FROM hart_data');
    return rows.map((r) => r['device'] as String).toList();
  }

  void renameHartDevice(String oldName, String newName) {
    _db.execute(
      'UPDATE hart_data SET device=? WHERE device=?',
      [newName, oldName],
    );
  }

  void editHartColumn(String oldColName, String newColName, int byteSize,
      String typeStr, String defaultHex) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'UPDATE hart_meta SET col_name=?, byte_size=?, type_str=? WHERE col_name=?',
        [newColName, byteSize, typeStr, oldColName],
      );
      if (oldColName != newColName) {
        _db.execute(
            'UPDATE hart_data SET col=? WHERE col=?', [newColName, oldColName]);
      }
      if (defaultHex.isNotEmpty) {
        _db.execute('UPDATE hart_data SET raw_value=? WHERE col=?',
            [defaultHex, newColName]);
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void editModbusVariable(String oldName, String newName, int byteSize,
      String typeStr, String mbPoint, String address, String formula) {
    _db.execute(
      'UPDATE modbus_data SET name=?, byte_size=?, type_str=?, mb_point=?, address=?, formula=?, raw_value=? WHERE name=?',
      [newName, byteSize, typeStr, mbPoint, address, formula, formula, oldName],
    );
  }

  // ── Modbus CRUD ───────────────────────────────────────────────────────────
  void addModbusVariable(String name, int byteSize, String typeStr,
      String mbPoint, String address, String formula) {
    _db.execute(
      'INSERT OR REPLACE INTO modbus_data (name, byte_size, type_str, mb_point, address, formula, raw_value) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [name, byteSize, typeStr, mbPoint, address, formula, formula],
    );
  }

  void removeModbusVariable(String name) {
    _db.execute('DELETE FROM modbus_data WHERE name=?', [name]);
  }

  List<String> getModbusNames() {
    final rows = _db.select('SELECT name FROM modbus_data');
    return rows.map((r) => r['name'] as String).toList();
  }

  // ── HART ENUM CRUD ────────────────────────────────────────────────────────
  /// Returns all enum entries: { enumIndex → { hexKey → description } }
  Map<int, Map<String, String>> getAllEnums() {
    final rows = _db.select(
      'SELECT enum_index, hex_key, description FROM hart_enum ORDER BY enum_index, hex_key',
    );
    final result = <int, Map<String, String>>{};
    for (final r in rows) {
      final idx = r['enum_index'] as int;
      result.putIfAbsent(idx, () => {});
      result[idx]![r['hex_key'] as String] = r['description'] as String;
    }
    return result;
  }

  /// Returns enum entries for a specific index.
  Map<String, String> getEnum(int enumIndex) {
    final rows = _db.select(
      'SELECT hex_key, description FROM hart_enum WHERE enum_index=? ORDER BY hex_key',
      [enumIndex],
    );
    return {
      for (final r in rows) r['hex_key'] as String: r['description'] as String
    };
  }

  /// Returns all distinct enum indices.
  List<int> getEnumIndices() {
    final rows = _db.select(
        'SELECT DISTINCT enum_index FROM hart_enum ORDER BY enum_index');
    return rows.map((r) => r['enum_index'] as int).toList();
  }

  void addEnumEntry(int enumIndex, String hexKey, String description) {
    _db.execute(
      'INSERT OR REPLACE INTO hart_enum (enum_index, hex_key, description) VALUES (?, ?, ?)',
      [enumIndex, hexKey, description],
    );
  }

  void removeEnumEntry(int enumIndex, String hexKey) {
    _db.execute(
      'DELETE FROM hart_enum WHERE enum_index=? AND hex_key=?',
      [enumIndex, hexKey],
    );
  }

  void removeEnumGroup(int enumIndex) {
    _db.execute('DELETE FROM hart_enum WHERE enum_index=?', [enumIndex]);
  }

  void updateEnumEntry(int enumIndex, String hexKey, String description) {
    _db.execute(
      'UPDATE hart_enum SET description=? WHERE enum_index=? AND hex_key=?',
      [description, enumIndex, hexKey],
    );
  }

  // ── HART BIT_ENUM CRUD ────────────────────────────────────────────────────
  /// Returns all bitenum entries: { bitEnumIndex → { hexMask → description } }
  Map<int, Map<int, String>> getAllBitEnums() {
    final rows = _db.select(
      'SELECT bitenum_index, hex_mask, description FROM hart_bitenum ORDER BY bitenum_index, hex_mask',
    );
    final result = <int, Map<int, String>>{};
    for (final r in rows) {
      final idx = r['bitenum_index'] as int;
      result.putIfAbsent(idx, () => {});
      result[idx]![r['hex_mask'] as int] = r['description'] as String;
    }
    return result;
  }

  Map<int, String> getBitEnum(int bitEnumIndex) {
    final rows = _db.select(
      'SELECT hex_mask, description FROM hart_bitenum WHERE bitenum_index=? ORDER BY hex_mask',
      [bitEnumIndex],
    );
    return {
      for (final r in rows) r['hex_mask'] as int: r['description'] as String
    };
  }

  List<int> getBitEnumIndices() {
    final rows = _db.select(
        'SELECT DISTINCT bitenum_index FROM hart_bitenum ORDER BY bitenum_index');
    return rows.map((r) => r['bitenum_index'] as int).toList();
  }

  void addBitEnumEntry(int bitEnumIndex, int hexMask, String description) {
    _db.execute(
      'INSERT OR REPLACE INTO hart_bitenum (bitenum_index, hex_mask, description) VALUES (?, ?, ?)',
      [bitEnumIndex, hexMask, description],
    );
  }

  void removeBitEnumEntry(int bitEnumIndex, int hexMask) {
    _db.execute(
      'DELETE FROM hart_bitenum WHERE bitenum_index=? AND hex_mask=?',
      [bitEnumIndex, hexMask],
    );
  }

  void removeBitEnumGroup(int bitEnumIndex) {
    _db.execute(
        'DELETE FROM hart_bitenum WHERE bitenum_index=?', [bitEnumIndex]);
  }

  void updateBitEnumEntry(int bitEnumIndex, int hexMask, String description) {
    _db.execute(
      'UPDATE hart_bitenum SET description=? WHERE bitenum_index=? AND hex_mask=?',
      [description, bitEnumIndex, hexMask],
    );
  }

  // ── HART COMMANDS CRUD ────────────────────────────────────────────────────
  /// Returns all commands: { command → { description, req, resp, write } }
  Map<String, Map<String, dynamic>> getAllCommands() {
    final rows = _db.select(
      'SELECT command, description, req_json, resp_json, write_json FROM hart_commands ORDER BY command',
    );
    final result = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      result[r['command'] as String] = {
        'description': r['description'] as String,
        'req': jsonDecode(r['req_json'] as String) as List<dynamic>,
        'resp': jsonDecode(r['resp_json'] as String) as List<dynamic>,
        'write': jsonDecode(r['write_json'] as String) as List<dynamic>,
      };
    }
    return result;
  }

  Map<String, dynamic>? getCommand(String command) {
    final rows = _db.select(
      'SELECT description, req_json, resp_json, write_json FROM hart_commands WHERE command=?',
      [command],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'description': r['description'] as String,
      'req': jsonDecode(r['req_json'] as String) as List<dynamic>,
      'resp': jsonDecode(r['resp_json'] as String) as List<dynamic>,
      'write': jsonDecode(r['write_json'] as String) as List<dynamic>,
    };
  }

  List<String> getCommandKeys() {
    final rows =
        _db.select('SELECT command FROM hart_commands ORDER BY command');
    return rows.map((r) => r['command'] as String).toList();
  }

  void addCommand(String command, String description, List<String> req,
      List<String> resp, List<String> write) {
    _db.execute(
      'INSERT OR REPLACE INTO hart_commands (command, description, req_json, resp_json, write_json) VALUES (?, ?, ?, ?, ?)',
      [
        command,
        description,
        jsonEncode(req),
        jsonEncode(resp),
        jsonEncode(write)
      ],
    );
  }

  void updateCommand(String command, String description, List<String> req,
      List<String> resp, List<String> write) {
    _db.execute(
      'UPDATE hart_commands SET description=?, req_json=?, resp_json=?, write_json=? WHERE command=?',
      [
        description,
        jsonEncode(req),
        jsonEncode(resp),
        jsonEncode(write),
        command
      ],
    );
  }

  void removeCommand(String command) {
    _db.execute('DELETE FROM hart_commands WHERE command=?', [command]);
  }

  // ── XLS Import ────────────────────────────────────────────────────────────
  /// Imports HART and Modbus data from an XLSX file.
  /// Returns the number of rows imported.
  int importFromXls(String sourcePath) {
    final bytes = File(sourcePath).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    int count = 0;

    // ── HART sheet ──────────────────────────────────────────────────────
    final hartSheet = excel.tables['HART'] ?? excel.tables['HART_tabela'];
    if (hartSheet != null && hartSheet.rows.length > 1) {
      final headers =
          hartSheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();

      // Detect meta columns
      final nameIdx = headers.indexWhere((h) => h.toUpperCase() == 'NAME');
      final sizeIdx = headers.indexWhere((h) => h.toUpperCase() == 'BYTE_SIZE');
      final typeIdx = headers.indexWhere((h) => h.toUpperCase() == 'TYPE');

      if (nameIdx >= 0 && sizeIdx >= 0 && typeIdx >= 0) {
        // Device columns are everything that's not NAME/BYTE_SIZE/TYPE
        final metaCols = {nameIdx, sizeIdx, typeIdx};
        final deviceCols = <int, String>{};
        for (int i = 0; i < headers.length; i++) {
          if (!metaCols.contains(i) && headers[i].isNotEmpty) {
            deviceCols[i] = headers[i];
          }
        }

        _db.execute('BEGIN');
        try {
          _db.execute('DELETE FROM hart_meta');
          _db.execute('DELETE FROM hart_data');

          final metaStmt = _db.prepare(
            'INSERT OR REPLACE INTO hart_meta (col_name, byte_size, type_str) VALUES (?, ?, ?)',
          );
          final dataStmt = _db.prepare(
            'INSERT OR REPLACE INTO hart_data (device, col, raw_value) VALUES (?, ?, ?)',
          );

          for (int row = 1; row < hartSheet.rows.length; row++) {
            final cells = hartSheet.rows[row];
            final colName = cells.length > nameIdx
                ? (cells[nameIdx]?.value?.toString() ?? '')
                : '';
            if (colName.isEmpty) continue;
            final byteSize = cells.length > sizeIdx
                ? (int.tryParse(cells[sizeIdx]?.value?.toString() ?? '') ?? 1)
                : 1;
            final typeStr = cells.length > typeIdx
                ? (cells[typeIdx]?.value?.toString() ?? 'UNSIGNED')
                : 'UNSIGNED';

            metaStmt.execute([colName, byteSize, typeStr]);

            for (final dEntry in deviceCols.entries) {
              final rawVal = cells.length > dEntry.key
                  ? (cells[dEntry.key]?.value?.toString() ?? '00')
                  : '00';
              dataStmt.execute([dEntry.value, colName, rawVal]);
              count++;
            }
          }

          metaStmt.dispose();
          dataStmt.dispose();
          _db.execute('COMMIT');
        } catch (e) {
          _db.execute('ROLLBACK');
          rethrow;
        }
      }
    }

    // ── Modbus sheet ────────────────────────────────────────────────────
    final mbSheet = excel.tables['MODBUS'] ?? excel.tables['MODBUS_tabela'];
    if (mbSheet != null && mbSheet.rows.length > 1) {
      final headers = mbSheet.rows.first
          .map((c) => c?.value?.toString().toUpperCase() ?? '')
          .toList();

      int col(String name) => headers.indexOf(name);
      final ni = col('NAME');
      final si = col('BYTE_SIZE');
      final ti = col('TYPE');
      final pi = col('MB_POINT');
      final ai = col('ADDRESS');

      // The formula column could be 'CLP100' or 'FORMULA'
      var fi = col('FORMULA');
      if (fi < 0) fi = col('CLP100');

      if (ni >= 0) {
        _db.execute('BEGIN');
        try {
          _db.execute('DELETE FROM modbus_data');
          final stmt = _db.prepare(
            'INSERT OR REPLACE INTO modbus_data (name, byte_size, type_str, mb_point, address, formula, raw_value) VALUES (?, ?, ?, ?, ?, ?, ?)',
          );
          for (int row = 1; row < mbSheet.rows.length; row++) {
            final cells = mbSheet.rows[row];
            String cell(int i) => (i >= 0 && cells.length > i)
                ? (cells[i]?.value?.toString() ?? '')
                : '';
            final name = cell(ni);
            if (name.isEmpty) continue;
            final byteSize = int.tryParse(cell(si)) ?? 4;
            final typeStr = cell(ti).isEmpty ? 'UNSIGNED' : cell(ti);
            final mbPoint = cell(pi).isEmpty ? 'ir' : cell(pi).toLowerCase();
            final address = cell(ai).isEmpty ? '01' : cell(ai);
            final formula = cell(fi).isEmpty ? '00000000' : cell(fi);
            stmt.execute(
                [name, byteSize, typeStr, mbPoint, address, formula, formula]);
            count++;
          }
          stmt.dispose();
          _db.execute('COMMIT');
        } catch (e) {
          _db.execute('ROLLBACK');
          rethrow;
        }
      }
    }

    // ── ENUM sheet (optional) ───────────────────────────────────────────
    final enumSheet = excel.tables['ENUM'];
    if (enumSheet != null && enumSheet.rows.length > 1) {
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM hart_enum');
        final stmt = _db.prepare(
          'INSERT OR REPLACE INTO hart_enum (enum_index, hex_key, description) VALUES (?, ?, ?)',
        );
        for (int row = 1; row < enumSheet.rows.length; row++) {
          final cells = enumSheet.rows[row];
          if (cells.length < 3) continue;
          final idx = int.tryParse(cells[0]?.value?.toString() ?? '');
          if (idx == null) continue;
          stmt.execute([
            idx,
            cells[1]?.value?.toString() ?? '',
            cells[2]?.value?.toString() ?? ''
          ]);
        }
        stmt.dispose();
        _db.execute('COMMIT');
      } catch (e) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }

    // ── BIT_ENUM sheet (optional) ───────────────────────────────────────
    final bitSheet = excel.tables['BIT_ENUM'];
    if (bitSheet != null && bitSheet.rows.length > 1) {
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM hart_bitenum');
        final stmt = _db.prepare(
          'INSERT OR REPLACE INTO hart_bitenum (bitenum_index, hex_mask, description) VALUES (?, ?, ?)',
        );
        for (int row = 1; row < bitSheet.rows.length; row++) {
          final cells = bitSheet.rows[row];
          if (cells.length < 3) continue;
          final idx = int.tryParse(cells[0]?.value?.toString() ?? '');
          final mask = int.tryParse(cells[1]?.value?.toString() ?? '');
          if (idx == null || mask == null) continue;
          stmt.execute([idx, mask, cells[2]?.value?.toString() ?? '']);
        }
        stmt.dispose();
        _db.execute('COMMIT');
      } catch (e) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }

    // ── COMMANDS sheet (optional) ───────────────────────────────────────
    final cmdSheet = excel.tables['COMMANDS'];
    if (cmdSheet != null && cmdSheet.rows.length > 1) {
      _db.execute('BEGIN');
      try {
        _db.execute('DELETE FROM hart_commands');
        final stmt = _db.prepare(
          'INSERT OR REPLACE INTO hart_commands (command, description, req_json, resp_json, write_json) VALUES (?, ?, ?, ?, ?)',
        );
        for (int row = 1; row < cmdSheet.rows.length; row++) {
          final cells = cmdSheet.rows[row];
          if (cells.length < 5) continue;
          final cmd = cells[0]?.value?.toString() ?? '';
          if (cmd.isEmpty) continue;
          stmt.execute([
            cmd,
            cells[1]?.value?.toString() ?? '',
            cells[2]?.value?.toString() ?? '[]',
            cells[3]?.value?.toString() ?? '[]',
            cells[4]?.value?.toString() ?? '[]',
          ]);
        }
        stmt.dispose();
        _db.execute('COMMIT');
      } catch (e) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }

    return count;
  }

  // ── XLS Export ────────────────────────────────────────────────────────────
  /// Exports all data to an XLSX file at [destPath].
  void exportToXls(String destPath) {
    final excel = Excel.createExcel();

    // ── HART sheet ──────────────────────────────────────────────────────
    final hartSheet = excel['HART'];
    final meta = getHartMeta();
    final devices = getHartDevices();

    // Header row
    hartSheet.appendRow([
      TextCellValue('NAME'),
      TextCellValue('BYTE_SIZE'),
      TextCellValue('TYPE'),
      ...devices.map((d) => TextCellValue(d)),
    ]);

    for (final m in meta) {
      final colName = m['col_name'] as String;
      final byteSize = m['byte_size'] as int;
      final typeStr = m['type_str'] as String;

      final row = <CellValue>[
        TextCellValue(colName),
        IntCellValue(byteSize),
        TextCellValue(typeStr),
      ];
      for (final dev in devices) {
        final val = getHartCell(dev, colName) ?? '00';
        row.add(TextCellValue(val));
      }
      hartSheet.appendRow(row);
    }

    // ── Modbus sheet ────────────────────────────────────────────────────
    final mbSheet = excel['MODBUS'];
    mbSheet.appendRow([
      TextCellValue('NAME'),
      TextCellValue('BYTE_SIZE'),
      TextCellValue('TYPE'),
      TextCellValue('MB_POINT'),
      TextCellValue('ADDRESS'),
      TextCellValue('FORMULA'),
    ]);
    for (final r in getModbusData()) {
      mbSheet.appendRow([
        TextCellValue(r['name'] as String),
        IntCellValue(r['byte_size'] as int),
        TextCellValue(r['type_str'] as String),
        TextCellValue(r['mb_point'] as String),
        TextCellValue(r['address'] as String),
        TextCellValue(r['formula'] as String),
      ]);
    }

    // ── ENUM sheet ──────────────────────────────────────────────────────
    final enumSheet = excel['ENUM'];
    enumSheet.appendRow([
      TextCellValue('ENUM_INDEX'),
      TextCellValue('HEX_KEY'),
      TextCellValue('DESCRIPTION'),
    ]);
    final enums = getAllEnums();
    for (final group in enums.entries) {
      for (final entry in group.value.entries) {
        enumSheet.appendRow([
          IntCellValue(group.key),
          TextCellValue(entry.key),
          TextCellValue(entry.value),
        ]);
      }
    }

    // ── BIT_ENUM sheet ──────────────────────────────────────────────────
    final bitSheet = excel['BIT_ENUM'];
    bitSheet.appendRow([
      TextCellValue('BITENUM_INDEX'),
      TextCellValue('HEX_MASK'),
      TextCellValue('DESCRIPTION'),
    ]);
    final bitEnums = getAllBitEnums();
    for (final group in bitEnums.entries) {
      for (final entry in group.value.entries) {
        bitSheet.appendRow([
          IntCellValue(group.key),
          IntCellValue(entry.key),
          TextCellValue(entry.value),
        ]);
      }
    }

    // ── COMMANDS sheet ──────────────────────────────────────────────────
    final cmdExSheet = excel['COMMANDS'];
    cmdExSheet.appendRow([
      TextCellValue('COMMAND'),
      TextCellValue('DESCRIPTION'),
      TextCellValue('REQ_JSON'),
      TextCellValue('RESP_JSON'),
      TextCellValue('WRITE_JSON'),
    ]);
    final cmds = getAllCommands();
    for (final entry in cmds.entries) {
      final m = entry.value;
      cmdExSheet.appendRow([
        TextCellValue(entry.key),
        TextCellValue(m['description'] as String),
        TextCellValue(jsonEncode(m['req'])),
        TextCellValue(jsonEncode(m['resp'])),
        TextCellValue(jsonEncode(m['write'])),
      ]);
    }

    // Remove default "Sheet1" created by Excel package
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      File(destPath).writeAsBytesSync(fileBytes);
    }
  }

  void close() => _db.dispose();
}
