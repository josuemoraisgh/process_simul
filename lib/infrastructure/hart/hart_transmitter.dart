import '../../domain/entities/react_var.dart';
import '../../domain/expression/expression_engine.dart';
import '../../domain/hart/hart_command_registry.dart';
import '../../domain/hart/hart_payload_parser.dart';
import 'hart_type_converter.dart';

/// Processes HART commands for a single device and returns the response body.
///
/// Mirrors the Python hrt_transmitter_v6.py COMMANDS dict.
class HartTransmitter {
  HartTransmitter({
    required HartCommandRegistry commands,
    required HartFunctionRegistry functions,
    this.codec = const HartPayloadCodec(),
  })  : _commands = commands,
        _functions = functions;

  factory HartTransmitter.standard() {
    return HartTransmitter(
      commands: standardCommandRegistry(),
      functions: HartFunctionRegistry(),
    );
  }

  static HartCommandRegistry standardCommandRegistry() {
    final commands = HartCommandRegistry(
      onUnknown: (command, context) => _processLegacy(
        command: command,
        requestBody: context.requestBody,
        device: context.device,
        onWrite: context.onWrite,
      ),
    );
    for (final command in _standardCommandCodes) {
      commands.register(FunctionalHartCommandHandler(
        command,
        (context) => _processLegacy(
          command: command,
          requestBody: context.requestBody,
          device: context.device,
          onWrite: context.onWrite,
        ),
      ));
    }
    return commands;
  }

  final HartCommandRegistry _commands;
  final HartFunctionRegistry _functions;
  final HartPayloadCodec codec;

  void registerCommand(HartCommandHandler handler) =>
      _commands.register(handler);

  HartCommandHandler removeCommand(int command) => _commands.remove(command);

  void registerFunction(HartFunction function) => _functions.register(function);

  HartFunction removeFunction(String name) => _functions.remove(name);

  static const _standardCommandCodes = <int>{
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x12,
    0x13,
    0x21,
    0x26,
    0x28,
    0x29,
    0x2A,
    0x2B,
    0x2D,
    0x2E,
    0x48,
    0x50,
    0x80,
    0x82,
    0x84,
    0x85,
    0x87,
    0x88,
    0x8A,
    0x8C,
    0x8E,
    0x98,
    0x9C,
    0xA0,
    0xA2,
    0xA4,
    0xA6,
    0xA8,
    0xAD,
    0xB0,
    0xB1,
    0xB2,
    0xB3,
    0xB4,
    0xB9,
    0xBA,
    0xBB,
    0xBD,
    0xC6,
    0xCC,
    0xDF,
  };

  static final ExpressionEngine _expressionEngine = ExpressionEngine();
  static final HartTransmitter _compatibility = HartTransmitter.standard();

  // ── Main entry point ─────────────────────────────────────────────────────────

  static List<int> process({
    required int command,
    required List<int> requestBody,
    required Map<String, ReactVar> device,
    required Function(String col, String rawHex) onWrite,
  }) =>
      _compatibility.dispatch(
        command: command,
        requestBody: requestBody,
        device: device,
        onWrite: onWrite,
      );

  List<int> dispatch({
    required int command,
    required List<int> requestBody,
    required Map<String, ReactVar> device,
    required HartWrite onWrite,
  }) {
    return _commands.dispatch(
      command,
      HartCommandContext(
        requestBody: requestBody,
        device: device,
        onWrite: onWrite,
        functions: _functions,
        codec: codec,
      ),
    );
  }

  static List<int> _processLegacy({
    required int command,
    required List<int> requestBody,
    required Map<String, ReactVar> device,
    required Function(String col, String rawHex) onWrite,
  }) {
    final cmd = command.toRadixString(16).toUpperCase().padLeft(2, '0');
    switch (cmd) {
      // ── Universal commands ──────────────────────────────────────────────────
      case '00':
        return _cmd00(device);
      case '01':
        return _cmd01(device);
      case '02':
        return _cmd02(device);
      case '03':
        return _cmd03(device);
      case '04':
        return _ec(device);
      case '05':
        return _ec(device);
      case '06':
        return _cmd06(device, requestBody, onWrite);
      case '07':
        return _cmd07(device);
      case '08':
        return [..._ec(device), 0x00, 0x00, 0x00, 0x00];
      case '09':
        return _ec(device);
      case '0A':
        return _ec(device);
      case '0B':
        return _cmd0B(device, requestBody);
      case '0C':
        return _buildResponse(_ec(device), [_g(device, 'message')]);
      case '0D':
        return _buildResponse(_ec(device), [
          _g(device, 'tag'),
          _g(device, 'descriptor'),
          _g(device, 'date'),
        ]);
      case '0E':
        return _buildResponse(_ec(device), [
          _g(device, 'sensor1_serial_number'),
          _g(device, 'process_variable_unit_code'),
          _g(device, 'pressure_upper_range_limit'),
          _g(device, 'pressure_lower_range_limit'),
          _g(device, 'pressure_minimum_span'),
        ]);
      case '0F':
        return _cmd0F(device);
      case '10':
        return _buildResponse(
            _ec(device), [_g(device, 'final_assembly_number')]);
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
        return [..._ec(device), ...requestBody];
      case '29':
        return [..._g(device, 'response_code'), ..._g(device, 'device_status')];
      case '2A':
        return _ec(device);
      case '2B':
        return _buildResponse(_ec(device), [_g(device, 'cmd2B_resp_suffix')]);
      case '2D':
        return [..._g(device, 'response_code'), ..._g(device, 'device_status')];
      case '2E':
        return [..._g(device, 'response_code'), ..._g(device, 'device_status')];
      case '48':
        return _buildResponse(_ec(device), [
          _g(device, 'xmtr_specific_status_0'),
          _g(device, 'xmtr_specific_status_1'),
          _g(device, 'xmtr_specific_status_2'),
        ]);
      case '50':
        return _buildResponse(_ec(device), [
          _g(device, 'transmitter_variable_code_1'),
          _g(device, 'transmitter_variable_code_2'),
          _g(device, 'transmitter_variable_code_3'),
          _g(device, 'transmitter_variable_code_4'),
        ]);
      // ── Vendor / extended ───────────────────────────────────────────────────
      case '80':
        return _cmd80(device);
      case '85':
        return _cmd85(device, requestBody);
      case '88':
        return [
          ..._hexBytes('70'),
          ..._g(device, 'device_status'),
          ..._hexBytes('17'),
          ..._hexBytes('FFFF'),
        ];
      case '8A':
        return [..._ec(device), 0x02, 0xFF];
      case '8C':
        return [
          ..._hexBytes('70'),
          ..._g(device, 'device_status'),
          ..._hexBytes('39'),
          ..._hexBytes('00000000'),
          ..._hexBytes('39'),
          ..._hexBytes('00000000'),
          ..._hexBytes('39'),
          ..._hexBytes('000000000001FF'),
          ..._hexBytes('39'),
          ..._hexBytes('FFFFFFFF'),
        ];
      case '8E':
        return [
          ..._hexBytes('70'),
          ..._g(device, 'device_status'),
          ..._hexBytes('3F800000'),
          ..._hexBytes('3DCCCCCC'),
          ..._hexBytes('0000000000000000'),
          ..._hexBytes('3DCCCCCC'),
        ];
      case '9C':
        return [
          ..._g(device, 'comm_status'),
          ..._g(device, 'device_status'),
          ..._hexBytes('C00000'),
        ];
      case 'A0':
        return _cmdA0(device, requestBody);
      case 'A4':
        return [
          ..._g(device, 'comm_status'),
          ..._g(device, 'device_status'),
          ..._hexBytes('0400'),
        ];
      case 'A6':
        return [
          ..._g(device, 'comm_status'),
          ..._g(device, 'device_status'),
          ..._hexBytes('17010000020000000000000000000300'),
        ];
      case 'AD':
        return _g(device, 'smar_ordering_code');
      case 'B0':
        return [..._ec(device), ..._g(device, 'total_unit_string'), 0x00];
      case 'B1':
        return [..._ec(device), ..._hexBytes('024000')];
      case 'B2':
        return [..._ec(device), ..._hexBytes('000000000000000000000000')];
      case 'B3':
        return [..._ec(device), ..._hexBytes('024000')];
      case 'B4':
        return [..._ec(device), ..._hexBytes('024000')];
      case 'B9':
        return [
          ..._g(device, 'comm_status'),
          ..._g(device, 'device_status'),
          0x02,
        ];
      case 'BA':
        return [
          0x76,
          ..._g(device, 'device_status'),
          ..._g(device, 'upper_range_value'),
          ..._hexBytes('3F800000'),
        ];
      case 'BD':
        return [
          0x76,
          ..._g(device, 'device_status'),
          ..._g(device, 'alarm_selection_code'),
          ..._hexBytes('4E4F4E4520'),
        ];
      case 'CC':
        return [..._ec(device), 0x00];
      case '82':
        return _hexBytes('00000201020101');
      case '84':
        return _hexBytes('000002012543D2000040A99999');
      case '87':
        return _hexBytes('00400201');
      case '98':
        return <int>[];
      case 'A2':
        return _hexBytes('00000201');
      case 'A8':
        return _hexBytes('00000201FF');
      case 'BB':
        return _hexBytes('000002FF');
      case 'C6':
        return _hexBytes('00000242480000');
      case 'DF':
        return _hexBytes('00000242C800003B801132B51B057FAC932D1D');
      default:
        return _errResponse(64); // Command not implemented
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static List<int> _g(Map<String, ReactVar> dev, String col) {
    final v = dev[col];
    if (v == null) return [];
    final hex = v.evaluatedHex.isEmpty ? v.rawValue : v.evaluatedHex;
    return _hexBytes(hex);
  }

  static List<int> _hexBytes(String hex) {
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

  static List<int> _ec(Map<String, ReactVar> dev) => _g(dev, 'error_code');

  static String _bytesToHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  // ── Identity block ────────────────────────────────────────────────────────
  static List<int> _identityBlock(Map<String, ReactVar> dev) => [
        0xFE,
        ..._g(dev, 'manufacturer_id'),
        ..._g(dev, 'device_type'),
        ..._g(dev, 'request_preambles'),
        ..._g(dev, 'hart_revision'),
        ..._g(dev, 'software_revision'),
        ..._g(dev, 'transmitter_revision'),
        ..._g(dev, 'hardware_revision'),
        ..._g(dev, 'device_flags'),
        ..._g(dev, 'device_id'),
      ];

  // ── Commands ──────────────────────────────────────────────────────────────

  static List<int> _cmd00(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [_identityBlock(dev)]);

  static List<int> _cmd01(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _g(dev, 'process_variable_unit_code'),
        _g(dev, 'PROCESS_VARIABLE'),
      ]);

  static List<int> _cmd02(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _g(dev, 'loop_current'),
        _g(dev, 'percent_of_range'),
      ]);

  static List<int> _cmd03(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _g(dev, 'loop_current'),
        _g(dev, 'process_variable_unit_code'),
        _g(dev, 'PROCESS_VARIABLE'),
        _g(dev, 'process_variable_unit_code'),
        _g(dev, 'PROCESS_VARIABLE'),
        _g(dev, 'process_variable_unit_code'),
        _g(dev, 'PROCESS_VARIABLE'),
        _g(dev, 'process_variable_unit_code'),
        _g(dev, 'PROCESS_VARIABLE'),
      ]);

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
      _g(dev, 'polling_address'),
      _g(dev, 'loop_current_mode'),
    ]);
  }

  static List<int> _cmd07(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _g(dev, 'polling_address'),
        _g(dev, 'loop_current_mode'),
      ]);

  /// Command 0B: Compare request body with stored tag; return identity block.
  static List<int> _cmd0B(Map<String, ReactVar> dev, List<int> body) {
    final tagHex = dev['tag']?.evaluatedHex ?? dev['tag']?.rawValue ?? '';
    final match = tagHex.toUpperCase() == _bytesToHex(body);
    return [match ? 0x00 : 0x01, ..._identityBlock(dev)];
  }

  static List<int> _cmd0F(Map<String, ReactVar> dev) =>
      _buildResponse(_ec(dev), [
        _g(dev, 'alarm_selection_code'),
        _g(dev, 'transfer_function_code'),
        _g(dev, 'process_variable_unit_code'),
        _g(dev, 'upper_range_value'),
        _g(dev, 'lower_range_value'),
        _g(dev, 'pressure_damping_value'),
        _g(dev, 'write_protect_code'),
        _g(dev, 'manufacturer_id'),
        _g(dev, 'analog_output_numbers_code'),
      ]);

  /// Command 11: Write message, echo back.
  static List<int> _cmd11(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    onWrite('message', _bytesToHex(body));
    return [..._ec(dev), ...body];
  }

  /// Command 12: Write tag, descriptor, date, echo back.
  /// Body layout (bytes): tag=6, descriptor=12, date=3.
  static List<int> _cmd12(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.length >= 21) {
      onWrite('tag', _bytesToHex(body.sublist(0, 6)));
      onWrite('descriptor', _bytesToHex(body.sublist(6, 18)));
      onWrite('date', _bytesToHex(body.sublist(18, 21)));
      return [..._ec(dev), ...body.sublist(0, 21)];
    }
    return _ec(dev);
  }

  /// Command 13: Write final assembly number, echo back.
  static List<int> _cmd13(Map<String, ReactVar> dev, List<int> body,
      Function(String, String) onWrite) {
    if (body.length >= 3) {
      onWrite('final_assembly_number', _bytesToHex(body.sublist(0, 3)));
      return [..._ec(dev), ...body.sublist(0, 3)];
    }
    return _ec(dev);
  }

  /// Command 21 (0x21): Read device variables.
  /// Codes 00 and 04 return PV; all others return NaN (FA + 7FC00000).
  static List<int> _cmd21(Map<String, ReactVar> dev, List<int> body) {
    final List<int> codes;
    if (body.length == 1) {
      codes = [body[0]];
    } else if (body.length >= 2) {
      final n = body[0].clamp(0, body.length - 1);
      codes = body.sublist(1, 1 + n);
    } else {
      codes = [0x00];
    }

    final result = <int>[..._ec(dev)];
    for (final code in codes) {
      if (code == 0x00 || code == 0x04) {
        result
          ..addAll(_g(dev, 'process_variable_unit_code'))
          ..addAll(_g(dev, 'PROCESS_VARIABLE'));
      } else {
        result.addAll([0xFA, 0x7F, 0xC0, 0x00, 0x00]);
      }
    }
    return result;
  }

  /// Command 26: Reset error flags.
  static List<int> _cmd26(
      Map<String, ReactVar> dev, Function(String, String) onWrite) {
    onWrite('config_changed', '00');
    return [
      0x02,
      ..._ec(dev),
      ..._g(dev, 'response_code'),
      ..._g(dev, 'device_status'),
      ..._g(dev, 'comm_status'),
    ];
  }

  /// Command 80: Vendor — read configuration block.
  static List<int> _cmd80(Map<String, ReactVar> dev) => [
        ..._g(dev, 'comm_status'),
        ..._g(dev, 'device_status'),
        ..._hexBytes('0C020A0102'),
        ..._g(dev, 'alarm_selection_code'),
        ..._g(dev, 'burst_mode_control_code'),
        ..._g(dev, 'write_protect_code'),
        ..._g(dev, 'write_protect_code'),
        ..._g(dev, 'flag_assignment'),
        ..._g(dev, 'material_code'),
        ..._hexBytes('0000'),
        0x04,
        ..._hexBytes('43FEFFFC'),
        ..._hexBytes('00000000'),
        ..._g(dev, 'process_variable_unit_code'),
        0x00,
      ];

  /// Command 85: Vendor — paged read, MAP on request body byte.
  static List<int> _cmd85(Map<String, ReactVar> dev, List<int> body) {
    const table = {
      '00': '00020000000042C8000042CC000042CE0000',
      '08': '040242D0000042D2000042D4000042D60000',
      '10': '0C0242E0000042E2000042E4000042E60000',
      '18': '140242D0000042D2000042D4000042D60000',
      '1C': '1C0242E0000042E2000042E4000042E60000',
    };
    final key = _bytesToHex(body);
    final mapped = table[key] ?? '0002000000000000000000000000000000';
    return [..._ec(dev), ..._hexBytes(mapped)];
  }

  /// Command A0: Vendor — MAP on request body byte, echoes body.
  static List<int> _cmdA0(Map<String, ReactVar> dev, List<int> body) {
    const table = {
      '00': '0000000000000000',
      '01': '42FF659F42FF659F',
      '02': '437F659F437F659F',
      '03': '43BF8C3743BF8C37',
      '04': '43FF659F43FF659F',
    };
    final key = _bytesToHex(body);
    final mapped = table[key] ?? '0000000000000000';
    return [
      ..._ec(dev),
      ...body,
      ..._hexBytes('0F05'),
      ..._hexBytes(mapped),
    ];
  }

  // ── Expression evaluator helpers ─────────────────────────────────────────────

  static double evaluateExpr(
      String expr, Map<String, Map<String, ReactVar>> allDevices) {
    try {
      return _expressionEngine.evaluate(expr, (reference) {
        if (reference.namespace != 'HART') return 0;
        final v = allDevices[reference.owner]?[reference.field];
        if (v == null) return 0;
        final hex = v.evaluatedHex.isEmpty ? v.rawValue : v.evaluatedHex;
        if (v.typeStr.toUpperCase().contains('FLOAT') || v.typeStr == 'SREAL') {
          return HartTypeConverter.hexToDouble(hex);
        }
        return int.tryParse(hex, radix: 16)?.toDouble() ?? 0;
      });
    } catch (_) {
      return 0.0;
    }
  }
}
