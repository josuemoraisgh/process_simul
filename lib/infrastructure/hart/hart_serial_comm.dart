import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../../domain/entities/react_var.dart';
import '../../application/notifiers/log_notifier.dart';
import 'hart_frame.dart';
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
  final HartTransmitter transmitter;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;
  bool _running = false;
  final HartFrameDecoder _decoder = HartFrameDecoder();

  HartSerialServer({
    required this.portName,
    required this.getTable,
    required this.writeCell,
    HartTransmitter? transmitter,
  }) : transmitter = transmitter ?? HartTransmitter.standard();

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
        final frames = _decoder.add(data);
        for (final frame in frames) {
          if (frame.isMasterToSlave) _handleFrame(frame);
        }
        if (_decoder.overflowed) {
          globalLog.warning(
              'HART-Serial', 'Receive buffer limit exceeded; clearing buffer');
          _decoder.clear();
        }
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
    _decoder.clear();

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

  // ── Frame processing (identical logic to HartCommServer._handleFrame) ────
  void _handleFrame(HartFrame frame) {
    final isLong = frame.isLongAddress;
    final addrBytes = isLong ? frame.longAddress : [frame.address];
    final pollAddr = isLong ? 0 : frame.address & 0x3F;
    final command = frame.command;
    final body = frame.body;
    // Ignore our own echoed response frames (delimiter 0x06 or 0x86)
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

    if (device.isEmpty) {
      globalLog.warning(
          'HART-Serial', 'Frame for unknown device address dropped');
      return;
    }

    final responseBody = transmitter.dispatch(
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
      while (diBytes.length < 3) {
        diBytes.add(0);
      }
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
    for (final b in payload) {
      cs ^= b;
    }

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
