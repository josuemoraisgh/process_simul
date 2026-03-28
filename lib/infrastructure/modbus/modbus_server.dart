import 'dart:io';
import 'dart:typed_data';
import '../../application/notifiers/log_notifier.dart';

typedef ModbusRegGetter = int Function(int address, bool isInput);
typedef ModbusRegSetter = void Function(int address, int value);
typedef ModbusCoilGetter = bool Function(int address, bool isInput);
typedef ModbusCoilSetter = void Function(int address, bool value);

/// Minimal Modbus TCP server (subset of the Modbus TCP specification).
///
/// Supported function codes:
///   0x01 – Read Coils
///   0x02 – Read Discrete Inputs
///   0x03 – Read Holding Registers
///   0x04 – Read Input Registers
///   0x05 – Write Single Coil
///   0x06 – Write Single Register
///   0x0F – Write Multiple Coils
///   0x10 – Write Multiple Registers
class ModbusTcpServer {
  final int port;
  final ModbusRegGetter getRegister;
  final ModbusRegSetter setRegister;
  final ModbusCoilGetter getCoil;
  final ModbusCoilSetter setCoil;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  bool _running = false;

  ModbusTcpServer({
    required this.port,
    required this.getRegister,
    required this.setRegister,
    required this.getCoil,
    required this.setCoil,
  });

  bool get isRunning => _running;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> start() async {
    if (_running) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _running = true;
    _server!.listen(_onClient);
    globalLog.info('Modbus', 'Server started on port $port');
  }

  Future<void> stop() async {
    _running = false;
    for (final c in _clients) {
      try {
        c.destroy();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    globalLog.info('Modbus', 'Server stopped');
  }

  // ── Client ────────────────────────────────────────────────────────────────
  void _onClient(Socket socket) {
    _clients.add(socket);
    final addr = '${socket.remoteAddress.address}:${socket.remotePort}';
    globalLog.info('Modbus', 'Client connected: $addr');
    final buf = <int>[];
    socket.listen(
      (data) {
        buf.addAll(data);
        _process(buf, socket);
      },
      onDone: () {
        _clients.remove(socket);
        globalLog.info('Modbus', 'Client disconnected: $addr');
        try {
          socket.destroy();
        } catch (_) {}
      },
      onError: (e) {
        _clients.remove(socket);
        globalLog.warning('Modbus', 'Client error ($addr): $e');
        try {
          socket.destroy();
        } catch (_) {}
      },
      cancelOnError: true,
    );
  }

  // ── PDU processing ────────────────────────────────────────────────────────
  void _process(List<int> buf, Socket socket) {
    // Modbus TCP MBAP header: transaction(2)+protocol(2)+length(2)+unitId(1) = 7 bytes
    while (buf.length >= 8) {
      final transId = (buf[0] << 8) | buf[1];
      // protocol = buf[2..3] should be 0
      final pduLen =
          (buf[4] << 8) | buf[5]; // includes unit-id + function + data
      final totalNeeded = 6 + pduLen;
      if (buf.length < totalNeeded) return;

      final unitId = buf[6];
      final fnCode = buf[7];
      final pduData = buf.sublist(8, totalNeeded);
      buf.removeRange(0, totalNeeded);

      final response = _handlePDU(fnCode, pduData);
      if (response != null) {
        globalLog.debug('Modbus', 'FC=0x${fnCode.toRadixString(16).padLeft(2,"0")} unit=$unitId, resp=${response.length}B');
        _sendResponse(socket, transId, unitId, fnCode, response);
      }
    }
  }

  List<int>? _handlePDU(int fn, List<int> data) {
    try {
      switch (fn) {
        case 0x01:
          return _readBits(data, isInput: false); // Read Coils
        case 0x02:
          return _readBits(data, isInput: true); // Read DI
        case 0x03:
          return _readRegs(data, isInput: false); // Read HR
        case 0x04:
          return _readRegs(data, isInput: true); // Read IR
        case 0x05:
          return _writeSingleCoil(data);
        case 0x06:
          return _writeSingleReg(data);
        case 0x0F:
          return _writeMultipleCoils(data);
        case 0x10:
          return _writeMultipleRegs(data);
        default:
          return _exception(fn, 0x01); // Illegal function
      }
    } catch (_) {
      return _exception(fn, 0x04); // Slave device failure
    }
  }

  // ── Read registers (0x03 / 0x04) ─────────────────────────────────────────
  List<int> _readRegs(List<int> data, {required bool isInput}) {
    if (data.length < 4) return _exception(isInput ? 0x04 : 0x03, 0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    final bytes = <int>[count * 2];
    for (int i = 0; i < count; i++) {
      final val = getRegister(startAddr + i, isInput);
      bytes.add((val >> 8) & 0xFF);
      bytes.add(val & 0xFF);
    }
    return bytes;
  }

  // ── Read bits (0x01 / 0x02) ───────────────────────────────────────────────
  List<int> _readBits(List<int> data, {required bool isInput}) {
    if (data.length < 4) return _exception(isInput ? 0x02 : 0x01, 0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    final byteCount = (count + 7) ~/ 8;
    final bytes = <int>[byteCount];
    for (int b = 0; b < byteCount; b++) {
      int byteVal = 0;
      for (int bit = 0; bit < 8; bit++) {
        final bitIdx = b * 8 + bit;
        if (bitIdx < count && getCoil(startAddr + bitIdx, isInput)) {
          byteVal |= (1 << bit);
        }
      }
      bytes.add(byteVal);
    }
    return bytes;
  }

  // ── Write single coil (0x05) ──────────────────────────────────────────────
  List<int> _writeSingleCoil(List<int> data) {
    if (data.length < 4) return _exception(0x05, 0x03);
    final addr = (data[0] << 8) | data[1];
    final value = data[2] == 0xFF;
    setCoil(addr, value);
    return data.sublist(0, 4); // Echo
  }

  // ── Write single register (0x06) ─────────────────────────────────────────
  List<int> _writeSingleReg(List<int> data) {
    if (data.length < 4) return _exception(0x06, 0x03);
    final addr = (data[0] << 8) | data[1];
    final value = (data[2] << 8) | data[3];
    setRegister(addr, value);
    return data.sublist(0, 4); // Echo
  }

  // ── Write multiple coils (0x0F) ───────────────────────────────────────────
  List<int> _writeMultipleCoils(List<int> data) {
    if (data.length < 5) return _exception(0x0F, 0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    for (int i = 0; i < count; i++) {
      final byteIdx = i ~/ 8;
      final bitIdx = i % 8;
      if (5 + byteIdx < data.length) {
        setCoil(startAddr + i, (data[5 + byteIdx] & (1 << bitIdx)) != 0);
      }
    }
    return [data[0], data[1], data[2], data[3]];
  }

  // ── Write multiple registers (0x10) ──────────────────────────────────────
  List<int> _writeMultipleRegs(List<int> data) {
    if (data.length < 5) return _exception(0x10, 0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    for (int i = 0; i < count; i++) {
      final idx = 5 + i * 2;
      if (idx + 1 < data.length) {
        final val = (data[idx] << 8) | data[idx + 1];
        setRegister(startAddr + i, val);
      }
    }
    return [data[0], data[1], data[2], data[3]];
  }

  // ── Exception response ────────────────────────────────────────────────────
  List<int> _exception(int fn, int code) => [fn | 0x80, code];

  // ── Send MBAP-wrapped response ────────────────────────────────────────────
  void _sendResponse(
      Socket socket, int transId, int unitId, int fn, List<int> data) {
    final pduLen = 1 + data.length; // unitId + data
    final packet = Uint8List.fromList([
      (transId >> 8) & 0xFF, transId & 0xFF, // Transaction ID
      0x00, 0x00, // Protocol ID (Modbus)
      (pduLen >> 8) & 0xFF, pduLen & 0xFF, // Length
      unitId, // Unit ID
      ...data, // PDU
    ]);
    try {
      socket.add(packet);
    } catch (_) {}
  }
}
