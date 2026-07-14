import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/react_var.dart';
import '../../infrastructure/hart/hart_comm.dart';
import '../../infrastructure/hart/hart_serial_comm.dart';
import '../../infrastructure/hart/hart_transmitter.dart';
import '../../infrastructure/modbus/modbus_server.dart';
import '../../infrastructure/modbus/modbus_value_parser.dart';
import 'hart_table_notifier.dart';
import 'log_notifier.dart';
import 'modbus_table_notifier.dart';

/// State for HART server and Modbus server connection.
class ConnectionState {
  final bool hartServerRunning;
  final bool modbusRunning;
  final String? hartError;
  final String? modbusError;
  final int hartPort;
  final String hartSerialPort;
  final int modbusPort;
  final bool modbusTestMode;
  final int modbusTestValue;

  const ConnectionState({
    this.hartServerRunning = false,
    this.modbusRunning = false,
    this.hartError,
    this.modbusError,
    this.hartPort = 5094,
    this.hartSerialPort = '',
    this.modbusPort = 502,
    this.modbusTestMode = false,
    this.modbusTestValue = 0,
  });

  ConnectionState copyWith({
    bool? hartServerRunning,
    bool? modbusRunning,
    String? hartError,
    String? modbusError,
    int? hartPort,
    String? hartSerialPort,
    int? modbusPort,
    bool? modbusTestMode,
    int? modbusTestValue,
  }) =>
      ConnectionState(
        hartServerRunning: hartServerRunning ?? this.hartServerRunning,
        modbusRunning: modbusRunning ?? this.modbusRunning,
        hartError: hartError,
        modbusError: modbusError,
        hartPort: hartPort ?? this.hartPort,
        hartSerialPort: hartSerialPort ?? this.hartSerialPort,
        modbusPort: modbusPort ?? this.modbusPort,
        modbusTestMode: modbusTestMode ?? this.modbusTestMode,
        modbusTestValue: modbusTestValue ?? this.modbusTestValue,
      );
}

typedef TableGetter = Map<String, Map<String, ReactVar>> Function();
typedef CellWriter = void Function(String device, String col, String hex);
typedef HartServerFactory = HartCommServer Function(
    int port,
    InternetAddress address,
    TableGetter getTable,
    CellWriter writeCell,
    HartTransmitter transmitter);
typedef HartSerialFactory = HartSerialServer Function(String portName,
    TableGetter getTable, CellWriter writeCell, HartTransmitter transmitter);

HartCommServer _defaultHartServerFactory(
        int port,
        InternetAddress address,
        TableGetter getTable,
        CellWriter writeCell,
        HartTransmitter transmitter) =>
    HartCommServer(
      port: port,
      bindAddress: address,
      getTable: getTable,
      writeCell: writeCell,
      transmitter: transmitter,
    );

HartSerialServer _defaultHartSerialFactory(
        String portName,
        TableGetter getTable,
        CellWriter writeCell,
        HartTransmitter transmitter) =>
    HartSerialServer(
      portName: portName,
      getTable: getTable,
      writeCell: writeCell,
      transmitter: transmitter,
    );

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  final HartTableNotifier _hartTable;
  final ModbusTableNotifier _modbusTable;
  final HartTransmitter _hartTransmitter;
  final HartServerFactory _hartServerFactory;
  final HartSerialFactory _hartSerialFactory;
  final Duration _modbusTestInterval;
  void Function()? _removeModbusTableListener;

  HartCommServer? _hartServer;
  HartSerialServer? _hartSerial;
  ModbusTcpServer? _modbusServer;

  // Modbus register/bit maps
  final _hrMap = <int, int>{}; // Holding Registers  (master-writable)
  final _irMap = <int, int>{}; // Input Registers    (read-only, from process)
  final _coilMap = <int, bool>{}; // Coils            (master-writable)
  final _diMap = <int, bool>{}; // Discrete Inputs    (read-only, from process)
  Timer? _modbusTestTimer;
  Map<int, int>? _hrBeforeTest;
  Map<int, int>? _irBeforeTest;
  Map<int, bool>? _coilBeforeTest;
  Map<int, bool>? _diBeforeTest;

  ConnectionNotifier(this._hartTable, this._modbusTable,
      {HartTransmitter? hartTransmitter,
      HartServerFactory hartServerFactory = _defaultHartServerFactory,
      HartSerialFactory hartSerialFactory = _defaultHartSerialFactory,
      Duration modbusTestInterval = const Duration(seconds: 1)})
      : _hartTransmitter = hartTransmitter ?? HartTransmitter.standard(),
        _hartServerFactory = hartServerFactory,
        _hartSerialFactory = hartSerialFactory,
        _modbusTestInterval = modbusTestInterval,
        super(const ConnectionState()) {
    // Keep the Modbus register/bit maps in sync with the simulated process
    // values (HART table) and the configured address/formula table.
    _hartTable.dataVersionNotifier.addListener(_onHartDataChanged);
    _removeModbusTableListener =
        _modbusTable.addListener(_onModbusTableChanged);
  }

  // ── HART Server ────────────────────────────────────────────────────────────
  Future<void> startHartServer(
      int port, TableGetter getTable, CellWriter writeCell,
      {String bindHost = '127.0.0.1'}) async {
    await stopHartServer();
    try {
      _hartServer = _hartServerFactory(port, InternetAddress(bindHost),
          getTable, writeCell, _hartTransmitter);
      await _hartServer!.start();
      state = state.copyWith(
          hartServerRunning: true, hartError: null, hartPort: port);
    } catch (e) {
      globalLog.error('HART', 'Failed to start server: $e');
      state = state.copyWith(hartServerRunning: false, hartError: e.toString());
    }
  }

  Future<void> stopHartServer() async {
    try {
      await _hartServer?.stop();
    } catch (e) {
      globalLog.warning('HART', 'Error stopping TCP server: $e');
    }
    _hartServer = null;
    try {
      await _hartSerial?.stop();
    } catch (e) {
      globalLog.warning('HART-Serial', 'Error stopping serial: $e');
    }
    _hartSerial = null;
    state = state.copyWith(hartServerRunning: false, hartError: null);
  }

  // ── HART Serial ────────────────────────────────────────────────────────────
  Future<void> startHartSerial(
      String portName, TableGetter getTable, CellWriter writeCell) async {
    await stopHartServer();
    try {
      _hartSerial =
          _hartSerialFactory(portName, getTable, writeCell, _hartTransmitter);
      await _hartSerial!.start();
      state = state.copyWith(
          hartServerRunning: true, hartError: null, hartSerialPort: portName);
    } catch (e) {
      globalLog.error('HART-Serial', 'Failed to open $portName: $e');
      state = state.copyWith(hartServerRunning: false, hartError: e.toString());
    }
  }

  // ── Modbus Server ──────────────────────────────────────────────────────────
  Future<void> startModbus(int port, {String bindHost = '127.0.0.1'}) async {
    await stopModbus();
    try {
      _modbusServer = ModbusTcpServer(
        port: port,
        bindAddress: InternetAddress(bindHost),
        getRegister: (addr, isInput) =>
            (isInput ? _irMap[addr] : _hrMap[addr]) ?? 0,
        setRegister: (addr, val) {
          if (!state.modbusTestMode) _hrMap[addr] = val;
        },
        getCoil: (addr, isInput) =>
            isInput ? (_diMap[addr] ?? false) : (_coilMap[addr] ?? false),
        setCoil: (addr, val) {
          if (!state.modbusTestMode) _coilMap[addr] = val;
        },
      );
      await _modbusServer!.start();
      state = state.copyWith(
          modbusRunning: true, modbusError: null, modbusPort: port);
    } catch (e) {
      globalLog.error('Modbus', 'Failed to start server: $e');
      state = state.copyWith(modbusRunning: false, modbusError: e.toString());
    }
  }

  Future<void> stopModbus() async {
    await _modbusServer?.stop();
    _modbusServer = null;
    state = state.copyWith(modbusRunning: false, modbusError: null);
  }

  // ── Register sync ───────────────────────────────────────────────────────────
  void syncHrRegister(int address, int value) => _hrMap[address] = value;
  void syncIrRegister(int address, int value) => _irMap[address] = value;

  void _onHartDataChanged() => _refreshReadOnlyPoints(_modbusTable.state);

  void _onModbusTableChanged(ModbusTableState mbState) {
    if (state.modbusTestMode) {
      _applyModbusTestValue(mbState, state.modbusTestValue);
      return;
    }
    _refreshReadOnlyPoints(mbState);
    _seedWritablePoints(mbState);
  }

  /// Alternates every configured Modbus point between 0 and 1. This affects
  /// only the Modbus wire maps; HART values and persisted formulas are never
  /// modified. Disabling the mode restores the maps captured on activation.
  void setModbusTestMode(bool enabled) {
    if (enabled == state.modbusTestMode) return;
    _modbusTestTimer?.cancel();
    _modbusTestTimer = null;

    if (enabled) {
      _hrBeforeTest = Map.of(_hrMap);
      _irBeforeTest = Map.of(_irMap);
      _coilBeforeTest = Map.of(_coilMap);
      _diBeforeTest = Map.of(_diMap);
      state = state.copyWith(modbusTestMode: true, modbusTestValue: 0);
      _applyModbusTestValue(_modbusTable.state, 0);
      _modbusTestTimer = Timer.periodic(_modbusTestInterval, (_) {
        final next = state.modbusTestValue == 0 ? 1 : 0;
        _applyModbusTestValue(_modbusTable.state, next);
        state = state.copyWith(modbusTestMode: true, modbusTestValue: next);
      });
      globalLog.info('Modbus', 'Test mode enabled (1 second, shared 0/1)');
      return;
    }

    _restoreModbusMaps();
    state = state.copyWith(modbusTestMode: false, modbusTestValue: 0);
    _refreshReadOnlyPoints(_modbusTable.state);
    _seedWritablePoints(_modbusTable.state);
    globalLog.info('Modbus', 'Test mode disabled');
  }

  void _applyModbusTestValue(ModbusTableState mbState, int value) {
    final bit = value != 0;
    for (final variable in mbState.data.values) {
      final (_, _, mbPoint, address, _) = variable;
      final wireAddress = _wireAddress(address);
      if (wireAddress == null) continue;
      switch (mbPoint) {
        case 'hr':
          _hrMap[wireAddress] = value;
        case 'ir':
          _irMap[wireAddress] = value;
        case 'co':
          _coilMap[wireAddress] = bit;
        case 'di':
          _diMap[wireAddress] = bit;
      }
    }
  }

  void _restoreModbusMaps() {
    _hrMap
      ..clear()
      ..addAll(_hrBeforeTest ?? const {});
    _irMap
      ..clear()
      ..addAll(_irBeforeTest ?? const {});
    _coilMap
      ..clear()
      ..addAll(_coilBeforeTest ?? const {});
    _diMap
      ..clear()
      ..addAll(_diBeforeTest ?? const {});
    _hrBeforeTest = null;
    _irBeforeTest = null;
    _coilBeforeTest = null;
    _diBeforeTest = null;
  }

  /// Pushes the current computed value of every 'ir'/'di' variable from the
  /// Modbus address table into the read-only register/bit maps. These points
  /// mirror the simulated process, so they are safe to overwrite every tick.
  void _refreshReadOnlyPoints(ModbusTableState mbState) {
    if (state.modbusTestMode) return;
    for (final v in mbState.data.values) {
      final (_, _, mbPoint, addressStr, formula) = v;
      if (mbPoint != 'ir' && mbPoint != 'di') continue;
      final wireAddr = _wireAddress(addressStr);
      if (wireAddr == null) continue;
      final value = _evalPointValue(formula);
      if (mbPoint == 'ir') {
        syncIrRegister(wireAddr, value.truncate() & 0xFFFF);
      } else {
        _diMap[wireAddr] = value != 0;
      }
    }
  }

  /// Seeds 'hr'/'co' variables with their configured default value the first
  /// time they are seen, without clobbering values already written by a
  /// connected Modbus master.
  void _seedWritablePoints(ModbusTableState mbState) {
    for (final v in mbState.data.values) {
      final (_, _, mbPoint, addressStr, formula) = v;
      if (mbPoint != 'hr' && mbPoint != 'co') continue;
      final wireAddr = _wireAddress(addressStr);
      if (wireAddr == null) continue;
      if (mbPoint == 'hr' && !_hrMap.containsKey(wireAddr)) {
        _hrMap[wireAddr] = _evalPointValue(formula).truncate() & 0xFFFF;
      } else if (mbPoint == 'co' && !_coilMap.containsKey(wireAddr)) {
        _coilMap[wireAddr] = _evalPointValue(formula) != 0;
      }
    }
  }

  double _evalPointValue(String formula) {
    if (formula.startsWith('@')) {
      return HartTransmitter.evaluateExpr(
          formula.substring(1), _hartTable.state.data);
    }
    return ModbusValueParser.parseLiteral(formula);
  }

  /// Converts the 1-based address configured in the Modbus table (as shown
  /// to the user, e.g. "1" for holding/input register 40001/30001) into the
  /// 0-based address used on the wire by the Modbus TCP PDU.
  int? _wireAddress(String addressStr) {
    final addr = int.tryParse(addressStr.trim());
    if (addr == null) return null;
    return addr > 0 ? addr - 1 : addr;
  }

  @override
  void dispose() {
    _modbusTestTimer?.cancel();
    _hartTable.dataVersionNotifier.removeListener(_onHartDataChanged);
    _removeModbusTableListener?.call();
    _stopSilently(_hartServer?.stop(), 'HART TCP');
    _stopSilently(_hartSerial?.stop(), 'HART serial');
    _stopSilently(_modbusServer?.stop(), 'Modbus TCP');
    super.dispose();
  }

  void _stopSilently(Future<void>? operation, String service) {
    if (operation == null) return;
    unawaited(operation.catchError((Object error, StackTrace stackTrace) {
      globalLog.warning('CONNECTION', 'Failed to stop $service: $error');
    }));
  }
}
