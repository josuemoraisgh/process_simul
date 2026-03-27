import 'dart:async';
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

  const HartTableState({
    this.data = const {},
    this.devices = const [],
    this.visibleCols = const [],
    this.showHuman = true,
    this.loading = true,
    this.error,
  });

  HartTableState copyWith({
    Map<String, Map<String, ReactVar>>? data,
    List<String>? devices,
    List<String>? visibleCols,
    bool? showHuman,
    bool? loading,
    String? error,
  }) {
    return HartTableState(
      data: data ?? this.data,
      devices: devices ?? this.devices,
      visibleCols: visibleCols ?? this.visibleCols,
      showHuman: showHuman ?? this.showHuman,
      loading: loading ?? this.loading,
      error: error,
    );
  }

  /// Returns the display value for a given cell.
  String cellDisplay(String device, String col) {
    final v = data[device]?[col];
    if (v == null) return '';
    final hex = v.model == DbModel.value
        ? v.rawValue
        : (v.evaluatedHex.isEmpty ? '?' : v.evaluatedHex);
    if (!showHuman) return hex.toUpperCase();
    return HartTypeConverter.hexToHuman(hex, v.typeStr);
  }

  DbModel cellModel(String device, String col) =>
      data[device]?[col]?.model ?? DbModel.value;
}

/// Manages the HART table state, expression evaluation, and TF simulation.
class HartTableNotifier extends StateNotifier<HartTableState> {
  final IDbRepository _repo;
  final SimulTf _simul;
  Timer? _evalTimer;

  HartTableNotifier(this._repo, this._simul)
      : super(const HartTableState());

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> load() async {
    try {
      state = state.copyWith(loading: true, error: null);
      final data = await _repo.getTable('HART');
      final devices = await _repo.rowKeys('HART');
      final allCols = await _repo.colKeys('HART');
      final visibleCols = _visibleSubset(allCols);

      state = state.copyWith(
        data: data,
        devices: devices,
        visibleCols: visibleCols,
        loading: false,
      );

      _evaluateAll();
      _startEvalTimer();
      _registerTFuncs();
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  // ── Cell edit ──────────────────────────────────────────────────────────────
  Future<void> setCellValue(
      String device, String col, String rawValue) async {
    await _repo.setRawValue('HART', device, col, rawValue);
    final v = state.data[device]?[col];
    if (v != null) {
      v.setRawValue(rawValue);
      v.setEvaluatedHex('');
    }
    // Re-evaluate and notify
    _evaluateAll();
    state = state.copyWith(data: Map.from(state.data));
  }

  // ── Visualisation toggle ───────────────────────────────────────────────────
  void toggleDisplay() {
    state = state.copyWith(showHuman: !state.showHuman);
  }

  void setShowHuman(bool v) => state = state.copyWith(showHuman: v);

  // ── Expression evaluation ──────────────────────────────────────────────────
  void _evaluateAll() {
    for (final device in state.data.values) {
      for (final v in device.values) {
        if (v.model == DbModel.func) {
          _evalFunc(v);
        }
      }
    }
  }

  void _evalFunc(ReactVar v) {
    try {
      final result = HartTransmitter.evaluateExpr(
        v.funcBody,
        state.data,
      );
      // Convert back to hex based on type
      final hex = v.typeStr.toUpperCase().contains('FLOAT') || v.typeStr == 'SREAL'
          ? HartTypeConverter.doubleToHex(result)
          : result.truncate().toRadixString(16).padLeft(v.byteSize * 2, '0').toUpperCase();
      v.setEvaluatedHex(hex);
    } catch (_) {
      v.setEvaluatedHex('7FC00000'); // NaN float
    }
  }

  void _startEvalTimer() {
    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _evaluateAll();
      // Trigger UI rebuild
      state = state.copyWith(data: state.data);
    });
  }

  void _registerTFuncs() {
    _simul.stop();
    _simul.reset();
    for (final entry in state.data.entries) {
      final device = entry.key;
      for (final v in entry.value.values) {
        if (v.model == DbModel.tFunc) {
          _simul.register(v, () {
            // Input: percent_of_range for this device
            final por = state.data[device]?['percent_of_range'];
            if (por == null) return 0.0;
            final hex = por.model == DbModel.value ? por.rawValue : por.evaluatedHex;
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

  Future<void> addColumn(String colName, int byteSize, String typeStr,
      String defaultHex) async {
    await _repo.addHartColumn(colName, byteSize, typeStr, defaultHex);
    await load();
  }

  Future<void> removeColumn(String colName) async {
    await _repo.removeHartColumn(colName);
    await load();
  }

  // ── Column helpers ─────────────────────────────────────────────────────────
  static List<String> _visibleSubset(List<String> all) {
    const preferred = [
      'error_code', 'device_status', 'polling_address',
      'tag', 'message', 'descriptor', 'date',
      'PROCESS_VARIABLE', 'percent_of_range', 'loop_current',
      'upper_range_value', 'lower_range_value', 'process_variable_unit_code',
    ];
    final available = all.toSet();
    return preferred.where(available.contains).toList();
  }

  @override
  void dispose() {
    _evalTimer?.cancel();
    _simul.stop();
    super.dispose();
  }
}
