import 'dart:math' as math;
import '../../domain/entities/react_var.dart';
import 'hart_type_converter.dart';

/// Processes HART commands for a single device and returns the response body.
///
/// Implements the core HART universal commands following
/// the original Python hrt_transmitter_v2.py DSL.
class HartTransmitter {
  HartTransmitter._();

  // ── Main entry point ─────────────────────────────────────────────────────────

  /// Process [command] with [requestBody] for [device] variable map.
  /// Returns the response body bytes, or error frame if unsupported.
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
      case '05':
        return _cmd05(device);
      case '06':
        return _cmd06(device, requestBody, onWrite);
      case '07':
        return _cmd07(device);
      case '08':
        return _cmd08(device);
      case '09':
        return _cmd09(device);
      case '0A':
        return _cmd0A(device);
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
        return _cmd13(device, requestBody, onWrite);
      case '21':
        return _cmd21(device, requestBody);
      case '26':
        return _cmd26(device, onWrite);
      case '28':
        return _cmd28(device, requestBody);
      case '29':
        return _cmd29(device);
      case '2A':
        return _cmd2A(device);
      case '2D':
        return _cmd2D(device);
      case '2E':
        return _cmd2E(device);
      case '50':
        return _cmd50(device);
      case '82':
        return _hexResponse('00000201020101');
      case '84':
        return _hexResponse('000002012543D2000040A99999');
      case '87':
        return _hexResponse('00400201');
      case '88':
        return _hexResponse('700002FFFFFF');
      case '8A':
        return _hexResponse('000002FF');
      case '8C':
        return _hexResponse('7000023941AC33E939000000003942480000FFFF3900000000');
      case '98':
        return <int>[];
      case 'A2':
        return _hexResponse('00000201');
      case 'A4':
        return _hexResponse('0000020200');
      case 'A6':
        return _hexResponse('00000222040000130A270000010B00');
      case 'A8':
        return _hexResponse('00000201FF');
      case 'AD':
        return _hexResponse('0000025454333031313131302D425549314C335030543459');
      case 'B9':
        return _hexResponse('004002');
      case 'BB':
        return _hexResponse('000002FF');
      case 'C6':
        return _hexResponse('00000242480000');
      case 'DF':
        return _hexResponse('00000242C800003B801132B51B057FAC932D1D');
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

  static List<int> _hexResponse(String hex) => _hexToBytes(hex);

  /// Returns device error_code bytes (used as HART response status).
  static List<int> _ec(Map<String, ReactVar> dev) =>
      _getHex(dev, 'error_code');

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

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
  static List<int> _cmd00(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [_identityBlock(dev)]);

  /// Command 01: Read primary variable.
  static List<int> _cmd01(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _getHex(dev, 'process_variable_unit_code'),
        _getHex(dev, 'PROCESS_VARIABLE'),
      ]);

  /// Command 02: Read loop current and percent of range.
  static List<int> _cmd02(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _getHex(dev, 'loop_current'),
        _getHex(dev, 'percent_of_range'),
      ]);

  /// Command 03: Read dynamic variables and loop current.
  static List<int> _cmd03(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _getHex(dev, 'loop_current'),
        _getHex(dev, 'process_variable_unit_code'),
        _getHex(dev, 'PROCESS_VARIABLE'),
        _getHex(dev, 'process_variable_unit_code'),
        _getHex(dev, 'PROCESS_VARIABLE'),
        _getHex(dev, 'process_variable_unit_code'),
        _getHex(dev, 'PROCESS_VARIABLE'),
        _getHex(dev, 'process_variable_unit_code'),
        _getHex(dev, 'PROCESS_VARIABLE'),
      ]);

  /// Command 04: stub — returns only status bytes.
  static List<int> _cmd04(Map<String, ReactVar> dev) => _ec(dev);

  /// Command 05: stub — returns only status bytes.
  static List<int> _cmd05(Map<String, ReactVar> dev) => _ec(dev);

  /// Command 06: Write polling address + loop current mode, echo both back.
  static List<int> _cmd06(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.length >= 2) {
      onWrite('polling_address',
          body[0].toRadixString(16).padLeft(2, '0').toUpperCase());
      onWrite('loop_current_mode',
          body[1].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return _buildResponse(_ec(dev), [
      _getHex(dev, 'polling_address'),
      _getHex(dev, 'loop_current_mode'),
    ]);
  }

  /// Command 07: Read loop configuration.
  static List<int> _cmd07(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _getHex(dev, 'polling_address'),
        _getHex(dev, 'loop_current_mode'),
      ]);

  /// Command 08: Read dynamic variable classifications — returns 4 zero-bytes.
  static List<int> _cmd08(Map<String, ReactVar> dev) =>
      [..._ec(dev), 0x00, 0x00, 0x00, 0x00];

  /// Command 09: stub.
  static List<int> _cmd09(Map<String, ReactVar> dev) => _ec(dev);

  /// Command 0A: stub.
  static List<int> _cmd0A(Map<String, ReactVar> dev) => _ec(dev);

  /// Command 0B (11): Read unique identifier associated with tag.
  static List<int> _cmd0B(Map<String, ReactVar> dev, List<int> body) {
    final tagHex = dev['tag']?.evaluatedHex ?? dev['tag']?.rawValue ?? '';
    final bodyHex = _bytesToHex(body);
    final match = tagHex.toUpperCase() == bodyHex;
    return [match ? 0x00 : 0x01, ..._identityBlock(dev)];
  }

  /// Command 0C (12): Read message.
  static List<int> _cmd0C(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [_getHex(dev, 'message')]);

  /// Command 0D (13): Read tag, descriptor, date.
  static List<int> _cmd0D(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _getHex(dev, 'tag'),
        _getHex(dev, 'descriptor'),
        _getHex(dev, 'date'),
      ]);

  /// Command 0E (14): Read primary variable transducer information.
  static List<int> _cmd0E(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _getHex(dev, 'sensor1_serial_number'),
        _getHex(dev, 'process_variable_unit_code'),
        _getHex(dev, 'pressure_upper_range_limit'),
        _getHex(dev, 'pressure_lower_range_limit'),
        _getHex(dev, 'pressure_minimum_span'),
      ]);

  /// Command 0F (15): Read device/PV output information.
  static List<int> _cmd0F(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
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

  /// Command 10 (16): Read final assembly number.
  static List<int> _cmd10(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [_getHex(dev, 'final_assembly_number')]);

  /// Command 11 (17): Write message — save and echo back.
  static List<int> _cmd11(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    onWrite('message', _bytesToHex(body));
    return [..._ec(dev), ...body];
  }

  /// Command 12 (18): Write tag, descriptor, date — save and echo back.
  /// Body layout: tag=6B, descriptor=12B, date=3B (total 21B).
  static List<int> _cmd12(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.length >= 21) {
      final tagBytes = body.sublist(0, 6);
      final descBytes = body.sublist(6, 18);
      final dateBytes = body.sublist(18, 21);
      onWrite('tag', _bytesToHex(tagBytes));
      onWrite('descriptor', _bytesToHex(descBytes));
      onWrite('date', _bytesToHex(dateBytes));
      return [..._ec(dev), ...tagBytes, ...descBytes, ...dateBytes];
    }
    return _ec(dev);
  }

  /// Command 13 (19): Write final assembly number — save and echo back.
  static List<int> _cmd13(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.length >= 3) {
      final fanBytes = body.sublist(0, 3);
      onWrite('final_assembly_number', _bytesToHex(fanBytes));
      return [..._ec(dev), ...fanBytes];
    }
    return _buildResponse(_ec(dev), [_getHex(dev, 'final_assembly_number')]);
  }

  /// Command 21 (0x21=33): Read device variables.
  /// Body: single code byte, or [count, code0, code1, ...].
  static List<int> _cmd21(Map<String, ReactVar> dev, List<int> body) {
    final List<int> codes;
    if (body.length == 1) {
      codes = [body[0]];
    } else if (body.length >= 2) {
      final n = body[0].clamp(0, body.length - 1);
      codes = body.sublist(1, 1 + n);
    } else {
      codes = [];
    }

    final result = <int>[..._ec(dev)];
    for (final code in codes) {
      if (code == 0x00) {
        result
          ..addAll(_getHex(dev, 'process_variable_unit_code'))
          ..addAll(_getHex(dev, 'PROCESS_VARIABLE'));
      } else {
        // Unit "not used" (0xFA) + NaN as IEEE 754 float
        result.addAll([0xFA, 0x7F, 0xC0, 0x00, 0x00]);
      }
    }
    return result;
  }

  /// Command 26 (0x26): Reset error flags.
  static List<int> _cmd26(
      Map<String, ReactVar> dev, Function(String, String) onWrite) {
    onWrite('config_changed', '00');
    return [
      0x02,
      ..._ec(dev),
      ..._getHex(dev, 'response_code'),
      ..._getHex(dev, 'device_status'),
      ..._getHex(dev, 'comm_status'),
    ];
  }

  /// Command 28 (0x28): Enter/exit fixed current mode — echo requested value.
  static List<int> _cmd28(Map<String, ReactVar> dev, List<int> body) =>
      [..._ec(dev), ...body];

  /// Command 29 (0x29): Perform self test.
  static List<int> _cmd29(Map<String, ReactVar> dev) => [
        ..._getHex(dev, 'response_code'),
        ..._getHex(dev, 'device_status'),
      ];

  /// Command 2A (0x2A): Perform device reset.
  static List<int> _cmd2A(Map<String, ReactVar> dev) => _ec(dev);

  /// Command 2D (0x2D): Trim 4 mA.
  static List<int> _cmd2D(Map<String, ReactVar> dev) => [
        ..._getHex(dev, 'response_code'),
        ..._getHex(dev, 'device_status'),
      ];

  /// Command 2E (0x2E): Trim 20 mA.
  static List<int> _cmd2E(Map<String, ReactVar> dev) => [
        ..._getHex(dev, 'response_code'),
        ..._getHex(dev, 'device_status'),
      ];

  /// Command 50 (0x50): Read dynamic variable assignments.
  static List<int> _cmd50(Map<String, ReactVar> dev) => [
        ..._ec(dev),
        ...(dev['pv_code'] != null ? _getHex(dev, 'pv_code') : [0xFA]),
        ...(dev['sv_code'] != null ? _getHex(dev, 'sv_code') : [0xFA]),
        ...(dev['tv_code'] != null ? _getHex(dev, 'tv_code') : [0xFA]),
        ...(dev['qv_code'] != null ? _getHex(dev, 'qv_code') : [0xFA]),
      ];

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
