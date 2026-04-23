import 'dart:async';
import '../../domain/entities/react_var.dart';
import '../hart/hart_type_converter.dart';
import '../../application/notifiers/log_notifier.dart';

/// Parses a transfer-function specification string of the form:
///   $[num_coeffs],[den_coeffs],delay,input_expr
/// Example: $[1],[1,2,1],0.2,x
class TFuncSpec {
  final List<double> num;
  final List<double> den;
  final double delay;
  final String inputExpr;

  TFuncSpec({
    required this.num,
    required this.den,
    required this.delay,
    required this.inputExpr,
  });

  static TFuncSpec? parse(String spec) {
    try {
      // Remove leading $
      final s = spec.startsWith(r'$') ? spec.substring(1) : spec;
      // Match [num],[den],delay,expr  — tolerates optional whitespace
      final re = RegExp(
          r'^\[([^\]]+)\]\s*,\s*\[([^\]]+)\]\s*,\s*([\d.]+)\s*,\s*(.+)$');
      final m = re.firstMatch(s.trim());
      if (m == null) return null;
      // Coefficients may be separated by commas, spaces, or both
      final splitter = RegExp(r'[\s,]+');
      final num = m.group(1)!.trim().split(splitter).map(double.parse).toList();
      final den = m.group(2)!.trim().split(splitter).map(double.parse).toList();
      final delay = double.parse(m.group(3)!);
      final expr = m.group(4)!.trim();
      return TFuncSpec(num: num, den: den, delay: delay, inputExpr: expr);
    } catch (_) {
      return null;
    }
  }
}

/// Discrete-time state-space representation using Euler (forward) discretization.
class DiscreteSS {
  final List<List<double>> A;
  final List<double> B;
  final List<double> C;
  final double D;
  final double Ts;
  List<double> x;

  DiscreteSS({
    required this.A,
    required this.B,
    required this.C,
    required this.D,
    required this.Ts,
  }) : x = List.filled(A.length, 0.0);

  /// Returns the system's DC gain for normalisation.
  double get dcGain {
    // For y = C(I-A)^{-1}B + D, approximate for 1st/2nd order
    if (A.isEmpty) return D;
    // Simple numeric: run to steady-state with u=1
    double y = 0;
    final xSteady = List.filled(A.length, 0.0);
    for (int k = 0; k < 500; k++) {
      final xNext = _mul(A, xSteady);
      for (int i = 0; i < xSteady.length; i++) {
        xSteady[i] = xNext[i] + B[i];
      }
      y = _dot(C, xSteady) + D;
    }
    return y.abs() < 1e-9 ? 1.0 : y;
  }

  double step(double u) {
    final xNext = _mul(A, x);
    for (int i = 0; i < x.length; i++) {
      xNext[i] += B[i] * u;
    }
    x = xNext;
    return _dot(C, x) + D * u;
  }

  void reset() {
    x = List.filled(A.length, 0.0);
  }

  static List<double> _mul(List<List<double>> mat, List<double> vec) {
    return mat.map((row) => _dot(row, vec)).toList();
  }

  static double _dot(List<double> a, List<double> b) {
    double s = 0;
    for (int i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }
}

/// Builds a discrete state-space system from transfer-function coefficients.
DiscreteSS buildDiscreteSSFromTF(
    List<double> num, List<double> den, double Ts) {
  // Normalise by den[0]
  final a0 = den[0];
  final numN = num.map((v) => v / a0).toList();
  final denN = den.map((v) => v / a0).toList();
  final n = denN.length - 1; // system order

  if (n == 0) {
    // Gain-only system
    return DiscreteSS(
      A: [],
      B: [],
      C: [],
      D: numN.isEmpty ? 1.0 : numN[0],
      Ts: Ts,
    );
  }

  // Controllable canonical form (continuous), then discretise using Euler
  // Ac = [0 1 0...; 0 0 1 ...; -an -a(n-1) ... -a1]
  final Ac = List.generate(n, (i) {
    return List.generate(n, (j) {
      if (i < n - 1) return i + 1 == j ? 1.0 : 0.0;
      return -(denN[n - j]).clamp(-1e9, 1e9);
    });
  });
  final Bc = List.generate(n, (i) => i == n - 1 ? 1.0 : 0.0);
  final Cc = List.generate(n, (i) {
    final ki = n - 1 - i;
    final numVal = ki < numN.length ? numN[ki] : 0.0;
    return numVal;
  });
  final Dc = numN.length > n ? numN[0] : 0.0;

  // Euler: Ad = I + Ts*Ac, Bd = Ts*Bc
  final Ad = List.generate(
      n, (i) => List.generate(n, (j) => (i == j ? 1.0 : 0.0) + Ts * Ac[i][j]));
  final Bd = Bc.map((v) => Ts * v).toList();

  return DiscreteSS(A: Ad, B: Bd, C: Cc, D: Dc, Ts: Ts);
}

/// Manages transfer-function simulation for all $tFunc ReactVar cells.
///
/// Runs a periodic timer (default 50 ms) to advance each registered
/// discrete-time system and update the ReactVar's evaluatedHex.
class SimulTf {
  final double stepMs;
  final Map<String, _TFEntry> _entries = {};
  Timer? _timer;
  bool _running = false;

  /// Called after a tick when at least one ReactVar actually changed.
  void Function()? onChanged;

  SimulTf({this.stepMs = 50.0});

  bool get isRunning => _running;

  int get entryCount => _entries.length;

  // ── Register / unregister ───────────────────────────────────────────────
  /// Returns `true` if the TF spec was parsed and registered successfully.
  bool register(ReactVar variable, double Function() getInput) {
    final key = '${variable.rowName}.${variable.colName}';
    final spec = TFuncSpec.parse(variable.tFuncBody);
    if (spec == null) return false;
    final sys = buildDiscreteSSFromTF(spec.num, spec.den, stepMs / 1000.0);
    _entries[key] = _TFEntry(variable: variable, sys: sys, getInput: getInput);
    return true;
  }

  void unregister(String rowName, String colName) {
    _entries.remove('$rowName.$colName');
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  void start() {
    if (_running) return;
    _running = true;
    _loggedFirstTick = false;
    _timer = Timer.periodic(Duration(milliseconds: stepMs.toInt()), _tick);
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    for (final e in _entries.values) {
      e.sys.reset();
    }
  }

  bool _loggedFirstTick = false;

  // ── Tick ─────────────────────────────────────────────────────────────────
  void _tick(Timer _) {
    bool anyChanged = false;
    for (final e in _entries.values) {
      double u = e.getInput();

      // Log first tick for diagnostics
      if (!_loggedFirstTick) {
        final key = '${e.variable.rowName}.${e.variable.colName}';
        globalLog.debug('TF', '$key input raw=$u');
      }

      // Input normalisation (mirrors Python heuristic)
      if (u > 1000) {
        u = u / 65535.0;
      } else if (u > 1) {
        u = u / 100.0;
      }
      u = u.clamp(0.0, 1.0);

      double y = e.sys.step(u).clamp(0.0, 1.0);

      // Back-convert to float hex and store in evaluatedHex
      final hexVal = HartTypeConverter.doubleToHex(y);
      if (e.variable.setEvaluatedHex(hexVal)) anyChanged = true;

      if (!_loggedFirstTick) {
        final key = '${e.variable.rowName}.${e.variable.colName}';
        globalLog.debug('TF', '$key u=$u y=$y hex=$hexVal');
      }
    }
    _loggedFirstTick = true;
    if (anyChanged) onChanged?.call();
  }
}

class _TFEntry {
  final ReactVar variable;
  final DiscreteSS sys;
  final double Function() getInput;
  _TFEntry({required this.variable, required this.sys, required this.getInput});
}
