import 'dart:io';
import 'dart:typed_data';
import '../../application/notifiers/log_notifier.dart';
import '../network/socket_error_guard.dart';

class _ModbusRequestException implements Exception {
  final int code;
  const _ModbusRequestException(this.code);
}

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
  static const int _maxAduLength = 260;
  static const int _maxReceiveBufferLength = 4096;
  static const int _maxReadBits = 2000;
  static const int _maxReadRegisters = 125;
  static const int _maxWriteCoils = 1968;
  static const int _maxWriteRegisters = 123;

  final int port;
  final InternetAddress bindAddress;
  final int maxClients;
  final ModbusRegGetter getRegister;
  final ModbusRegSetter setRegister;
  final ModbusCoilGetter getCoil;
  final ModbusCoilSetter setCoil;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  bool _running = false;

  ModbusTcpServer({
    required this.port,
    InternetAddress? bindAddress,
    this.maxClients = 32,
    required this.getRegister,
    required this.setRegister,
    required this.getCoil,
    required this.setCoil,
  }) : bindAddress = bindAddress ?? InternetAddress.loopbackIPv4;

  bool get isRunning => _running;
  int get boundPort => _server?.port ?? port;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> start() async {
    if (_running) return;
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be between 0 and 65535');
    }
    if (maxClients < 1) {
      throw ArgumentError.value(maxClients, 'maxClients', 'must be positive');
    }
    _server = await ServerSocket.bind(bindAddress, port);
    _running = true;
    _server!.listen(_onClient);
    globalLog.info('Modbus', 'Server started on port $boundPort');
  }

  Future<void> stop() async {
    _running = false;
    // Iterate a copy: destroy() synchronously triggers each socket's onDone
    // handler, which removes itself from _clients — mutating the list
    // being iterated if we don't snapshot it first.
    for (final c in List<Socket>.from(_clients)) {
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
    if (_clients.length >= maxClients) {
      globalLog.warning('Modbus', 'Connection limit reached; rejecting client');
      socket.destroy();
      return;
    }
    _clients.add(socket);
    final addr = '${socket.remoteAddress.address}:${socket.remotePort}';
    globalLog.info('Modbus', 'Client connected: $addr');
    final buf = <int>[];
    socket.listen(
      (data) {
        buf.addAll(data);
        if (buf.length > _maxReceiveBufferLength) {
          globalLog.warning(
              'Modbus', 'Receive buffer limit exceeded; closing client');
          _clients.remove(socket);
          socket.destroy();
          return;
        }
        _process(buf, socket);
      },
      onDone: () {
        _clients.remove(socket);
        globalLog.info('Modbus', 'Client disconnected: $addr');
        try {
          socket.destroy();
        } catch (_) {}
      },
      onError: SocketErrorGuard(
        channel: 'Modbus',
        address: addr,
        socket: socket,
        clients: _clients,
      ).call,
      cancelOnError: true,
    );
  }

  // ── PDU processing ────────────────────────────────────────────────────────
  void _process(List<int> buf, Socket socket) {
    // Modbus TCP MBAP header: transaction(2)+protocol(2)+length(2)+unitId(1) = 7 bytes
    while (buf.length >= 7) {
      final transId = (buf[0] << 8) | buf[1];
      final protocolId = (buf[2] << 8) | buf[3];
      final pduLen =
          (buf[4] << 8) | buf[5]; // includes unit-id + function + data
      // A valid PDU always has at least a unit id + function code.
      if (protocolId != 0 || pduLen < 2 || 6 + pduLen > _maxAduLength) {
        globalLog.warning(
            'Modbus', 'Malformed frame (length=$pduLen), dropping buffer');
        buf.clear();
        return;
      }
      final totalNeeded = 6 + pduLen;
      if (buf.length < totalNeeded) return;

      final unitId = buf[6];
      final fnCode = buf[7];
      final pduData = buf.sublist(8, totalNeeded);
      buf.removeRange(0, totalNeeded);

      final response = _handlePDU(fnCode, pduData);
      if (response != null) {
        globalLog.debug('Modbus',
            'FC=0x${fnCode.toRadixString(16).padLeft(2, "0")} unit=$unitId, resp=${response.length}B');
        _sendResponse(socket, transId, unitId, response);
      }
    }
  }

  /// Returns the full response PDU (function code byte + payload), or `null`
  /// if no response should be sent.
  List<int>? _handlePDU(int fn, List<int> data) {
    try {
      final payload = switch (fn) {
        0x01 => _readBits(data, isInput: false), // Read Coils
        0x02 => _readBits(data, isInput: true), // Read DI
        0x03 => _readRegs(data, isInput: false), // Read HR
        0x04 => _readRegs(data, isInput: true), // Read IR
        0x05 => _writeSingleCoil(data),
        0x06 => _writeSingleReg(data),
        0x0F => _writeMultipleCoils(data),
        0x10 => _writeMultipleRegs(data),
        _ => null, // Illegal function
      };
      if (payload == null) return _exception(fn, 0x01);
      return [fn, ...payload];
    } on _ModbusRequestException catch (e) {
      return _exception(fn, e.code);
    } catch (_) {
      return _exception(fn, 0x04); // Slave device failure
    }
  }

  // ── Read registers (0x03 / 0x04) ─────────────────────────────────────────
  List<int> _readRegs(List<int> data, {required bool isInput}) {
    if (data.length != 4) throw const _ModbusRequestException(0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    if (count < 1 || count > _maxReadRegisters) {
      throw const _ModbusRequestException(0x03);
    }
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
    if (data.length != 4) throw const _ModbusRequestException(0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    if (count < 1 || count > _maxReadBits) {
      throw const _ModbusRequestException(0x03);
    }
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
    if (data.length != 4) throw const _ModbusRequestException(0x03);
    final addr = (data[0] << 8) | data[1];
    final rawValue = (data[2] << 8) | data[3];
    if (rawValue != 0xFF00 && rawValue != 0x0000) {
      throw const _ModbusRequestException(0x03);
    }
    final value = rawValue == 0xFF00;
    setCoil(addr, value);
    return data.sublist(0, 4); // Echo
  }

  // ── Write single register (0x06) ─────────────────────────────────────────
  List<int> _writeSingleReg(List<int> data) {
    if (data.length != 4) throw const _ModbusRequestException(0x03);
    final addr = (data[0] << 8) | data[1];
    final value = (data[2] << 8) | data[3];
    setRegister(addr, value);
    return data.sublist(0, 4); // Echo
  }

  // ── Write multiple coils (0x0F) ───────────────────────────────────────────
  List<int> _writeMultipleCoils(List<int> data) {
    if (data.length < 5) throw const _ModbusRequestException(0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    final byteCount = data[4];
    final expectedByteCount = (count + 7) ~/ 8;
    if (count < 1 ||
        count > _maxWriteCoils ||
        byteCount != expectedByteCount ||
        data.length != 5 + byteCount) {
      throw const _ModbusRequestException(0x03);
    }
    final writes = <(int, bool)>[];
    for (int i = 0; i < count; i++) {
      final byteIdx = i ~/ 8;
      final bitIdx = i % 8;
      writes.add((startAddr + i, (data[5 + byteIdx] & (1 << bitIdx)) != 0));
    }
    for (final (address, value) in writes) {
      setCoil(address, value);
    }
    return [data[0], data[1], data[2], data[3]];
  }

  // ── Write multiple registers (0x10) ──────────────────────────────────────
  List<int> _writeMultipleRegs(List<int> data) {
    if (data.length < 5) throw const _ModbusRequestException(0x03);
    final startAddr = (data[0] << 8) | data[1];
    final count = (data[2] << 8) | data[3];
    final byteCount = data[4];
    if (count < 1 ||
        count > _maxWriteRegisters ||
        byteCount != count * 2 ||
        data.length != 5 + byteCount) {
      throw const _ModbusRequestException(0x03);
    }
    final writes = <(int, int)>[];
    for (int i = 0; i < count; i++) {
      final idx = 5 + i * 2;
      writes.add((startAddr + i, (data[idx] << 8) | data[idx + 1]));
    }
    for (final (address, value) in writes) {
      setRegister(address, value);
    }
    return [data[0], data[1], data[2], data[3]];
  }

  // ── Exception response ────────────────────────────────────────────────────
  /// Full exception PDU: function code (with error bit set) + exception code.
  List<int> _exception(int fn, int code) => [fn | 0x80, code];

  // ── Send MBAP-wrapped response ────────────────────────────────────────────
  /// [pdu] is the full response PDU, i.e. function code byte + payload.
  void _sendResponse(Socket socket, int transId, int unitId, List<int> pdu) {
    final pduLen = 1 + pdu.length; // unitId + pdu (function code + data)
    final packet = Uint8List.fromList([
      (transId >> 8) & 0xFF, transId & 0xFF, // Transaction ID
      0x00, 0x00, // Protocol ID (Modbus)
      (pduLen >> 8) & 0xFF, pduLen & 0xFF, // Length
      unitId, // Unit ID
      ...pdu, // PDU (function code + data)
    ]);
    try {
      socket.add(packet);
    } catch (_) {}
  }
}
