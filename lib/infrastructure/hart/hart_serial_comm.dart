import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../../domain/entities/react_var.dart';
import '../../application/notifiers/log_notifier.dart';
import 'hart_transmitter.dart';

typedef HartTableGetter = Map<String, Map<String, ReactVar>> Function();
typedef HartCellWriter = void Function(
    String device, String col, String rawHex);

/// Serial-port server that implements the HART protocol slave simulator.
///
/// Opens [portName] (e.g. 'COM3') and listens for incoming HART frames,
/// parses them, delegates to [HartTransmitter], and sends back responses.
class HartSerialServer {
  final String portName;
  final HartTableGetter getTable;
  final HartCellWriter writeCell;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;
  bool _running = false;
  final _buf = <int>[];

  HartSerialServer({
    required this.portName,
    required this.getTable,
    required this.writeCell,
  });

  bool get isRunning => _running;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  Future<void> start() async {
    if (_running) return;

    // Windows needs \\.\PREFIX for non-standard port names (e.g. CNCA0)
    String osPortName = portName;
    if (!portName.startsWith(r'\\') &&
        !portName.toUpperCase().startsWith('COM')) {
      osPortName = r'\\.\' + portName;
    }

    _port = SerialPort(osPortName);

    // Open for read+write
    if (!_port!.openReadWrite()) {
      final err = SerialPort.lastError?.message ?? 'Unknown error';
      globalLog.error(
          'HART-Serial', 'Cannot open $portName ($osPortName): $err');
      _port?.dispose();
      _port = null;
      throw Exception('Cannot open $portName: $err');
    }

    // Configure: 1200 baud, 8-O-1 (HART standard)
    final config = SerialPortConfig()
      ..baudRate = 1200
      ..bits = 8
      ..parity = SerialPortParity.odd
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    _port!.config = config;
    config.dispose();

    _reader = SerialPortReader(_port!);
    _sub = _reader!.stream.listen(
      (data) {
        if (!_running) return;
        _buf.addAll(data);
        _flush();
      },
      onError: (e) {
        if (!_running) return;
        globalLog.warning('HART-Serial', 'Read error on $portName: $e');
      },
    );

    _running = true;
    globalLog.info('HART-Serial', 'Listening on $portName (1200 baud, 8-O-1)');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _buf.clear();

    // 1. Cancel the stream subscription first (stops data callbacks).
    final sub = _sub;
    _sub = null;
    try {
      await sub?.cancel();
    } catch (_) {}

    // 2. Close reader — must happen AFTER cancel and BEFORE port close.
    //    SerialPortReader.close() can crash if the port is already closed,
    //    so we wrap it and give time for native cleanup.
    final reader = _reader;
    _reader = null;
    if (reader != null) {
      try {
        reader.close();
      } catch (_) {}
      // Allow native event loop to settle before closing the port.
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 3. Close and dispose the port.
    final port = _port;
    _port = null;
    if (port != null) {
      try {
        if (port.isOpen) port.close();
      } catch (_) {}
      try {
        port.dispose();
      } catch (_) {}
    }

    globalLog.info('HART-Serial', 'Stopped on $portName');
  }

  // ── Frame extraction (identical logic to HartCommServer._flush) ──────────
  void _flush() {
    // Consume until preamble
    while (_buf.isNotEmpty && _buf.first != 0xFF) _buf.removeAt(0);
    if (_buf.length < 6) return;

    // Find end of preamble
    int pos = 0;
    while (pos < _buf.length && _buf[pos] == 0xFF) pos++;
    if (pos >= _buf.length) return;

    final delim = _buf[pos];
    final isLong = (delim & 0x80) != 0;
    final addrLen = isLong ? 5 : 1;
    final headerEnd = pos + 1 + addrLen + 2;
    if (_buf.length <= headerEnd) return;
    final byteCount = _buf[headerEnd - 1];
    final totalNeeded = headerEnd + byteCount + 1; // +1 checksum
    if (_buf.length < totalNeeded) return;

    final frame = List<int>.from(_buf.sublist(0, totalNeeded));
    _buf.removeRange(0, totalNeeded);

    _handleFrame(frame);

    // Process further frames in buffer
    if (_buf.isNotEmpty) _flush();
  }

  // ── Frame processing (identical logic to HartCommServer._handleFrame) ────
  void _handleFrame(List<int> raw) {
    int pos = 0;
    while (pos < raw.length && raw[pos] == 0xFF) pos++;
    if (pos >= raw.length) return;

    final delim = raw[pos];

    // Ignore our own echoed response frames (delimiter 0x06 or 0x86)
    final frameType = delim & 0x07;
    if (frameType == 0x06 || frameType == 0x01) {
      // 0x06 = slave response (short), 0x86 = slave response (long)
      // 0x01 = burst frame — also ignore
      return;
    }

    // Log received frame
    final rxHex = raw
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    globalLog.debug('HART-Serial', 'Rx: $rxHex');

    pos++; // advance past delimiter
    final isLong = (delim & 0x80) != 0;
    int pollAddr = 0;
    List<int> addrBytes =
        []; // full address bytes (preserves master/burst bits)

    if (isLong) {
      if (pos + 5 > raw.length) return;
      addrBytes = List.from(raw.sublist(pos, pos + 5));
      pos += 5;
    } else {
      if (pos >= raw.length) return;
      addrBytes = [raw[pos++]];
      pollAddr = addrBytes[0] & 0x3F;
    }

    if (pos + 2 > raw.length) return;
    final command = raw[pos++];
    final byteCount = raw[pos++];
    if (pos + byteCount > raw.length) return;
    final body = raw.sublist(pos, pos + byteCount);

    // Route to correct device
    final table = getTable();
    Map<String, ReactVar> device = {};
    String deviceName = '';

    if (isLong) {
      // Long frame: match by unique address (mfg_id + device_type + device_id)
      final mfgId =
          (addrBytes[0] & 0x3F).toRadixString(16).padLeft(2, '0').toUpperCase();
      final devType =
          addrBytes[1].toRadixString(16).padLeft(2, '0').toUpperCase();
      final devId = addrBytes
          .sublist(2, 5)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      for (final e in table.entries) {
        final eMfg = (e.value['manufacturer_id']?.rawValue ?? '').toUpperCase();
        final eType = (e.value['device_type']?.rawValue ?? '').toUpperCase();
        final eId = (e.value['device_id']?.rawValue ?? '').toUpperCase();
        if (eMfg == mfgId && eType == devType && eId == devId) {
          device = e.value;
          deviceName = e.key;
          break;
        }
      }
    } else {
      // Short frame: match by polling address
      for (final e in table.entries) {
        final addrHex = e.value['polling_address']?.rawValue ?? '01';
        if ((int.tryParse(addrHex, radix: 16) ?? 1) == pollAddr) {
          device = e.value;
          deviceName = e.key;
          break;
        }
      }
    }

    if (device.isEmpty && table.isNotEmpty) {
      // Fallback for address 0 / no match: use device with highest polling address
      int maxAddr = -1;
      for (final e in table.entries) {
        final pa = int.tryParse(e.value['polling_address']?.rawValue ?? '00',
                radix: 16) ??
            0;
        if (pa > maxAddr) {
          maxAddr = pa;
          device = e.value;
          deviceName = e.key;
        }
      }
    }

    final responseBody = HartTransmitter.process(
      command: command,
      requestBody: body,
      device: device,
      onWrite: (col, hex) => writeCell(deviceName, col, hex),
    );

    // Build response address from DEVICE's own fields (not request echo)
    final respAddrBytes = _buildRespAddr(isLong, addrBytes, device);

    globalLog.debug('HART-Serial',
        'Cmd ${command.toRadixString(16).padLeft(2, "0").toUpperCase()} → device=$deviceName, resp=${responseBody.length}B');

    _sendResponse(command, isLong, respAddrBytes, responseBody);
  }

  // ── Build response address from device fields ────────────────────────────
  List<int> _buildRespAddr(
      bool isLong, List<int> reqAddrBytes, Map<String, ReactVar> device) {
    if (isLong) {
      final mfg = int.tryParse(device['manufacturer_id']?.rawValue ?? '00',
              radix: 16) ??
          0;
      final dt =
          int.tryParse(device['device_type']?.rawValue ?? '00', radix: 16) ?? 0;
      final diHex = device['device_id']?.rawValue ?? '000000';
      final diBytes = <int>[];
      for (int i = 0; i + 1 < diHex.length; i += 2) {
        diBytes.add(int.parse(diHex.substring(i, i + 2), radix: 16));
      }
      while (diBytes.length < 3) diBytes.add(0);
      return [
        (reqAddrBytes[0] & 0xC0) | (mfg & 0x3F),
        dt,
        ...diBytes.take(3),
      ];
    } else {
      final pa = int.tryParse(device['polling_address']?.rawValue ?? '00',
              radix: 16) ??
          0;
      return [(reqAddrBytes[0] & 0xC0) | (pa & 0x3F)];
    }
  }

  // ── Response builder ──────────────────────────────────────────────────────
  void _sendResponse(int command, bool isLong, List<int> respAddrBytes,
      List<int> responseBody) {
    final respDelim = isLong ? 0x86 : 0x06;

    final payload = <int>[
      respDelim,
      ...respAddrBytes,
      command,
      responseBody.length,
      ...responseBody,
    ];

    int cs = 0;
    for (final b in payload) cs ^= b;

    final packet = Uint8List.fromList([
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // preamble
      ...payload, cs,
    ]);

    final txHex = packet
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    globalLog.debug('HART-Serial', 'Wrote frame: $txHex');

    try {
      final port = _port;
      if (port == null) return;
      // sp_nonblocking_write may write fewer bytes than requested,
      // so loop until the entire packet has been sent.
      int offset = 0;
      while (offset < packet.length) {
        final remaining = Uint8List.sublistView(packet, offset);
        final written = port.write(remaining);
        if (written <= 0) {
          globalLog.warning(
              'HART-Serial', 'Write stalled at $offset/${packet.length} bytes');
          break;
        }
        offset += written;
      }
    } catch (e) {
      globalLog.warning('HART-Serial', 'Write error: $e');
    }
  }

  /// Returns a list of available serial port names on this machine.
  static List<String> availablePorts() => SerialPort.availablePorts;
}
