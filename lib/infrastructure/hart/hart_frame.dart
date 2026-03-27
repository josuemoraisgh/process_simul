import 'dart:typed_data';

/// HART protocol frame parser and builder.
///
/// Frame structure:
///   [FF...FF] [Delimiter] [Address] [Command] [ByteCount] [Body] [Checksum]
class HartFrame {
  /// Delimiter byte for short frame (master→slave with polling address).
  static const int kDelimShort = 0x02;

  /// Delimiter byte for long frame (with unique address).
  static const int kDelimLong  = 0x82;

  /// Minimum preamble length.
  static const int kMinPreamble = 2;

  // ── Parsed fields ──────────────────────────────────────────────────────────
  final int  delimiter;
  final int  command;
  final int  address;      // polling address (short frame)
  final List<int> longAddress; // 5-byte unique address (long frame)
  final List<int> body;

  HartFrame({
    required this.delimiter,
    required this.command,
    this.address   = 0,
    this.longAddress = const [],
    this.body      = const [],
  });

  bool get isLongAddress => (delimiter & 0x80) != 0;
  bool get isMasterToSlave => (delimiter & 0x02) != 0;

  // ── Builder ─────────────────────────────────────────────────────────────────
  /// Builds the full byte sequence (with 5 preamble bytes + checksum).
  Uint8List build({int preambleCount = 5, bool masterFrame = false}) {
    final delim = isLongAddress ? kDelimLong : kDelimShort;
    // Address bytes
    final addrBytes = isLongAddress
        ? longAddress
        : [address & 0xFF];

    final payload = <int>[
      delim,
      ...addrBytes,
      command,
      body.length,
      ...body,
    ];

    // Checksum = XOR of all payload bytes
    int cs = 0;
    for (final b in payload) cs ^= b;

    final preamble = List.filled(preambleCount, 0xFF);
    return Uint8List.fromList([...preamble, ...payload, cs]);
  }

  // ── Parser ───────────────────────────────────────────────────────────────────
  /// Parses a [HartFrame] from raw bytes.  Returns null if invalid.
  static HartFrame? parse(Uint8List bytes) {
    // Skip preamble (0xFF bytes)
    int pos = 0;
    while (pos < bytes.length && bytes[pos] == 0xFF) pos++;
    if (pos >= bytes.length) return null;

    final delim = bytes[pos++];
    final isLong = (delim & 0x80) != 0;

    if (isLong) {
      if (pos + 5 > bytes.length) return null;
      final longAddr = bytes.sublist(pos, pos + 5);
      pos += 5;
      if (pos + 2 > bytes.length) return null;
      final cmd = bytes[pos++];
      final byteCount = bytes[pos++];
      if (pos + byteCount + 1 > bytes.length) return null;
      final body = bytes.sublist(pos, pos + byteCount);
      return HartFrame(
          delimiter: delim, command: cmd, longAddress: longAddr, body: body);
    } else {
      if (pos >= bytes.length) return null;
      final addr = bytes[pos++];
      if (pos + 2 > bytes.length) return null;
      final cmd = bytes[pos++];
      final byteCount = bytes[pos++];
      if (pos + byteCount + 1 > bytes.length) return null;
      final body = bytes.sublist(pos, pos + byteCount);
      return HartFrame(delimiter: delim, command: cmd, address: addr, body: body);
    }
  }

  // ── Response builder ─────────────────────────────────────────────────────────
  /// Creates a response frame for [command] addressed back to the master.
  static HartFrame response({
    required int command,
    required bool longAddress,
    required int address,
    List<int> longAddr = const [],
    required List<int> responseBody,
  }) {
    return HartFrame(
      delimiter: longAddress ? 0x86 : 0x06, // slave response delimiter
      command: command,
      address: address,
      longAddress: longAddr,
      body: responseBody,
    );
  }

  // ── Checksum helper ──────────────────────────────────────────────────────────
  static bool verifyChecksum(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    int cs = 0;
    for (int i = 0; i < bytes.length - 1; i++) cs ^= bytes[i];
    return cs == bytes.last;
  }

  // ── Accumulator for streaming input ─────────────────────────────────────────
  static List<int> _buf = [];

  /// Feed bytes and return a parsed frame when one is complete, or null.
  static HartFrame? feedBytes(List<int> incoming) {
    _buf.addAll(incoming);
    // Look for preamble start
    while (_buf.isNotEmpty && _buf[0] != 0xFF) _buf.removeAt(0);
    if (_buf.length < 5) return null;
    // Skip all preamble bytes
    int pos = 0;
    while (pos < _buf.length && _buf[pos] == 0xFF) pos++;
    if (pos >= _buf.length) return null;
    // Determine frame type
    final delim = _buf[pos];
    final isLong = (delim & 0x80) != 0;
    final addrLen = isLong ? 5 : 1;
    final headerLen = 1 + addrLen + 2; // delim + addr + cmd + bytecount
    if (_buf.length < pos + headerLen) return null;
    final byteCount = _buf[pos + 1 + addrLen + 1];
    final totalNeeded = pos + headerLen + byteCount + 1;
    if (_buf.length < totalNeeded) return null;
    final frameBytes = Uint8List.fromList(_buf.sublist(0, totalNeeded));
    _buf = _buf.sublist(totalNeeded);
    return parse(frameBytes);
  }

  static void clearBuffer() => _buf = [];
}
