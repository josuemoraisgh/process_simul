import '../enums/db_model.dart';

/// A single reactive cell in the HART or Modbus table.
///
/// [rawValue] stores exactly what is persisted in SQLite:
///   - plain hex string  → DbModel.value
///   - "@expr"           → DbModel.func  (expression)
///   - "$spec"           → DbModel.tFunc (transfer-function spec)
class ReactVar {
  final String tableName;
  final String rowName;
  final String colName;
  final int byteSize;
  final String typeStr;

  String _rawValue;

  ReactVar({
    required this.tableName,
    required this.rowName,
    required this.colName,
    required this.byteSize,
    required this.typeStr,
    required String rawValue,
  }) : _rawValue = rawValue;

  // ── Accessors ────────────────────────────────────────────────────────────
  String get rawValue => _rawValue;

  DbModel get model {
    if (_rawValue.startsWith('@')) return DbModel.func;
    if (_rawValue.startsWith(r'$')) return DbModel.tFunc;
    return DbModel.value;
  }

  /// The hex string to use for HART protocol responses.
  /// For func/tFunc cells, the *last evaluated* hex is stored in [evaluatedHex].
  String _evaluatedHex = '';
  String get evaluatedHex => _evaluatedHex.isEmpty ? _rawValue : _evaluatedHex;

  // ── Mutators ─────────────────────────────────────────────────────────────
  void setRawValue(String v) => _rawValue = v;
  void setEvaluatedHex(String hex) => _evaluatedHex = hex;

  // ── Expression helpers ───────────────────────────────────────────────────
  /// Expression body (without leading '@').
  String get funcBody => model == DbModel.func ? _rawValue.substring(1) : '';

  /// Transfer-function spec body (without leading '$').
  String get tFuncBody => model == DbModel.tFunc ? _rawValue.substring(1) : '';

  @override
  String toString() =>
      'ReactVar($tableName.$rowName.$colName [$typeStr] = $_rawValue)';
}
