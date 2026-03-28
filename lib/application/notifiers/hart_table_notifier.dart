import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/react_var.dart';
import '../../domain/enums/db_model.dart';
import '../../domain/repositories/i_db_repository.dart';
import '../../infrastructure/hart/hart_type_converter.dart';
import '../../infrastructure/hart/hart_transmitter.dart';
import '../../infrastructure/simulation/simul_tf.dart';

/// Immutable view-model for the HART table.
class HartTableState {
  final Map<String, Map<String, ReactVar>> data; // device → col → var
  final List<String> devices;
  final List<String> visibleCols;
  final bool showHuman; // true = engineering units, false = hex
  final bool loading;
  final String? error;
  final Map<int, Map<String, String>> enumMaps; // enumIndex → { hexKey → desc }
  final Map<int, Map<int, String>>
      bitEnumMaps; // bitEnumIndex → { mask → desc }
  final int dataVersion; // incremented only on real data changes

  const HartTableState({
    this.data = const {},
    this.devices = const [],
    this.visibleCols = const [],
    this.showHuman = true,
    this.loading = true,
    this.error,
    this.enumMaps = const {},
    this.bitEnumMaps = const {},
    this.dataVersion = 0,
  });

  HartTableState copyWith({
    Map<String, Map<String, ReactVar>>? data,
    List<String>? devices,
    List<String>? visibleCols,
    bool? showHuman,
    bool? loading,
    String? error,
    Map<int, Map<String, String>>? enumMaps,
    Map<int, Map<int, String>>? bitEnumMaps,
    int? dataVersion,
  }) {
    return HartTableState(
      data: data ?? this.data,
      devices: devices ?? this.devices,
      visibleCols: visibleCols ?? this.visibleCols,
      showHuman: showHuman ?? this.showHuman,
      loading: loading ?? this.loading,
      error: error,
      enumMaps: enumMaps ?? this.enumMaps,
      bitEnumMaps: bitEnumMaps ?? this.bitEnumMaps,
      dataVersion: dataVersion ?? this.dataVersion,
    );
  }

  /// Returns the display value for a given cell.
  String cellDisplay(String device, String col) {
    final v = data[device]?[col];
    if (v == null) return '';
    final hex = v.model == DbModel.value
        ? v.rawValue
        : (v.hasEvaluated ? v.evaluatedHex : '?');
    if (!showHuman) return hex.toUpperCase();

    final t = v.typeStr.toUpperCase();
    Map<String, String>? eMap;
    Map<int, String>? bMap;
    if (t.contains('BIT_ENUM')) {
      final idx = HartTypeConverter.parseBitEnumIndex(t);
      if (idx >= 0) bMap = bitEnumMaps[idx];
    } else if (t.contains('ENUM')) {
      final idx = HartTypeConverter.parseEnumIndex(t);
      if (idx >= 0) eMap = enumMaps[idx];
    }
    return HartTypeConverter.hexToHuman(hex, v.typeStr,
        enumMap: eMap, bitEnumMap: bMap);
  }

  DbModel cellModel(String device, String col) =>
      data[device]?[col]?.model ?? DbModel.value;
}

/// Manages the HART table state, expression evaluation, and TF simulation.
class HartTableNotifier extends StateNotifier<HartTableState> {
  final IDbRepository _repo;
  final SimulTf _simul;
  Timer? _evalTimer;
  bool _dirty = false;
  int _dataVersion = 0;

  /// Per-cell notifiers: only the cells whose display changed get rebuilt.
  final Map<String, ValueNotifier<String>> _cellNotifiers = {};

  /// Incremented whenever cell values change (for external listeners like Modbus).
  final ValueNotifier<int> dataVersionNotifier = ValueNotifier<int>(0);

  HartTableNotifier(this._repo, this._simul) : super(const HartTableState());

  /// Returns (or creates) a ValueNotifier for a single cell's display text.
  /// Widgets should wrap their display in [ValueListenableBuilder] with this.
  ValueNotifier<String> cellNotifier(String device, String col) {
    final key = '$device\x00$col';
    return _cellNotifiers.putIfAbsent(
      key,
      () => ValueNotifier<String>(state.cellDisplay(device, col)),
    );
  }

  /// Updates only the ValueNotifiers whose display actually changed.
  void _refreshCellNotifiers() {
    for (final dEntry in state.data.entries) {
      for (final cEntry in dEntry.value.entries) {
        final key = '${dEntry.key}\x00${cEntry.key}';
        final n = _cellNotifiers[key];
        if (n != null) {
          final display = state.cellDisplay(dEntry.key, cEntry.key);
          if (n.value != display) n.value = display;
        }
      }
    }
  }

  /// Forces ALL existing cell notifiers to recompute (e.g. after showHuman toggle).
  void _refreshAllCellNotifiers() {
    for (final entry in _cellNotifiers.entries) {
      final sep = entry.key.indexOf('\x00');
      if (sep < 0) continue;
      final device = entry.key.substring(0, sep);
      final col = entry.key.substring(sep + 1);
      entry.value.value = state.cellDisplay(device, col);
    }
  }

  /// Disposes all cell notifiers (called before a full reload).
  void _clearCellNotifiers() {
    for (final n in _cellNotifiers.values) {
      n.dispose();
    }
    _cellNotifiers.clear();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> load() async {
    try {
      _clearCellNotifiers();
      state = state.copyWith(loading: true, error: null);
      final data = await _repo.getTable('HART');
      final devices = await _repo.rowKeys('HART');
      final allCols = await _repo.colKeys('HART');
      final visibleCols = _visibleSubset(allCols);
      final enumMaps = _repo.getAllEnums();
      final bitEnumMaps = _repo.getAllBitEnums();

      state = state.copyWith(
        data: data,
        devices: devices,
        visibleCols: visibleCols,
        loading: false,
        enumMaps: enumMaps,
        bitEnumMaps: bitEnumMaps,
      );

      _evaluateAll();
      _startEvalTimer();
      _registerTFuncs();
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  // ── Cell edit ──────────────────────────────────────────────────────────────
  Future<void> setCellValue(String device, String col, String rawValue) async {
    await _repo.setRawValue('HART', device, col, rawValue);
    final v = state.data[device]?[col];
    if (v != null) {
      v.setRawValue(rawValue);
      v.setEvaluatedHex('');
    }
    _evaluateAll();
    _refreshCellNotifiers();
    _dataVersion++;
    dataVersionNotifier.value = _dataVersion;
    // Emit state so model/prefix changes (value↔func↔tFunc) propagate.
    state =
        state.copyWith(data: Map.from(state.data), dataVersion: _dataVersion);
  }

  // ── Visualisation toggle ───────────────────────────────────────────────────
  void toggleDisplay() {
    state = state.copyWith(showHuman: !state.showHuman);
    _refreshAllCellNotifiers();
  }

  void setShowHuman(bool v) {
    state = state.copyWith(showHuman: v);
    _refreshAllCellNotifiers();
  }

  // ── Expression evaluation ──────────────────────────────────────────────────
  /// Re-evaluates all @func cells. Returns `true` when any value changed.
  bool _evaluateAll() {
    bool anyChanged = false;
    for (final device in state.data.values) {
      for (final v in device.values) {
        if (v.model == DbModel.func) {
          if (_evalFunc(v)) anyChanged = true;
        }
      }
    }
    return anyChanged;
  }

  /// Returns `true` when the evaluated hex actually changed.
  bool _evalFunc(ReactVar v) {
    try {
      final result = HartTransmitter.evaluateExpr(
        v.funcBody,
        state.data,
      );
      // Convert back to hex based on type
      final hex =
          v.typeStr.toUpperCase().contains('FLOAT') || v.typeStr == 'SREAL'
              ? HartTypeConverter.doubleToHex(result)
              : result
                  .truncate()
                  .toRadixString(16)
                  .padLeft(v.byteSize * 2, '0')
                  .toUpperCase();
      return v.setEvaluatedHex(hex);
    } catch (_) {
      return v.setEvaluatedHex('7FC00000'); // NaN float
    }
  }

  void _startEvalTimer() {
    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final funcChanged = _evaluateAll();
      // Value-only changes: update per-cell notifiers without emitting state.
      // This avoids rebuilding the entire table widget tree.
      if (funcChanged || _dirty) {
        _dirty = false;
        _dataVersion++;
        dataVersionNotifier.value = _dataVersion;
        _refreshCellNotifiers();
      }
    });
  }

  void _registerTFuncs() {
    _simul.stop();
    _simul.reset();
    _simul.onChanged = () => _dirty = true;
    for (final entry in state.data.entries) {
      final device = entry.key;
      for (final v in entry.value.values) {
        if (v.model == DbModel.tFunc) {
          _simul.register(v, () {
            // Input: percent_of_range for this device
            final por = state.data[device]?['percent_of_range'];
            if (por == null) return 0.0;
            final hex =
                por.model == DbModel.value ? por.rawValue : por.evaluatedHex;
            return HartTypeConverter.hexToDouble(hex);
          });
        }
      }
    }
    _simul.start();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────────
  Future<void> addDevice(String deviceName) async {
    await _repo.addHartDevice(deviceName);
    await load();
  }

  Future<void> removeDevice(String deviceName) async {
    await _repo.removeHartDevice(deviceName);
    await load();
  }

  Future<void> addColumn(
      String colName, int byteSize, String typeStr, String defaultHex) async {
    await _repo.addHartColumn(colName, byteSize, typeStr, defaultHex);
    await load();
  }

  Future<void> removeColumn(String colName) async {
    await _repo.removeHartColumn(colName);
    await load();
  }

  Future<void> editDevice(String oldName, String newName) async {
    await _repo.renameHartDevice(oldName, newName);
    await load();
  }

  Future<void> editColumn(String oldName, String newName, int byteSize,
      String typeStr, String defaultHex) async {
    await _repo.editHartColumn(oldName, newName, byteSize, typeStr, defaultHex);
    await load();
  }

  // ── Column helpers ─────────────────────────────────────────────────────────
  /// Returns ALL columns from [all], with the preferred key-columns first
  /// (case-insensitive match), followed by the remaining columns in order.
  static List<String> _visibleSubset(List<String> all) {
    const preferred = [
      'error_code',
      'device_status',
      'polling_address',
      'tag',
      'message',
      'descriptor',
      'date',
      'PROCESS_VARIABLE',
      'process_variable',
      'percent_of_range',
      'loop_current',
      'upper_range_value',
      'lower_range_value',
      'process_variable_unit_code',
    ];
    final preferredLower = preferred.map((p) => p.toLowerCase()).toSet();
    final result = <String>[];
    final rest = <String>[];

    for (final col in all) {
      if (preferredLower.contains(col.toLowerCase())) {
        result.add(col);
      } else {
        rest.add(col);
      }
    }

    // Sort result in preferred order (case-insensitive)
    result.sort((a, b) {
      final ai = preferredLower.toList().indexOf(a.toLowerCase());
      final bi = preferredLower.toList().indexOf(b.toLowerCase());
      return ai.compareTo(bi);
    });

    return [...result, ...rest];
  }

  @override
  void dispose() {
    _evalTimer?.cancel();
    _simul.stop();
    _simul.onChanged = null;
    _clearCellNotifiers();
    dataVersionNotifier.dispose();
    super.dispose();
  }
}
