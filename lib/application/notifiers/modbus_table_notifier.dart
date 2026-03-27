import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/repositories/i_db_repository.dart';

/// Immutable view-model for the Modbus table.
/// Each entry: name → (byteSize, typeStr, mbPoint, address, formula)
class ModbusTableState {
  final Map<String, (int, String, String, String, String)> data;
  final bool loading;
  final String? error;

  const ModbusTableState({
    this.data = const {},
    this.loading = true,
    this.error,
  });

  ModbusTableState copyWith({
    Map<String, (int, String, String, String, String)>? data,
    bool? loading,
    String? error,
  }) {
    return ModbusTableState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class ModbusTableNotifier extends StateNotifier<ModbusTableState> {
  final IDbRepository _repo;

  ModbusTableNotifier(this._repo) : super(const ModbusTableState());

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> load() async {
    try {
      state = state.copyWith(loading: true, error: null);
      final tableData = await _repo.getTable('MODBUS');
      final data = <String, (int, String, String, String, String)>{};
      for (final entry in tableData.entries) {
        final cols = entry.value;
        final byteSize =
            int.tryParse(cols['byte_size']?.rawValue ?? '4') ?? 4;
        final typeStr = cols['type_str']?.rawValue ?? 'UNSIGNED';
        final mbPoint = cols['mb_point']?.rawValue ?? 'ir';
        final address = cols['address']?.rawValue ?? '01';
        final formula = cols['formula']?.rawValue ?? '';
        data[entry.key] = (byteSize, typeStr, mbPoint, address, formula);
      }
      state = state.copyWith(data: data, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<void> addVariable(String name, int byteSize, String typeStr,
      String mbPoint, String address, String formula) async {
    await _repo.addModbusVariable(
        name, byteSize, typeStr, mbPoint, address, formula);
    await load();
  }

  Future<void> removeVariable(String name) async {
    await _repo.removeModbusVariable(name);
    await load();
  }
}
