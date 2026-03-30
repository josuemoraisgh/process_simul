import 'dart:math' as math;
import '../../domain/entities/react_var.dart';
import 'hart_type_converter.dart';

/// Processes HART commands for a single device and returns the response body.
///
/// Implements the core HART universal commands (0-21) following
/// the original Python hrt_transmitter_v6.py DSL.
class HartTransmitter {
  HartTransmitter._();

  // ── Main entry point ─────────────────────────────────────────────────────────

  /// Process [command] with [requestBody] for [device] variable map.
  /// Returns the response body bytes, or null if unsupported.
  static List<int> process({
    required int command,
    required List<int> requestBody,
    required Map<String, ReactVar> device,
    required Function(String col, String rawHex) onWrite,
  }) {
    final cmd = command.toRadixString(16).toUpperCase().padLeft(2, '0');
    switch (cmd) {
      case '00':
        return _cmd00(device);
      case '01':
        return _cmd01(device);
      case '02':
        return _cmd02(device);
      case '03':
        return _cmd03(device);
      case '04':
        return _cmd04(device);
      case '06':
        return _cmd06(device, requestBody, onWrite);
      case '07':
        return _cmd07(device);
      case '0B':
        return _cmd0B(device, requestBody);
      case '0C':
        return _cmd0C(device);
      case '0D':
        return _cmd0D(device);
      case '0E':
        return _cmd0E(device);
      case '0F':
        return _cmd0F(device);
      case '10':
        return _cmd10(device);
      case '11':
        return _cmd11(device, requestBody, onWrite);
      case '12':
        return _cmd12(device, requestBody, onWrite);
      case '13':
        return _cmd13(device);
      case '15':
        return _cmd15(device, requestBody, onWrite);
      default:
        return _errResponse(64); // Command not implemented
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static List<int> _getHex(Map<String, ReactVar> dev, String col) {
    final v = dev[col];
    if (v == null) return [];
    final hex = v.evaluatedHex.isEmpty ? v.rawValue : v.evaluatedHex;
    return _hexToBytes(hex);
  }

  static List<int> _hexToBytes(String hex) {
    final h = hex.replaceAll(' ', '');
    final result = <int>[];
    for (int i = 0; i < h.length - 1; i += 2) {
      result.add(int.parse(h.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static List<int> _buildResponse(
      List<int> statusBytes, List<List<int>> fields) {
    return [...statusBytes, ...fields.expand((f) => f)];
  }

  static List<int> _errResponse(int code) => [code, 0x00];

  static List<int> _ok() => [0x00, 0x00];

  // ── Identity block ────────────────────────────────────────────────────────
  static List<int> _identityBlock(Map<String, ReactVar> dev) => [
        0xFE,
        ..._getHex(dev, 'manufacturer_id'),
        ..._getHex(dev, 'device_type'),
        ..._getHex(dev, 'request_preambles'),
        ..._getHex(dev, 'hart_revision'),
        ..._getHex(dev, 'software_revision'),
        ..._getHex(dev, 'transmitter_revision'),
        ..._getHex(dev, 'hardware_revision'),
        ..._getHex(dev, 'device_flags'),
        ..._getHex(dev, 'device_id'),
      ];

  // ── Commands ──────────────────────────────────────────────────────────────

  /// Command 00: Read unique identifier.
  static List<int> _cmd00(Map<String, ReactVar> dev) {
    return _buildResponse(_getHex(dev, 'error_code'), [_identityBlock(dev)]);
  }

  /// Command 01: Read primary variable.
  static List<int> _cmd01(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'PROCESS_VARIABLE'),
    ]);
  }

  /// Command 02: Read loop current and percent of range.
  static List<int> _cmd02(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'loop_current'),
      _getHex(dev, 'percent_of_range'),
    ]);
  }

  /// Command 03: Read dynamic variables and loop current.
  static List<int> _cmd03(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'loop_current'),
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'PROCESS_VARIABLE'),
      // SV, TV, QV (repeat PV for simplicity)
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'PROCESS_VARIABLE'),
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'PROCESS_VARIABLE'),
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'PROCESS_VARIABLE'),
    ]);
  }

  /// Command 04: Read current and percent of range (similar to 02).
  static List<int> _cmd04(Map<String, ReactVar> dev) => _cmd02(dev);

  /// Command 06: Write polling address.
  static List<int> _cmd06(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.isNotEmpty) {
      final hex = body[0].toRadixString(16).padLeft(2, '0').toUpperCase();
      onWrite('polling_address', hex);
    }
    return _buildResponse(_ok(), [_getHex(dev, 'polling_address')]);
  }

  /// Command 07: Read loop configuration.
  static List<int> _cmd07(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'polling_address'),
      _getHex(dev, 'loop_current_mode'),
    ]);
  }

  /// Command 0B (11): Read unique identifier associated with tag.
  static List<int> _cmd0B(Map<String, ReactVar> dev, List<int> body) {
    // Compare body (tag bytes) with stored tag
    final tagHex = dev['tag']?.evaluatedHex ?? dev['tag']?.rawValue ?? '';
    final bodyHex = body
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final match = tagHex.toUpperCase() == bodyHex;
    return [match ? 0x00 : 0x01, ..._identityBlock(dev)];
  }

  /// Command 0C (12): Read message.
  static List<int> _cmd0C(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [_getHex(dev, 'message')]);
  }

  /// Command 0D (13): Read tag, descriptor, date.
  static List<int> _cmd0D(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'tag'),
      _getHex(dev, 'descriptor'),
      _getHex(dev, 'date'),
    ]);
  }

  /// Command 0E (14): Read primary variable sensor info.
  static List<int> _cmd0E(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'sensor1_serial_number'),
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'pressure_upper_range_limit'),
      _getHex(dev, 'pressure_lower_range_limit'),
      _getHex(dev, 'pressure_minimum_span'),
    ]);
  }

  /// Command 0F (15): Read output info.
  static List<int> _cmd0F(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [
      _getHex(dev, 'alarm_selection_code'),
      _getHex(dev, 'transfer_function_code'),
      _getHex(dev, 'process_variable_unit_code'),
      _getHex(dev, 'upper_range_value'),
      _getHex(dev, 'lower_range_value'),
      _getHex(dev, 'pressure_damping_value'),
      _getHex(dev, 'write_protect_code'),
      _getHex(dev, 'manufacturer_id'),
      _getHex(dev, 'analog_output_numbers_code'),
    ]);
  }

  /// Command 10 (16): Read final assembly number.
  static List<int> _cmd10(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [_getHex(dev, 'final_assembly_number')]);
  }

  /// Command 11 (17): Write message.
  static List<int> _cmd11(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.isNotEmpty) {
      final hex = body
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      onWrite('message', hex);
    }
    return _buildResponse(_ok(), []);
  }

  /// Command 12 (18): Write tag, descriptor, date.
  static List<int> _cmd12(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.length >= 21) {
      final tag = body
          .sublist(0, 6)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final desc = body
          .sublist(6, 18)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final date = body
          .sublist(18, 21)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      onWrite('tag', tag);
      onWrite('descriptor', desc);
      onWrite('date', date);
    }
    return _buildResponse(_ok(), []);
  }

  /// Command 13 (19): Write final assembly number.
  static List<int> _cmd13(Map<String, ReactVar> dev) {
    return _buildResponse(_ok(), [_getHex(dev, 'final_assembly_number')]);
  }

  /// Command 15 (21): Read all device variables.
  static List<int> _cmd15(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    // Write range values if body provides them
    if (body.length >= 17) {
      onWrite('alarm_selection_code',
          body[0].toRadixString(16).padLeft(2, '0').toUpperCase());
      onWrite('transfer_function_code',
          body[1].toRadixString(16).padLeft(2, '0').toUpperCase());
      onWrite('process_variable_unit_code',
          body[2].toRadixString(16).padLeft(2, '0').toUpperCase());
      final upperHex = body
          .sublist(3, 7)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final lowerHex = body
          .sublist(7, 11)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      onWrite('upper_range_value', upperHex);
      onWrite('lower_range_value', lowerHex);
    }
    return _cmd0F(dev);
  }

  // ── Expression evaluator helpers ─────────────────────────────────────────────

  /// Simple expression evaluator for percent_of_range and PROCESS_VARIABLE.
  /// Supports: +, -, *, /, numeric literals, HART.device.col references.
  static double evaluateExpr(
      String expr, Map<String, Map<String, ReactVar>> allDevices) {
    try {
      String resolved = expr;
      // Replace HART.DEVICE.COL references
      resolved = resolved.replaceAllMapped(
        RegExp(r'HART\.(\w+)\.(\w+)'),
        (m) {
          final device = m.group(1)!;
          final col = m.group(2)!;
          final v = allDevices[device]?[col];
          if (v == null) return '0';
          final hex = v.evaluatedHex.isEmpty ? v.rawValue : v.evaluatedHex;
          if (v.typeStr.toUpperCase().contains('FLOAT') ||
              v.typeStr == 'SREAL') {
            return HartTypeConverter.hexToDouble(hex).toString();
          }
          try {
            return int.parse(hex, radix: 16).toString();
          } catch (_) {
            return '0';
          }
        },
      );
      // Also handle int() wrapping
      resolved = resolved.replaceAllMapped(
        RegExp(r'int\(([^)]+)\)'),
        (m) => _evalSimple(m.group(1)!).truncate().toString(),
      );
      return _evalSimple(resolved);
    } catch (_) {
      return 0.0;
    }
  }

  static double _evalSimple(String expr) {
    expr = expr.trim();
    if (expr.isEmpty) return 0.0;

    // Strip balanced outer parentheses
    if (expr.startsWith('(') && expr.endsWith(')')) {
      int d = 0;
      bool balanced = true;
      for (int i = 0; i < expr.length - 1; i++) {
        if (expr[i] == '(') d++;
        if (expr[i] == ')') d--;
        if (d == 0) {
          balanced = false;
          break;
        }
      }
      if (balanced) return _evalSimple(expr.substring(1, expr.length - 1));
    }

    // Level 1: + - (scan right-to-left)
    int depth = 0;
    for (int i = expr.length - 1; i >= 1; i--) {
      if (expr[i] == ')') depth++;
      if (expr[i] == '(') depth--;
      if (depth == 0 && (expr[i] == '+' || expr[i] == '-')) {
        // Skip if part of scientific notation (e.g. 1.5e-3)
        if (i > 1 && (expr[i - 1] == 'e' || expr[i - 1] == 'E')) continue;
        final left = _evalSimple(expr.substring(0, i));
        final right = _evalSimple(expr.substring(i + 1));
        return expr[i] == '+' ? left + right : left - right;
      }
    }

    // Level 2: * / but NOT ** (scan right-to-left)
    depth = 0;
    for (int i = expr.length - 1; i >= 1; i--) {
      if (expr[i] == ')') depth++;
      if (expr[i] == '(') depth--;
      if (depth == 0) {
        if (expr[i] == '/') {
          final left = _evalSimple(expr.substring(0, i));
          final right = _evalSimple(expr.substring(i + 1));
          return right != 0 ? left / right : 0.0;
        }
        if (expr[i] == '*' &&
            (i + 1 >= expr.length || expr[i + 1] != '*') &&
            (expr[i - 1] != '*')) {
          final left = _evalSimple(expr.substring(0, i));
          final right = _evalSimple(expr.substring(i + 1));
          return left * right;
        }
      }
    }

    // Level 3: ** power (scan left-to-right for right-associativity)
    depth = 0;
    for (int i = 0; i < expr.length - 1; i++) {
      if (expr[i] == '(') depth++;
      if (expr[i] == ')') depth--;
      if (depth == 0 && expr[i] == '*' && expr[i + 1] == '*') {
        final left = _evalSimple(expr.substring(0, i));
        final right = _evalSimple(expr.substring(i + 2));
        return math.pow(left, right).toDouble();
      }
    }

    // Unary minus / plus
    if (expr.startsWith('-')) return -_evalSimple(expr.substring(1));
    if (expr.startsWith('+')) return _evalSimple(expr.substring(1));

    // Function calls: fn(args)
    final fnRe = RegExp(r'^(math\.sqrt|sqrt|exp|abs|log|ln|pow)\(');
    final fnMatch = fnRe.firstMatch(expr);
    if (fnMatch != null) {
      final fn = fnMatch.group(1)!;
      final start = fn.length + 1;
      int d = 1, end = start;
      while (end < expr.length && d > 0) {
        if (expr[end] == '(') d++;
        if (expr[end] == ')') d--;
        end++;
      }
      final argStr = expr.substring(start, end - 1);
      // pow(a,b) has two args
      if (fn == 'pow') {
        final commaIdx = _findTopLevelComma(argStr);
        if (commaIdx > 0) {
          final a = _evalSimple(argStr.substring(0, commaIdx));
          final b = _evalSimple(argStr.substring(commaIdx + 1));
          return math.pow(a, b).toDouble();
        }
      }
      final arg = _evalSimple(argStr);
      return switch (fn) {
        'exp' => math.exp(arg),
        'sqrt' || 'math.sqrt' => math.sqrt(arg.clamp(0, double.infinity)),
        'abs' => arg.abs(),
        'log' || 'ln' => arg > 0 ? math.log(arg) : 0.0,
        _ => arg,
      };
    }

    return double.tryParse(expr) ?? 0.0;
  }

  /// Finds the first comma at depth 0 in [s].
  static int _findTopLevelComma(String s) {
    int d = 0;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '(') d++;
      if (s[i] == ')') d--;
      if (d == 0 && s[i] == ',') return i;
    }
    return -1;
  }
}
