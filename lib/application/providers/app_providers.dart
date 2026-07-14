import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/sqlite_datasource.dart';
import '../../data/repositories/db_repository_impl.dart';
import '../../data/repositories/sqlite_equipment_repository.dart';
import '../../domain/repositories/i_db_repository.dart';
import '../../domain/hart/hart_command_registry.dart';
import '../../infrastructure/hart/hart_transmitter.dart';
import '../../infrastructure/simulation/simul_tf.dart';
import '../notifiers/hart_table_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../notifiers/connection_notifier.dart';
import '../notifiers/log_notifier.dart';
import '../notifiers/modbus_table_notifier.dart';
import '../notifiers/custom_types_notifier.dart';
import '../equipment/equipment_catalog.dart';

// ── Infrastructure singletons ───────────────────────────────────────────────
final sqliteDatasourceProvider = Provider<SqliteDatasource>(
  (ref) {
    final datasource = SqliteDatasource();
    ref.onDispose(datasource.close);
    return datasource;
  },
);

final dbRepositoryProvider = Provider<IDbRepository>((ref) {
  return DbRepositoryImpl(ref.watch(sqliteDatasourceProvider));
});

final equipmentRepositoryProvider = Provider<EquipmentRepository>((ref) {
  return SqliteEquipmentRepository(ref.watch(sqliteDatasourceProvider));
});

final equipmentCatalogProvider = Provider<EquipmentCatalog>((ref) {
  return EquipmentCatalog(ref.watch(equipmentRepositoryProvider));
});

final hartFunctionRegistryProvider = Provider<HartFunctionRegistry>(
  (_) => HartFunctionRegistry(),
);

final hartCommandRegistryProvider = Provider<HartCommandRegistry>(
  (_) => HartTransmitter.standardCommandRegistry(),
);

final hartTransmitterProvider = Provider<HartTransmitter>((ref) {
  return HartTransmitter(
    commands: ref.watch(hartCommandRegistryProvider),
    functions: ref.watch(hartFunctionRegistryProvider),
  );
});

final simulTfProvider = Provider<SimulTf>((ref) {
  final stepMs = ref.watch(settingsProvider.select((s) => s.tfStepMs));
  final simulation = SimulTf(stepMs: stepMs.toDouble());
  ref.onDispose(simulation.stop);
  return simulation;
});

/// Whether the TF simulation is currently running (drives UI only).
final tfRunningProvider = StateProvider<bool>((_) => false);

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
    ref.watch(equipmentCatalogProvider),
  );
});

// ── Connection (HART server + Modbus server) ─────────────────────────────────
final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>(
  (ref) => ConnectionNotifier(
    ref.watch(hartTableProvider.notifier),
    ref.watch(modbusTableProvider.notifier),
    hartTransmitter: ref.watch(hartTransmitterProvider),
  ),
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
