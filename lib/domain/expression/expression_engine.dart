import 'dart:collection';
import 'dart:math' as math;

typedef ExpressionVariableResolver = double Function(
  ExpressionReference reference,
);
typedef ExpressionFunction = double Function(List<double> arguments);

final class ExpressionReference {
  const ExpressionReference(this.namespace, this.owner, this.field);

  final String namespace;
  final String owner;
  final String field;
}

final class ExpressionException implements Exception {
  const ExpressionException(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() => 'ExpressionException($message, offset: $offset)';
}

final class ExpressionFunctionSpec {
  const ExpressionFunctionSpec({
    required this.name,
    required this.function,
    required this.minArguments,
    required this.maxArguments,
  });

  final String name;
  final ExpressionFunction function;
  final int minArguments;
  final int maxArguments;

  double invoke(List<double> arguments) {
    if (arguments.length < minArguments || arguments.length > maxArguments) {
      throw ExpressionException(
        '$name expects $minArguments..$maxArguments arguments, '
        'got ${arguments.length}',
      );
    }
    return function(List<double>.unmodifiable(arguments));
  }
}

/// Registry shared by the parser and every compiled expression.
///
/// Registrations are explicit and duplicate names are rejected. Compiled
/// expressions resolve the function by name at evaluation time, so replacing
/// an engine does not couple expressions to HART commands or infrastructure.
final class ExpressionFunctionRegistry {
  final Map<String, ExpressionFunctionSpec> _functions = {};

  factory ExpressionFunctionRegistry.standard() {
    final registry = ExpressionFunctionRegistry();
    registry
      ..registerUnary(
          'sqrt', (value) => math.sqrt(value.clamp(0, double.infinity)))
      ..registerUnary(
          'math.sqrt', (value) => math.sqrt(value.clamp(0, double.infinity)))
      ..registerUnary('exp', math.exp)
      ..registerUnary('abs', (value) => value.abs())
      ..registerUnary('log', (value) => value > 0 ? math.log(value) : 0)
      ..registerUnary('ln', (value) => value > 0 ? math.log(value) : 0)
      ..registerUnary('int', (value) => value.truncateToDouble())
      ..register(ExpressionFunctionSpec(
        name: 'pow',
        minArguments: 2,
        maxArguments: 2,
        function: (arguments) =>
            math.pow(arguments[0], arguments[1]).toDouble(),
      ));
    return registry;
  }

  ExpressionFunctionRegistry();

  void register(ExpressionFunctionSpec function) {
    final name = function.name.trim();
    if (name.isEmpty) {
      throw const ExpressionException('empty function name');
    }
    if (_functions.containsKey(name)) {
      throw ExpressionException('function already registered: $name');
    }
    _functions[name] = function;
  }

  void registerUnary(String name, double Function(double value) function) {
    register(ExpressionFunctionSpec(
      name: name,
      minArguments: 1,
      maxArguments: 1,
      function: (arguments) => function(arguments.single),
    ));
  }

  ExpressionFunctionSpec resolve(String name) {
    final function = _functions[name];
    if (function == null) {
      throw ExpressionException('function not registered: $name');
    }
    return function;
  }
}

final class ExpressionEngineMetrics {
  const ExpressionEngineMetrics({
    required this.compilations,
    required this.cacheHits,
    required this.cachedExpressions,
  });

  final int compilations;
  final int cacheHits;
  final int cachedExpressions;
}

final class CompiledExpression {
  const CompiledExpression._(this.source, this._root, this._functions);

  final String source;
  final _ExpressionNode _root;
  final ExpressionFunctionRegistry _functions;

  double evaluate(ExpressionVariableResolver resolveVariable) =>
      _root.evaluate(resolveVariable, _functions);
}

/// Bounded compiler/cache for process expressions.
final class ExpressionEngine {
  ExpressionEngine({
    ExpressionFunctionRegistry? functions,
    this.maxCacheEntries = 512,
    this.maxExpressionLength = 4096,
    this.maxTokens = 1024,
    this.maxParseDepth = 128,
  }) : functions = functions ?? ExpressionFunctionRegistry.standard() {
    if (maxCacheEntries <= 0 ||
        maxExpressionLength <= 0 ||
        maxTokens <= 0 ||
        maxParseDepth <= 0) {
      throw ArgumentError('expression limits must be positive');
    }
  }

  final ExpressionFunctionRegistry functions;
  final int maxCacheEntries;
  final int maxExpressionLength;
  final int maxTokens;
  final int maxParseDepth;
  final LinkedHashMap<String, CompiledExpression> _cache = LinkedHashMap();
  int _compilations = 0;
  int _cacheHits = 0;

  ExpressionEngineMetrics get metrics => ExpressionEngineMetrics(
        compilations: _compilations,
        cacheHits: _cacheHits,
        cachedExpressions: _cache.length,
      );

  CompiledExpression compile(String source) {
    final normalized = source.trim();
    final cached = _cache.remove(normalized);
    if (cached != null) {
      _cacheHits++;
      _cache[normalized] = cached;
      return cached;
    }
    if (normalized.length > maxExpressionLength) {
      throw ExpressionException(
        'expression exceeds $maxExpressionLength characters',
      );
    }
    final tokens = _Lexer(normalized, maxTokens: maxTokens).scan();
    final root = _Parser(tokens, maxDepth: maxParseDepth).parse();
    final compiled = CompiledExpression._(normalized, root, functions);
    _compilations++;
    _cache[normalized] = compiled;
    if (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return compiled;
  }

  double evaluate(String source, ExpressionVariableResolver resolveVariable) =>
      compile(source).evaluate(resolveVariable);

  void clearCache() => _cache.clear();
}

enum _TokenType {
  number,
  identifier,
  plus,
  minus,
  star,
  slash,
  power,
  lParen,
  rParen,
  comma,
  end
}

final class _Token {
  const _Token(this.type, this.lexeme, this.offset);
  final _TokenType type;
  final String lexeme;
  final int offset;
}

final class _Lexer {
  _Lexer(this.source, {required this.maxTokens});
  final String source;
  final int maxTokens;

  List<_Token> scan() {
    final tokens = <_Token>[];
    var offset = 0;
    void add(_Token token) {
      if (tokens.length >= maxTokens) {
        throw ExpressionException('expression exceeds $maxTokens tokens');
      }
      tokens.add(token);
    }

    while (offset < source.length) {
      final code = source.codeUnitAt(offset);
      if (_isWhitespace(code)) {
        offset++;
        continue;
      }
      final start = offset;
      if (_isDigit(code) ||
          (code == 0x2e &&
              offset + 1 < source.length &&
              _isDigit(source.codeUnitAt(offset + 1)))) {
        offset = _scanNumber(offset);
        add(_Token(_TokenType.number, source.substring(start, offset), start));
        continue;
      }
      if (_isIdentifierStart(code)) {
        offset++;
        while (offset < source.length &&
            _isIdentifierPart(source.codeUnitAt(offset))) {
          offset++;
        }
        add(_Token(
          _TokenType.identifier,
          source.substring(start, offset),
          start,
        ));
        continue;
      }
      offset++;
      switch (code) {
        case 0x2b:
          add(_Token(_TokenType.plus, '+', start));
        case 0x2d:
          add(_Token(_TokenType.minus, '-', start));
        case 0x2a:
          if (offset < source.length && source.codeUnitAt(offset) == 0x2a) {
            offset++;
            add(_Token(_TokenType.power, '**', start));
          } else {
            add(_Token(_TokenType.star, '*', start));
          }
        case 0x2f:
          add(_Token(_TokenType.slash, '/', start));
        case 0x28:
          add(_Token(_TokenType.lParen, '(', start));
        case 0x29:
          add(_Token(_TokenType.rParen, ')', start));
        case 0x2c:
          add(_Token(_TokenType.comma, ',', start));
        default:
          throw ExpressionException('unexpected character', offset: start);
      }
    }
    tokens.add(_Token(_TokenType.end, '', source.length));
    return List.unmodifiable(tokens);
  }

  int _scanNumber(int offset) {
    var cursor = offset;
    while (cursor < source.length && _isDigit(source.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor < source.length && source.codeUnitAt(cursor) == 0x2e) {
      cursor++;
      while (cursor < source.length && _isDigit(source.codeUnitAt(cursor))) {
        cursor++;
      }
    }
    if (cursor < source.length &&
        (source.codeUnitAt(cursor) == 0x65 ||
            source.codeUnitAt(cursor) == 0x45)) {
      final exponent = cursor++;
      if (cursor < source.length &&
          (source.codeUnitAt(cursor) == 0x2b ||
              source.codeUnitAt(cursor) == 0x2d)) {
        cursor++;
      }
      final digits = cursor;
      while (cursor < source.length && _isDigit(source.codeUnitAt(cursor))) {
        cursor++;
      }
      if (digits == cursor) return exponent;
    }
    return cursor;
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
  static bool _isIdentifierStart(int code) =>
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      code == 0x5f;
  static bool _isIdentifierPart(int code) =>
      _isIdentifierStart(code) || _isDigit(code) || code == 0x2e;
}

final class _Parser {
  _Parser(this.tokens, {required this.maxDepth});
  final List<_Token> tokens;
  final int maxDepth;
  var _current = 0;
  var _depth = 0;

  _ExpressionNode parse() {
    if (_peek.type == _TokenType.end) return const _NumberNode(0);
    final expression = _withDepth(_parseAddition);
    if (_peek.type != _TokenType.end) {
      throw ExpressionException('unexpected token', offset: _peek.offset);
    }
    return expression;
  }

  _ExpressionNode _parseAddition() {
    var expression = _withDepth(_parseMultiplication);
    while (_match(_TokenType.plus) || _match(_TokenType.minus)) {
      final operator = _previous.type;
      final right = _withDepth(_parseMultiplication);
      expression = _BinaryNode(expression, operator, right);
    }
    return expression;
  }

  _ExpressionNode _parseMultiplication() {
    var expression = _withDepth(_parsePower);
    while (_match(_TokenType.star) || _match(_TokenType.slash)) {
      final operator = _previous.type;
      final right = _withDepth(_parsePower);
      expression = _BinaryNode(expression, operator, right);
    }
    return expression;
  }

  _ExpressionNode _parsePower() {
    final left = _withDepth(_parseUnary);
    if (_match(_TokenType.power)) {
      return _BinaryNode(left, _previous.type, _withDepth(_parsePower));
    }
    return left;
  }

  _ExpressionNode _parseUnary() {
    if (_match(_TokenType.plus) || _match(_TokenType.minus)) {
      return _UnaryNode(_previous.type, _withDepth(_parseUnary));
    }
    return _withDepth(_parsePrimary);
  }

  _ExpressionNode _parsePrimary() {
    if (_match(_TokenType.number)) {
      final value = double.tryParse(_previous.lexeme);
      if (value == null) {
        throw ExpressionException('invalid number', offset: _previous.offset);
      }
      return _NumberNode(value);
    }
    if (_match(_TokenType.identifier)) {
      final name = _previous.lexeme;
      if (_match(_TokenType.lParen)) {
        final arguments = <_ExpressionNode>[];
        if (_peek.type != _TokenType.rParen) {
          do {
            arguments.add(_withDepth(_parseAddition));
          } while (_match(_TokenType.comma));
        }
        _consume(_TokenType.rParen, 'expected closing parenthesis');
        return _FunctionNode(name, List.unmodifiable(arguments));
      }
      final parts = name.split('.');
      if (parts.length == 3) {
        return _ReferenceNode(
            ExpressionReference(parts[0], parts[1], parts[2]));
      }
      return const _NumberNode(0);
    }
    if (_match(_TokenType.lParen)) {
      final expression = _withDepth(_parseAddition);
      _consume(_TokenType.rParen, 'expected closing parenthesis');
      return expression;
    }
    throw ExpressionException('expected expression', offset: _peek.offset);
  }

  T _withDepth<T>(T Function() parse) {
    _depth++;
    if (_depth > maxDepth) {
      throw ExpressionException('expression exceeds parse depth $maxDepth');
    }
    try {
      return parse();
    } finally {
      _depth--;
    }
  }

  bool _match(_TokenType type) {
    if (_peek.type != type) return false;
    _current++;
    return true;
  }

  void _consume(_TokenType type, String message) {
    if (!_match(type)) throw ExpressionException(message, offset: _peek.offset);
  }

  _Token get _peek => tokens[_current];
  _Token get _previous => tokens[_current - 1];
}

sealed class _ExpressionNode {
  const _ExpressionNode();
  double evaluate(
    ExpressionVariableResolver resolveVariable,
    ExpressionFunctionRegistry functions,
  );
}

final class _NumberNode extends _ExpressionNode {
  const _NumberNode(this.value);
  final double value;
  @override
  double evaluate(
          ExpressionVariableResolver _, ExpressionFunctionRegistry __) =>
      value;
}

final class _ReferenceNode extends _ExpressionNode {
  const _ReferenceNode(this.reference);
  final ExpressionReference reference;
  @override
  double evaluate(
    ExpressionVariableResolver resolveVariable,
    ExpressionFunctionRegistry _,
  ) =>
      resolveVariable(reference);
}

final class _UnaryNode extends _ExpressionNode {
  const _UnaryNode(this.operator, this.operand);
  final _TokenType operator;
  final _ExpressionNode operand;
  @override
  double evaluate(
    ExpressionVariableResolver resolveVariable,
    ExpressionFunctionRegistry functions,
  ) {
    final value = operand.evaluate(resolveVariable, functions);
    return operator == _TokenType.minus ? -value : value;
  }
}

final class _BinaryNode extends _ExpressionNode {
  const _BinaryNode(this.left, this.operator, this.right);
  final _ExpressionNode left;
  final _TokenType operator;
  final _ExpressionNode right;
  @override
  double evaluate(
    ExpressionVariableResolver resolveVariable,
    ExpressionFunctionRegistry functions,
  ) {
    final a = left.evaluate(resolveVariable, functions);
    final b = right.evaluate(resolveVariable, functions);
    return switch (operator) {
      _TokenType.plus => a + b,
      _TokenType.minus => a - b,
      _TokenType.star => a * b,
      _TokenType.slash => b == 0 ? 0 : a / b,
      _TokenType.power => math.pow(a, b).toDouble(),
      _ => throw const ExpressionException('invalid binary operator'),
    };
  }
}

final class _FunctionNode extends _ExpressionNode {
  const _FunctionNode(this.name, this.arguments);
  final String name;
  final List<_ExpressionNode> arguments;
  @override
  double evaluate(
    ExpressionVariableResolver resolveVariable,
    ExpressionFunctionRegistry functions,
  ) =>
      functions.resolve(name).invoke([
        for (final argument in arguments)
          argument.evaluate(resolveVariable, functions),
      ]);
}
