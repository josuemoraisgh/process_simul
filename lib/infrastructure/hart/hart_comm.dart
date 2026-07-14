import 'dart:io';
import 'dart:typed_data';
import '../../domain/entities/react_var.dart';
import '../../application/notifiers/log_notifier.dart';
import 'hart_frame.dart';
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
  final InternetAddress bindAddress;
  final int maxClients;
  final HartTableGetter getTable;
  final HartCellWriter writeCell;
  final HartTransmitter transmitter;

  ServerSocket? _server;
  final List<Socket> _clients = [];
  bool _running = false;

  HartCommServer({
    required this.port,
    InternetAddress? bindAddress,
    this.maxClients = 32,
    required this.getTable,
    required this.writeCell,
    HartTransmitter? transmitter,
  })  : bindAddress = bindAddress ?? InternetAddress.loopbackIPv4,
        transmitter = transmitter ?? HartTransmitter.standard();

  bool get isRunning => _running;
  int get boundPort => _server?.port ?? port;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
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
    globalLog.info('HART', 'Server started on port $boundPort');
  }

  Future<void> stop() async {
    _running = false;
    for (final c in List<Socket>.from(_clients)) {
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
    if (_clients.length >= maxClients) {
      globalLog.warning('HART', 'Connection limit reached; rejecting client');
      socket.destroy();
      return;
    }
    _clients.add(socket);
    final addr = '${socket.remoteAddress.address}:${socket.remotePort}';
    globalLog.info('HART', 'Client connected: $addr');
    final decoder = HartFrameDecoder();
    socket.listen(
      (data) {
        final frames = decoder.add(data);
        for (final frame in frames) {
          if (frame.isMasterToSlave) _handleFrame(frame, socket);
        }
        if (decoder.overflowed) {
          globalLog.warning(
              'HART', 'Receive buffer limit exceeded; closing client');
          _clients.remove(socket);
          socket.destroy();
        }
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

  // ── Frame processing ──────────────────────────────────────────────────────
  void _handleFrame(HartFrame frame, Socket socket) {
    final isLong = frame.isLongAddress;
    final addrBytes = isLong ? frame.longAddress : [frame.address];
    final pollAddr = isLong ? 0 : frame.address & 0x3F;
    final command = frame.command;
    final body = frame.body;

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
      globalLog.warning('HART', 'Frame for unknown device address dropped');
      return;
    }

    // Generate response
    final responseBody = transmitter.dispatch(
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
