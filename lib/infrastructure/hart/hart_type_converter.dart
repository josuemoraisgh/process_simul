import 'dart:typed_data';
import 'dart:math' as math;

/// Converts between hex strings and human-readable engineering values,
/// mirroring the Python hrt_type.py implementation.
class HartTypeConverter {
  HartTypeConverter._();

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Hex → engineering/human value as a [String].
  ///
  /// For ENUM types, pass [enumMap] with { hexKey → description }.
  /// For BIT_ENUM types, pass [bitEnumMap] with { mask → description }.
  static String hexToHuman(
    String hex,
    String typeStr, {
    Map<String, String>? enumMap,
    Map<int, String>? bitEnumMap,
  }) {
    try {
      final t = typeStr.toUpperCase();
      if (t.contains('FLOAT') || t == 'SREAL') return _sreal2human(hex);
      if (t.contains('UNSIGNED')) return _uint2human(hex);
      if (t.contains('INTEGER')) return _int2human(hex);
      if (t.contains('PACKED')) return _pascii2human(hex);
      if (t.contains('DATE')) return _date2human(hex);
      if (t.contains('TIME')) return _time2human(hex);
      if (t.contains('BOOL')) return hex;
      if (t.contains('BIT_ENUM')) {
        if (bitEnumMap != null && bitEnumMap.isNotEmpty) {
          return _bitEnum2human(hex, bitEnumMap);
        }
        return hex;
      }
      if (t.contains('ENUM')) {
        if (enumMap != null && enumMap.isNotEmpty) {
          return _enum2human(hex, enumMap);
        }
        return hex;
      }
      return hex;
    } catch (_) {
      return hex;
    }
  }

  /// Engineering/human value [String] → hex.
  static String humanToHex(
    String value,
    String typeStr,
    int byteSize, {
    Map<String, String>? enumMap,
    Map<int, String>? bitEnumMap,
  }) {
    try {
      final t = typeStr.toUpperCase();
      if (t.contains('FLOAT') || t == 'SREAL') {
        return _human2sreal(double.parse(value));
      }
      if (t.contains('UNSIGNED')) {
        return _human2uint(int.parse(value), byteSize);
      }
      if (t.contains('INTEGER')) return _human2int(int.parse(value), byteSize);
      if (t.contains('PACKED')) return _human2pascii(value, byteSize);
      if (t.contains('DATE')) return _human2date(value, byteSize);
      if (t.contains('BOOL')) return value;
      if (t.contains('BIT_ENUM')) {
        if (bitEnumMap != null && bitEnumMap.isNotEmpty) {
          return _human2bitEnum(value, bitEnumMap, byteSize);
        }
        return value;
      }
      if (t.contains('ENUM')) {
        if (enumMap != null && enumMap.isNotEmpty) {
          return _human2enum(value, enumMap, byteSize);
        }
        return value;
      }
      return value;
    } catch (_) {
      return value;
    }
  }

  // ── ENUM lookup (supports range keys like "F0-F9") ──────────────────────────
  static String _enum2human(String hex, Map<String, String> map) {
    final hexUp = hex.toUpperCase().replaceFirst(RegExp(r'^0+'), '');
    final normalised = hexUp.isEmpty ? '0' : hexUp;
    // Exact match first
    for (final entry in map.entries) {
      if (entry.key.toUpperCase() == hex.toUpperCase()) return entry.value;
      if (entry.key.toUpperCase() == normalised) return entry.value;
    }
    // Range match "XX-YY"
    final intVal = int.tryParse(hex, radix: 16);
    if (intVal != null) {
      for (final entry in map.entries) {
        final key = entry.key.toUpperCase();
        if (key.contains('-')) {
          final parts = key.split('-');
          if (parts.length == 2) {
            final lo = int.tryParse(parts[0], radix: 16);
            final hi = int.tryParse(parts[1], radix: 16);
            if (lo != null && hi != null && intVal >= lo && intVal <= hi) {
              return entry.value;
            }
          }
        }
      }
    }
    return hex; // fallback to raw hex
  }

  static String _human2enum(
      String value, Map<String, String> map, int byteSize) {
    // If value is already a valid hex string, return it
    final intVal = int.tryParse(value, radix: 16);
    if (intVal != null) return value;
    // Reverse lookup by description
    for (final entry in map.entries) {
      if (entry.value == value) {
        final k = entry.key;
        if (k.contains('-')) return k.split('-').first;
        return k.padLeft(byteSize * 2, '0').toUpperCase();
      }
    }
    return value;
  }

  // ── BIT_ENUM lookup (bitwise AND) ───────────────────────────────────────────
  static String _bitEnum2human(String hex, Map<int, String> map) {
    final intVal = int.tryParse(hex, radix: 16) ?? 0;
    if (intVal == 0) {
      return map.containsKey(0) ? map[0]! : '0';
    }
    final labels = <String>[];
    for (final entry in map.entries) {
      if (entry.key == 0) continue;
      if ((intVal & entry.key) == entry.key) {
        labels.add(entry.value);
      }
    }
    return labels.isEmpty ? hex : labels.join(' | ');
  }

  static String _human2bitEnum(
      String value, Map<int, String> map, int byteSize) {
    // If value is already a valid hex string, return it
    final intVal = int.tryParse(value, radix: 16);
    if (intVal != null) return value;
    // Reverse lookup: OR together all matching bit masks
    int result = 0;
    final parts = value.split('|').map((s) => s.trim()).toList();
    for (final part in parts) {
      for (final entry in map.entries) {
        if (entry.value.trim() == part) {
          result |= entry.key;
        }
      }
    }
    return result.toRadixString(16).padLeft(byteSize * 2, '0').toUpperCase();
  }

  // ── IEEE-754 SREAL ──────────────────────────────────────────────────────────
  static String _sreal2human(String hex) {
    final h = hex.padLeft(8, '0');
    final bytes = Uint8List.fromList([
      int.parse(h.substring(0, 2), radix: 16),
      int.parse(h.substring(2, 4), radix: 16),
      int.parse(h.substring(4, 6), radix: 16),
      int.parse(h.substring(6, 8), radix: 16),
    ]);
    final bd = ByteData.sublistView(bytes);
    final v = bd.getFloat32(0, Endian.big);
    if (v.isNaN || v.isInfinite) return '0.0000';
    if (v.abs() >= 0.0001) return v.toStringAsFixed(4);
    return v.toStringAsExponential(2);
  }

  static String _human2sreal(double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.big);
    return bd.buffer
        .asUint8List()
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  // ── UNSIGNED ────────────────────────────────────────────────────────────────
  static String _uint2human(String hex) {
    if (hex.isEmpty) return '0';
    return int.parse(hex, radix: 16).toString();
  }

  static String _human2uint(int v, int byteSize) {
    if (v < 0) v = 0;
    return v.toRadixString(16).padLeft(byteSize * 2, '0').toUpperCase();
  }

  // ── INTEGER (signed) ────────────────────────────────────────────────────────
  static String _int2human(String hex) {
    int v = int.parse(hex, radix: 16);
    if (v >= 0x8000) v -= 0x10000;
    return v.toString();
  }

  static String _human2int(int v, int byteSize) {
    if (v < 0) v = (v + (1 << 16)) & 0xFFFF;
    return v.toRadixString(16).padLeft(byteSize * 2, '0').toUpperCase();
  }

  // ── PACKED ASCII (6-bit encoding) ───────────────────────────────────────────
  static String _pascii2human(String hex) {
    if (hex.isEmpty) return '';
    final bigVal = BigInt.parse(hex, radix: 16);
    final totalBits = hex.length * 4;
    final numChars = totalBits ~/ 6;
    final chars = <String>[];
    for (int i = 0; i < numChars; i++) {
      final shift = totalBits - 6 * (i + 1);
      int sixBit = ((bigVal >> shift) & BigInt.from(0x3F)).toInt();
      // Toggle bit-6: if bit-5 == 1 clear bit-6, else set bit-6
      if ((sixBit >> 5) & 1 == 1) {
        sixBit &= 0x3F; // bit6=0 already since it's a 6-bit value
        sixBit |= 0x00; // no-op but keep explicit
      } else {
        sixBit |= 0x40;
      }
      final ch = sixBit & 0x7F;
      if (ch >= 0x20 && ch <= 0x7E) {
        chars.add(String.fromCharCode(ch));
      } else {
        chars.add(' ');
      }
    }
    return chars.join().trimRight();
  }

  static String _human2pascii(String value, int byteSize) {
    if (byteSize <= 0) return '';
    final maxChars = (byteSize * 8) ~/ 6;
    // Normalize: uppercase, replace out-of-range with space
    final norm = value.toUpperCase().padRight(maxChars, ' ');
    final chars = norm.substring(0, math.min(norm.length, maxChars));
    // Convert each char to 6-bit value
    final sixBits = chars.codeUnits.map((c) {
      final ch = c >= 0x20 && c <= 0x5F ? c : 0x20;
      return ch & 0x3F;
    }).toList();
    // Pack into bytes
    final out = <int>[];
    int acc = 0;
    int accBits = 0;
    for (final v in sixBits) {
      acc = (acc << 6) | v;
      accBits += 6;
      while (accBits >= 8) {
        accBits -= 8;
        out.add((acc >> accBits) & 0xFF);
        acc &= (1 << accBits) - 1;
      }
    }
    if (accBits > 0) out.add((acc << (8 - accBits)) & 0xFF);
    while (out.length < byteSize) {
      out.add(0);
    }
    return out
        .take(byteSize)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  // ── DATE (DD/MM/YYYY) ───────────────────────────────────────────────────────
  static String _date2human(String hex) {
    if (hex.length < 6) return '';
    final day = int.parse(hex.substring(0, 2), radix: 16);
    final mon = int.parse(hex.substring(2, 4), radix: 16);
    final yr = 1900 + int.parse(hex.substring(4, 6), radix: 16);
    return '${day.toString().padLeft(2, '0')}/${mon.toString().padLeft(2, '0')}/$yr';
  }

  static String _human2date(String value, int byteSize) {
    final parts = value.split('/');
    if (parts.length < 3) return '000000';
    final day = int.parse(parts[0]);
    final mon = int.parse(parts[1]);
    final yr = int.parse(parts[2]) - 1900;
    return '${day.toRadixString(16).padLeft(2, '0')}${mon.toRadixString(16).padLeft(2, '0')}${yr.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  // ── TIME ────────────────────────────────────────────────────────────────────
  static String _time2human(String hex) {
    if (hex.length < 8) return '00:00:00';
    final b = [
      int.parse(hex.substring(0, 2), radix: 16),
      int.parse(hex.substring(2, 4), radix: 16),
      int.parse(hex.substring(4, 6), radix: 16),
      int.parse(hex.substring(6, 8), radix: 16),
    ];
    final totalMs = b[0] * 524288 + b[1] * 2048 + b[2] * 8 + b[2] * 0.03125;
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Float helpers ────────────────────────────────────────────────────────────
  static double hexToDouble(String hex) {
    try {
      final h = hex.padLeft(8, '0');
      final bytes = Uint8List.fromList([
        int.parse(h.substring(0, 2), radix: 16),
        int.parse(h.substring(2, 4), radix: 16),
        int.parse(h.substring(4, 6), radix: 16),
        int.parse(h.substring(6, 8), radix: 16),
      ]);
      final v = ByteData.sublistView(bytes).getFloat32(0, Endian.big);
      return v.isNaN || v.isInfinite ? 0.0 : v.toDouble();
    } catch (_) {
      return 0.0;
    }
  }

  static String doubleToHex(double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.big);
    return bd.buffer
        .asUint8List()
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  // ── Helpers for parsing ENUM/BIT_ENUM index from typeStr ────────────────────
  /// Parses "ENUM00" → 0, "ENUM27" → 27. Returns -1 if not an ENUM type.
  static int parseEnumIndex(String typeStr) {
    final m = RegExp(r'ENUM(\d+)', caseSensitive: false).firstMatch(typeStr);
    return m != null ? (int.tryParse(m.group(1)!) ?? -1) : -1;
  }

  /// Parses "BIT_ENUM02" → 2. Returns -1 if not a BIT_ENUM type.
  static int parseBitEnumIndex(String typeStr) {
    final m =
        RegExp(r'BIT_ENUM(\d+)', caseSensitive: false).firstMatch(typeStr);
    return m != null ? (int.tryParse(m.group(1)!) ?? -1) : -1;
  }

  /// Returns true if typeStr is an ENUM or BIT_ENUM type.
  static bool isEnumType(String typeStr) =>
      typeStr.toUpperCase().contains('ENUM');
}
