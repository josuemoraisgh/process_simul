import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../../domain/entities/react_var.dart';
import '../../application/notifiers/log_notifier.dart';
import 'hart_transmitter.dart';

typedef HartTableGetter = Map<String, Map<String, ReactVar>> Function();
typedef HartCellWriter = void Function(
    String device, String col, String rawHex);

/// TCP server that implements the HART protocol slave simulator.
///
/// Listens on [port] for incoming HART master (e.g. PACTware) connections,
/// parses frames, delegates to [HartTransmitter], and sends back responses.
class HartCommServer {
  final int port;
  final HartTableGetter getTable;
  final HartCellWriter writeCell;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  bool _running = false;

  HartCommServer({
    required this.port,
    required this.getTable,
    required this.writeCell,
  });

  bool get isRunning => _running;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  Future<void> start() async {
    if (_running) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _running = true;
    _server!.listen(_onClient);
    globalLog.info('HART', 'Server started on port $port');
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
    globalLog.info('HART', 'Server stopped');
  }

  // ── Client ────────────────────────────────────────────────────────────────
  void _onClient(Socket socket) {
    _clients.add(socket);
    final addr = '${socket.remoteAddress.address}:${socket.remotePort}';
    globalLog.info('HART', 'Client connected: $addr');
    final buf = <int>[];
    socket.listen(
      (data) {
        buf.addAll(data);
        _flush(buf, socket);
      },
      onDone: () {
        _clients.remove(socket);
        globalLog.info('HART', 'Client disconnected: $addr');
        try {
          socket.destroy();
        } catch (_) {}
      },
      onError: (e) {
        _clients.remove(socket);
        globalLog.warning('HART', 'Client error ($addr): $e');
        try {
          socket.destroy();
        } catch (_) {}
      },
      cancelOnError: true,
    );
  }

  // ── Frame extraction ─────────────────────────────────────────────────────
  void _flush(List<int> buf, Socket socket) {
    // Consume until preamble
    while (buf.isNotEmpty && buf.first != 0xFF) {
      buf.removeAt(0);
    }
    if (buf.length < 6) return;

    // Find end of preamble
    int pos = 0;
    while (pos < buf.length && buf[pos] == 0xFF) {
      pos++;
    }
    if (pos >= buf.length) return;

    final delim = buf[pos];
    final isLong = (delim & 0x80) != 0;
    final addrLen = isLong ? 5 : 1;
    // header: delim(1) + addr(addrLen) + cmd(1) + bytecount(1) = addrLen+3
    final headerEnd = pos + 1 + addrLen + 2;
    if (buf.length <= headerEnd) return;
    final byteCount = buf[headerEnd - 1];
    final totalNeeded = headerEnd + byteCount + 1; // +1 for checksum
    if (buf.length < totalNeeded) return;

    final frame = List<int>.from(buf.sublist(0, totalNeeded));
    buf.removeRange(0, totalNeeded);

    _handleFrame(frame, socket);

    // Process further frames in buffer
    if (buf.isNotEmpty) _flush(buf, socket);
  }

  // ── Frame processing ──────────────────────────────────────────────────────
  void _handleFrame(List<int> raw, Socket socket) {
    int pos = 0;
    while (pos < raw.length && raw[pos] == 0xFF) {
      pos++;
    }
    if (pos >= raw.length) return;

    final delim = raw[pos++];
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

    // Log received frame
    final rxHex = raw
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    globalLog.debug('HART', 'Rx: $rxHex');

    // Generate response
    final responseBody = HartTransmitter.process(
      command: command,
      requestBody: body,
      device: device,
      onWrite: (col, hex) => writeCell(deviceName, col, hex),
    );

    // Build response address from DEVICE's own fields (not request echo)
    final respAddrBytes = _buildRespAddr(isLong, addrBytes, device);

    globalLog.debug('HART',
        'Cmd ${command.toRadixString(16).padLeft(2, "0").toUpperCase()} → device=$deviceName, resp=${responseBody.length}B');

    _sendResponse(socket, command, isLong, respAddrBytes, responseBody);
  }

  // ── Build response address from device fields ────────────────────────────
  List<int> _buildRespAddr(
      bool isLong, List<int> reqAddrBytes, Map<String, ReactVar> device) {
    if (isLong) {
      // Long: master/burst bits from request + device's mfg_id, device_type, device_id
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
      // Short: master/burst bits from request + device's polling address
      final pa = int.tryParse(device['polling_address']?.rawValue ?? '00',
              radix: 16) ??
          0;
      return [(reqAddrBytes[0] & 0xC0) | (pa & 0x3F)];
    }
  }

  // ── Response builder ──────────────────────────────────────────────────────
  void _sendResponse(Socket socket, int command, bool isLong,
      List<int> respAddrBytes, List<int> responseBody) {
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
    globalLog.debug('HART', 'Wrote frame: $txHex');

    try {
      socket.add(packet);
    } catch (_) {}
  }
}
