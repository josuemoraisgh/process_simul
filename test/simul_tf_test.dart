// Specs for the transfer-function simulation math (TFuncSpec parsing and the
// discrete state-space realisation built from num/den coefficients).
import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/infrastructure/simulation/simul_tf.dart';

void main() {
  group('TFuncSpec.parse', () {
    test('parses a well-formed spec', () {
      final spec = TFuncSpec.parse(r'$[1],[1,2,1],0.2,x');
      expect(spec, isNotNull);
      expect(spec!.num, [1.0]);
      expect(spec.den, [1.0, 2.0, 1.0]);
      expect(spec.delay, 0.2);
      expect(spec.inputExpr, 'x');
    });

    test('tolerates whitespace and multi-term coefficients', () {
      final spec = TFuncSpec.parse(r'$[1, 2], [1, 3, 2], 0, @HART.DEV.col');
      expect(spec, isNotNull);
      expect(spec!.num, [1.0, 2.0]);
      expect(spec.den, [1.0, 3.0, 2.0]);
      expect(spec.inputExpr, '@HART.DEV.col');
    });

    test('returns null for malformed input', () {
      expect(TFuncSpec.parse(r'$[1],[1,2,1]'), isNull);
      expect(TFuncSpec.parse('not a spec'), isNull);
      expect(TFuncSpec.parse(''), isNull);
    });
  });

  group('buildDiscreteSSFromTF', () {
    test('gain-only system (order 0) has no states and D = num/den', () {
      final sys = buildDiscreteSSFromTF([5], [2], 0.01);
      expect(sys.A, isEmpty);
      expect(sys.dcGain, closeTo(2.5, 1e-9));
      // A stateless gain must respond instantly, with no dynamics.
      expect(sys.step(2.0), closeTo(5.0, 1e-9));
    });

    test('strictly-proper first-order lag settles at DC gain 1 for G(s)=1/(s+1)',
        () {
      final sys = buildDiscreteSSFromTF([1], [1, 1], 0.01);
      expect(sys.dcGain, closeTo(1.0, 1e-3));

      double y = 0;
      for (int i = 0; i < 2000; i++) {
        y = sys.step(1.0);
      }
      expect(y, closeTo(1.0, 1e-3));
    });

    test(
        'proper numerator (order == denominator order) uses correct '
        'feedthrough/steady-state gain for G(s) = (s+2)/(s+3)', () {
      // Analytic DC gain: G(0) = 2/3.
      final sys = buildDiscreteSSFromTF([1, 2], [1, 3], 0.001);
      expect(sys.dcGain, closeTo(2 / 3, 1e-3));

      double y = 0;
      for (int i = 0; i < 20000; i++) {
        y = sys.step(1.0);
      }
      expect(y, closeTo(2 / 3, 1e-3));
    });

    test('reset() zeroes internal state', () {
      final sys = buildDiscreteSSFromTF([1], [1, 1], 0.01);
      for (int i = 0; i < 100; i++) {
        sys.step(1.0);
      }
      expect(sys.x.any((v) => v != 0), isTrue);
      sys.reset();
      expect(sys.x.every((v) => v == 0), isTrue);
    });
  });

  group('SimulTf registration', () {
    test('register() succeeds for a valid spec and fails for an invalid one',
        () {
      final sim = SimulTf(stepMs: 10);
      final ok = ReactVar(
        tableName: 'HART',
        rowName: 'DEV',
        colName: 'PV',
        byteSize: 4,
        typeStr: 'FLOAT',
        rawValue: r'$[1],[1,1],0,1',
      );
      final bad = ReactVar(
        tableName: 'HART',
        rowName: 'DEV',
        colName: 'BAD',
        byteSize: 4,
        typeStr: 'FLOAT',
        rawValue: r'$not a spec',
      );

      expect(sim.register(ok, () => 1.0), isTrue);
      expect(sim.entryCount, 1);
      expect(sim.register(bad, () => 1.0), isFalse);
      expect(sim.entryCount, 1);

      sim.unregister('DEV', 'PV');
      expect(sim.entryCount, 0);
    });

    test('start()/stop() toggle isRunning', () {
      final sim = SimulTf(stepMs: 10);
      expect(sim.isRunning, isFalse);
      sim.start();
      expect(sim.isRunning, isTrue);
      sim.stop();
      expect(sim.isRunning, isFalse);
    });

    test('ticking advances the registered ReactVar toward the TF steady state',
        () async {
      final sim = SimulTf(stepMs: 10);
      final v = ReactVar(
        tableName: 'HART',
        rowName: 'DEV',
        colName: 'PV',
        byteSize: 4,
        typeStr: 'FLOAT',
        rawValue: r'$[1],[1,1],0,1',
      );
      sim.register(v, () => 1.0);
      sim.start();
      addTearDown(sim.stop);

      await Future.delayed(const Duration(milliseconds: 500));
      expect(v.hasEvaluated, isTrue);
    });
  });
}
