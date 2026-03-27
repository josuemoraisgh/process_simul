import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/react_var.dart';
import '../../infrastructure/hart/hart_comm.dart';
import '../../infrastructure/modbus/modbus_server.dart';

/// State for HART server and Modbus server connection.
class ConnectionState {
  final bool hartServerRunning;
  final bool modbusRunning;
  final String? hartError;
  final String? modbusError;
  final int hartPort;
  final int modbusPort;

  const ConnectionState({
    this.hartServerRunning = false,
    this.modbusRunning     = false,
    this.hartError,
    this.modbusError,
    this.hartPort          = 5094,
    this.modbusPort        = 502,
  });

  ConnectionState copyWith({
    bool?   hartServerRunning,
    bool?   modbusRunning,
    String? hartError,
    String? modbusError,
    int?    hartPort,
    int?    modbusPort,
  }) => ConnectionState(
    hartServerRunning: hartServerRunning ?? this.hartServerRunning,
    modbusRunning:     modbusRunning     ?? this.modbusRunning,
    hartError:         hartError,
    modbusError:       modbusError,
    hartPort:          hartPort          ?? this.hartPort,
    modbusPort:        modbusPort        ?? this.modbusPort,
  );
}

typedef TableGetter = Map<String, Map<String, ReactVar>> Function();
typedef CellWriter = void Function(String device, String col, String hex);

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  HartCommServer?  _hartServer;
  ModbusTcpServer? _modbusServer;

  // Modbus register maps
  final _hrMap = <int, int>{};  // Holding Registers (writable)
  final _irMap = <int, int>{};  // Input Registers   (readable)
  final _coilMap = <int, bool>{};

  ConnectionNotifier() : super(const ConnectionState());

  // ── HART Server ────────────────────────────────────────────────────────────
  Future<void> startHartServer(
      int port, TableGetter getTable, CellWriter writeCell) async {
    await stopHartServer();
    try {
      _hartServer = HartCommServer(
        port: port,
        getTable: getTable,
        writeCell: writeCell,
      );
      await _hartServer!.start();
      state = state.copyWith(
          hartServerRunning: true, hartError: null, hartPort: port);
    } catch (e) {
      state = state.copyWith(
          hartServerRunning: false, hartError: e.toString());
    }
  }

  Future<void> stopHartServer() async {
    await _hartServer?.stop();
    _hartServer = null;
    state = state.copyWith(hartServerRunning: false, hartError: null);
  }

  // ── Modbus Server ──────────────────────────────────────────────────────────
  Future<void> startModbus(int port) async {
    await stopModbus();
    try {
      _modbusServer = ModbusTcpServer(
        port: port,
        getRegister: (addr, isInput) =>
            (isInput ? _irMap[addr] : _hrMap[addr]) ?? 0,
        setRegister: (addr, val) => _hrMap[addr] = val,
        getCoil:    (addr, isInput) => _coilMap[addr] ?? false,
        setCoil:    (addr, val)    => _coilMap[addr]  = val,
      );
      await _modbusServer!.start();
      state = state.copyWith(
          modbusRunning: true, modbusError: null, modbusPort: port);
    } catch (e) {
      state = state.copyWith(
          modbusRunning: false, modbusError: e.toString());
    }
  }

  Future<void> stopModbus() async {
    await _modbusServer?.stop();
    _modbusServer = null;
    state = state.copyWith(modbusRunning: false, modbusError: null);
  }

  // ── Register sync (called by HartTableNotifier on data change) ─────────────
  void syncHrRegister(int address, int value) => _hrMap[address] = value;
  void syncIrRegister(int address, int value) => _irMap[address] = value;

  @override
  void dispose() {
    _hartServer?.stop();
    _modbusServer?.stop();
    super.dispose();
  }
}
