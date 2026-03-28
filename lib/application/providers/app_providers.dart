import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/sqlite_datasource.dart';
import '../../data/repositories/db_repository_impl.dart';
import '../../domain/repositories/i_db_repository.dart';
import '../../infrastructure/simulation/simul_tf.dart';
import '../notifiers/hart_table_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../notifiers/connection_notifier.dart';
import '../notifiers/log_notifier.dart';
import '../notifiers/modbus_table_notifier.dart';
import '../notifiers/custom_types_notifier.dart';

// ── Infrastructure singletons ───────────────────────────────────────────────
final sqliteDatasourceProvider = Provider<SqliteDatasource>(
  (_) => SqliteDatasource(),
);

final dbRepositoryProvider = Provider<IDbRepository>((ref) {
  return DbRepositoryImpl(ref.watch(sqliteDatasourceProvider));
});

final simulTfProvider = Provider<SimulTf>((ref) {
  final stepMs = ref.watch(settingsProvider).tfStepMs;
  return SimulTf(stepMs: stepMs.toDouble());
});

// ── Settings ────────────────────────────────────────────────────────────────
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (_) => SettingsNotifier(),
);

// ── HART table ───────────────────────────────────────────────────────────────
final hartTableProvider =
    StateNotifierProvider<HartTableNotifier, HartTableState>((ref) {
  return HartTableNotifier(
    ref.watch(dbRepositoryProvider),
    ref.watch(simulTfProvider),
  );
});

// ── Connection (HART server + Modbus server) ─────────────────────────────────
final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>(
  (_) => ConnectionNotifier(),
);

// ── Logs ─────────────────────────────────────────────────────────────────────
final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  final notifier = LogNotifier();
  initGlobalLog(notifier);
  return notifier;
});

// ── Modbus table ─────────────────────────────────────────────────────────────
final modbusTableProvider =
    StateNotifierProvider<ModbusTableNotifier, ModbusTableState>((ref) {
  return ModbusTableNotifier(ref.watch(dbRepositoryProvider));
});
// ── Custom types (ENUM / BIT_ENUM) ───────────────────────────────────────
final customTypesProvider =
    StateNotifierProvider<CustomTypesNotifier, CustomTypesState>((ref) {
  return CustomTypesNotifier(ref.watch(dbRepositoryProvider));
});
