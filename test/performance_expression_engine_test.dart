import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/domain/expression/expression_engine.dart';

void main() {
  double noVariables(ExpressionReference _) => 0;

  group('ExpressionEngine compiled evaluation', () {
    test('preserves precedence, right-associative power and unary signs', () {
      final engine = ExpressionEngine();
      expect(engine.evaluate('2 + 3 * 4', noVariables), 14);
      expect(engine.evaluate('(2 + 3) * 4', noVariables), 20);
      expect(engine.evaluate('2 ** 3 ** 2', noVariables), 512);
      expect(engine.evaluate('-2 ** 2', noVariables), 4);
      expect(engine.evaluate('-2 + +5', noVariables), 3);
    });

    test('resolves structured references without recompiling', () {
      final engine = ExpressionEngine();
      final values = {('DEV', 'PV'): 1.5};
      double resolve(ExpressionReference reference) =>
          values[(reference.owner, reference.field)] ?? 0;

      expect(engine.evaluate('HART.DEV.PV * 2', resolve), 3);
      values[('DEV', 'PV')] = 2.5;
      expect(engine.evaluate('HART.DEV.PV * 2', resolve), 5);

      expect(engine.metrics.compilations, 1);
      expect(engine.metrics.cacheHits, 1);
      expect(engine.metrics.cachedExpressions, 1);
    });

    test('supports registered functions and rejects duplicate names', () {
      final functions = ExpressionFunctionRegistry.standard();
      functions.registerUnary('double', (value) => value * 2);
      final engine = ExpressionEngine(functions: functions);

      expect(engine.evaluate('double(sqrt(9))', noVariables), 6);
      expect(
        () => functions.registerUnary('double', (value) => value),
        throwsA(isA<ExpressionException>()),
      );
    });

    test('bounds cache, source length, tokens and parse depth', () {
      final engine = ExpressionEngine(
        maxCacheEntries: 2,
        maxExpressionLength: 12,
        maxTokens: 8,
        maxParseDepth: 16,
      );
      engine.evaluate('1', noVariables);
      engine.evaluate('2', noVariables);
      engine.evaluate('3', noVariables);
      expect(engine.metrics.cachedExpressions, 2);
      expect(
        () => engine.compile('1234567890123'),
        throwsA(isA<ExpressionException>()),
      );
      expect(
        () => engine.compile('1+1+1+1+1'),
        throwsA(isA<ExpressionException>()),
      );
      expect(
        () => engine.compile('((((((1))))))'),
        throwsA(isA<ExpressionException>()),
      );
    });

    test('compiles a hot expression once across 1000 evaluations', () {
      final engine = ExpressionEngine();
      for (var i = 0; i < 1000; i++) {
        expect(engine.evaluate('HART.DEV.PV + 1', (_) => i.toDouble()), i + 1);
      }
      expect(engine.metrics.compilations, 1);
      expect(engine.metrics.cacheHits, 999);
    });
  });
}
