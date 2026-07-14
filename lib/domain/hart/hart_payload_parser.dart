import 'dart:typed_data';

final class HartPayloadException implements Exception {
  const HartPayloadException(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() => 'HartPayloadException($message, offset: $offset)';
}

/// Shared validation and encoding boundary for every HART command.
final class HartPayloadCodec {
  const HartPayloadCodec({this.maxPayloadBytes = 255});

  final int maxPayloadBytes;

  HartPayloadReader reader(Iterable<int> payload) {
    final bytes = payload.toList(growable: false);
    if (bytes.length > maxPayloadBytes) {
      throw HartPayloadException('payload exceeds $maxPayloadBytes bytes');
    }
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] < 0 || bytes[i] > 0xff) {
        throw HartPayloadException('value is not a byte', offset: i);
      }
    }
    return HartPayloadReader._(Uint8List.fromList(bytes));
  }

  List<int> hexToBytes(String value) {
    final hex = value.replaceAll(' ', '');
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      throw const HartPayloadException('invalid hexadecimal value');
    }
    return List.unmodifiable([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  String bytesToHex(Iterable<int> bytes) => reader(bytes)
      .readRemaining()
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

final class HartPayloadReader {
  HartPayloadReader._(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int get offset => _offset;
  int get remaining => _bytes.length - _offset;

  int readUint8() => readBytes(1).single;

  List<int> readBytes(int count) {
    if (count < 0 || count > remaining) {
      throw HartPayloadException(
        'requested $count bytes but only $remaining remain',
        offset: _offset,
      );
    }
    final result = Uint8List.fromList(_bytes.sublist(_offset, _offset + count));
    _offset += count;
    return List.unmodifiable(result);
  }

  List<int> readRemaining() => readBytes(remaining);
}
