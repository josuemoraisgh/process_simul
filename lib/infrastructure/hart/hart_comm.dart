import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import '../../domain/entities/react_var.dart';
import 'hart_transmitter.dart';

typedef HartTableGetter = Map<String, Map<String, ReactVar>> Function();
typedef HartCellWriter = void Function(String device, String col, String rawHex);

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
  }

  Future<void> stop() async {
    _running = false;
    for (final c in _clients) {
      try { c.destroy(); } catch (_) {}
    }
    _clients.clear();
    await _server?.close();
    _server = null;
  }

  // ── Client ────────────────────────────────────────────────────────────────
  void _onClient(Socket socket) {
    _clients.add(socket);
    final buf = <int>[];
    socket.listen(
      (data) {
        buf.addAll(data);
        _flush(buf, socket);
      },
      onDone: () {
        _clients.remove(socket);
        try { socket.destroy(); } catch (_) {}
      },
      onError: (_) {
        _clients.remove(socket);
        try { socket.destroy(); } catch (_) {}
      },
      cancelOnError: true,
    );
  }

  // ── Frame extraction ─────────────────────────────────────────────────────
  void _flush(List<int> buf, Socket socket) {
    // Consume until preamble
    while (buf.isNotEmpty && buf.first != 0xFF) buf.removeAt(0);
    if (buf.length < 6) return;

    // Find end of preamble
    int pos = 0;
    while (pos < buf.length && buf[pos] == 0xFF) pos++;
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
    while (pos < raw.length && raw[pos] == 0xFF) pos++;
    if (pos >= raw.length) return;

    final delim   = raw[pos++];
    final isLong  = (delim & 0x80) != 0;
    int pollAddr  = 0;
    List<int> longAddr = [];

    if (isLong) {
      if (pos + 5 > raw.length) return;
      longAddr = List.from(raw.sublist(pos, pos + 5));
      pos += 5;
      pollAddr = longAddr[1] & 0x3F; // use short-address byte for routing
    } else {
      if (pos >= raw.length) return;
      pollAddr = raw[pos++] & 0x3F;
    }

    if (pos + 2 > raw.length) return;
    final command   = raw[pos++];
    final byteCount = raw[pos++];
    if (pos + byteCount > raw.length) return;
    final body = raw.sublist(pos, pos + byteCount);

    // Route to correct device
    final table = getTable();
    Map<String, ReactVar> device = {};
    String deviceName = '';
    for (final e in table.entries) {
      final addrHex = e.value['polling_address']?.rawValue ?? '01';
      if ((int.tryParse(addrHex, radix: 16) ?? 1) == pollAddr) {
        device = e.value;
        deviceName = e.key;
        break;
      }
    }
    if (device.isEmpty && table.isNotEmpty) {
      device     = table.values.first;
      deviceName = table.keys.first;
    }

    // Generate response
    final responseBody = HartTransmitter.process(
      command: command,
      requestBody: body,
      device: device,
      onWrite: (col, hex) => writeCell(deviceName, col, hex),
    );

    _sendResponse(socket, command, pollAddr, isLong, longAddr, responseBody);
  }

  // ── Response builder ──────────────────────────────────────────────────────
  void _sendResponse(Socket socket, int command, int pollAddr, bool isLong,
      List<int> longAddr, List<int> responseBody) {
    // Slave response delimiter: 0x06 (short) or 0x86 (long)
    final respDelim = isLong ? 0x86 : 0x06;
    final addrBytes = isLong ? longAddr : [pollAddr];

    final payload = <int>[
      respDelim, ...addrBytes, command,
      responseBody.length, ...responseBody,
    ];

    int cs = 0;
    for (final b in payload) cs ^= b;

    final packet = Uint8List.fromList([
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // preamble
      ...payload, cs,
    ]);

    try { socket.add(packet); } catch (_) {}
  }
}
