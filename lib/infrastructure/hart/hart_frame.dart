import 'dart:typed_data';

/// HART protocol frame parser and builder.
///
/// Frame structure:
///   [FF...FF] [Delimiter] [Address] [Command] [ByteCount] [Body] [Checksum]
class HartFrame {
  /// Delimiter byte for short frame (master→slave with polling address).
  static const int kDelimShort = 0x02;

  /// Delimiter byte for long frame (with unique address).
  static const int kDelimLong = 0x82;

  /// Minimum preamble length.
  static const int kMinPreamble = 2;
  static const int maxFrameLength = 272;

  // ── Parsed fields ──────────────────────────────────────────────────────────
  final int delimiter;
  final int command;
  final int address; // polling address (short frame)
  final List<int> longAddress; // 5-byte unique address (long frame)
  final List<int> body;

  HartFrame({
    required this.delimiter,
    required this.command,
    this.address = 0,
    this.longAddress = const [],
    this.body = const [],
  });

  bool get isLongAddress => (delimiter & 0x80) != 0;
  bool get isMasterToSlave => (delimiter & 0x07) == 0x02;

  // ── Builder ─────────────────────────────────────────────────────────────────
  /// Builds the full byte sequence (with 5 preamble bytes + checksum).
  Uint8List build({int preambleCount = 5, bool masterFrame = false}) {
    // Use the frame's own delimiter (supports both request and response types)
    final delim = delimiter;
    // Address bytes
    final addrBytes = isLongAddress ? longAddress : [address & 0xFF];

    final payload = <int>[
      delim,
      ...addrBytes,
      command,
      body.length,
      ...body,
    ];

    // Checksum = XOR of all payload bytes
    int cs = 0;
    for (final b in payload) {
      cs ^= b;
    }

    final preamble = List.filled(preambleCount, 0xFF);
    return Uint8List.fromList([...preamble, ...payload, cs]);
  }

  // ── Parser ───────────────────────────────────────────────────────────────────
  /// Parses a [HartFrame] from raw bytes.  Returns null if invalid.
  static HartFrame? parse(Uint8List bytes) {
    // Skip preamble (0xFF bytes)
    int pos = 0;
    while (pos < bytes.length && bytes[pos] == 0xFF) {
      pos++;
    }
    if (pos < kMinPreamble ||
        pos >= bytes.length ||
        bytes.length > maxFrameLength) {
      return null;
    }

    if (!verifyChecksum(bytes)) return null;

    final delim = bytes[pos++];
    final isLong = (delim & 0x80) != 0;

    if (isLong) {
      if (pos + 5 > bytes.length) return null;
      final longAddr = bytes.sublist(pos, pos + 5);
      pos += 5;
      if (pos + 2 > bytes.length) return null;
      final cmd = bytes[pos++];
      final byteCount = bytes[pos++];
      if (pos + byteCount + 1 != bytes.length) return null;
      final body = bytes.sublist(pos, pos + byteCount);
      return HartFrame(
          delimiter: delim, command: cmd, longAddress: longAddr, body: body);
    } else {
      if (pos >= bytes.length) return null;
      final addr = bytes[pos++];
      if (pos + 2 > bytes.length) return null;
      final cmd = bytes[pos++];
      final byteCount = bytes[pos++];
      if (pos + byteCount + 1 != bytes.length) return null;
      final body = bytes.sublist(pos, pos + byteCount);
      return HartFrame(
          delimiter: delim, command: cmd, address: addr, body: body);
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
    int start = 0;
    while (start < bytes.length && bytes[start] == 0xFF) {
      start++;
    }
    if (start < kMinPreamble || start >= bytes.length - 1) return false;
    int cs = 0;
    for (int i = start; i < bytes.length - 1; i++) {
      cs ^= bytes[i];
    }
    return cs == bytes.last;
  }

  // ── Accumulator for streaming input ─────────────────────────────────────────
  static HartFrameDecoder _legacyDecoder = HartFrameDecoder();
  static final List<HartFrame> _legacyPending = [];

  /// Feed bytes and return a parsed frame when one is complete, or null.
  static HartFrame? feedBytes(List<int> incoming) {
    _legacyPending.addAll(_legacyDecoder.add(incoming));
    return _legacyPending.isEmpty ? null : _legacyPending.removeAt(0);
  }

  static void clearBuffer() {
    _legacyDecoder = HartFrameDecoder();
    _legacyPending.clear();
  }
}

/// Per-connection streaming decoder. It is intentionally independent of
/// command dispatch so parsed frames can later be routed through a command
/// registry without duplicating framing or checksum logic.
class HartFrameDecoder {
  final List<int> _buffer = [];
  bool _overflowed = false;

  bool get overflowed => _overflowed;

  List<HartFrame> add(List<int> incoming) {
    _overflowed = false;
    _buffer.addAll(incoming);
    final frames = <HartFrame>[];

    while (_buffer.isNotEmpty) {
      final preambleStart = _buffer.indexOf(0xFF);
      if (preambleStart < 0) {
        _buffer.clear();
        break;
      }
      if (preambleStart > 0) _buffer.removeRange(0, preambleStart);

      int pos = 0;
      while (pos < _buffer.length && _buffer[pos] == 0xFF) {
        pos++;
      }
      if (pos >= _buffer.length) break;
      if (pos < HartFrame.kMinPreamble) {
        _buffer.removeAt(0);
        continue;
      }

      final isLong = (_buffer[pos] & 0x80) != 0;
      final addressLength = isLong ? 5 : 1;
      final headerEnd = pos + 1 + addressLength + 2;
      if (_buffer.length < headerEnd) break;
      final byteCount = _buffer[headerEnd - 1];
      final totalLength = headerEnd + byteCount + 1;
      if (_buffer.length < totalLength) break;

      final bytes = Uint8List.fromList(_buffer.sublist(0, totalLength));
      _buffer.removeRange(0, totalLength);
      final frame = HartFrame.parse(bytes);
      if (frame != null) frames.add(frame);
    }

    if (_buffer.length > HartFrame.maxFrameLength) {
      _buffer.clear();
      _overflowed = true;
    }
    return frames;
  }

  void clear() => _buffer.clear();
}
