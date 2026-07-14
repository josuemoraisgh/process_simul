import 'dart:collection';

import '../entities/react_var.dart';
import 'hart_payload_parser.dart';

typedef HartWrite = void Function(String field, String rawHex);

final class HartCommandContext {
  HartCommandContext({
    required Iterable<int> requestBody,
    required Map<String, ReactVar> device,
    required this.onWrite,
    required this.functions,
    this.codec = const HartPayloadCodec(),
  })  : requestBody = List.unmodifiable(requestBody),
        device = UnmodifiableMapView(device) {
    codec.reader(this.requestBody);
  }

  final List<int> requestBody;
  final Map<String, ReactVar> device;
  final HartWrite onWrite;
  final HartFunctionRegistry functions;
  final HartPayloadCodec codec;

  HartPayloadReader newReader() => codec.reader(requestBody);

  T interpret<T>(String name, {HartPayloadReader? reader}) =>
      functions.invoke<T>(name, this, reader ?? newReader());
}

abstract interface class HartCommandHandler {
  int get command;
  List<int> execute(HartCommandContext context);
}

typedef HartCommandExecutor = List<int> Function(HartCommandContext context);

final class FunctionalHartCommandHandler implements HartCommandHandler {
  const FunctionalHartCommandHandler(this.command, this._execute);

  @override
  final int command;
  final HartCommandExecutor _execute;

  @override
  List<int> execute(HartCommandContext context) => _execute(context);
}

abstract interface class HartFunction {
  String get name;
  Object? interpret(HartCommandContext context, HartPayloadReader payload);
}

final class HartRegistryException implements Exception {
  const HartRegistryException(this.message);
  final String message;

  @override
  String toString() => 'HartRegistryException($message)';
}

/// Reusable typed interpretation functions available to every handler.
final class HartFunctionRegistry {
  final Map<String, HartFunction> _functions = {};

  bool contains(String name) => _functions.containsKey(name);

  void register(HartFunction function) {
    final name = function.name.trim();
    if (name.isEmpty) throw const HartRegistryException('empty function name');
    if (_functions.containsKey(name)) {
      throw HartRegistryException('function already registered: $name');
    }
    _functions[name] = function;
  }

  HartFunction remove(String name) {
    final removed = _functions.remove(name);
    if (removed == null) {
      throw HartRegistryException('function not registered: $name');
    }
    return removed;
  }

  T invoke<T>(
      String name, HartCommandContext context, HartPayloadReader payload) {
    final function = _functions[name];
    if (function == null) {
      throw HartRegistryException('function not registered: $name');
    }
    final result = function.interpret(context, payload);
    if (result is! T) {
      throw HartRegistryException('function $name did not return $T');
    }
    return result;
  }
}

/// Dispatcher with no central switch. A module owns registration and can be
/// added or removed independently at startup or in a test.
final class HartCommandRegistry {
  final Map<int, HartCommandHandler> _handlers = {};

  bool contains(int command) => _handlers.containsKey(command);

  void register(HartCommandHandler handler) {
    if (handler.command < 0 || handler.command > 0xffff) {
      throw HartRegistryException('invalid command code: ${handler.command}');
    }
    if (_handlers.containsKey(handler.command)) {
      throw HartRegistryException(
        'command already registered: ${handler.command}',
      );
    }
    _handlers[handler.command] = handler;
  }

  HartCommandHandler remove(int command) {
    final removed = _handlers.remove(command);
    if (removed == null) {
      throw HartRegistryException('command not registered: $command');
    }
    return removed;
  }

  List<int> dispatch(int command, HartCommandContext context) {
    final handler = _handlers[command];
    if (handler == null) return const [64, 0];
    return List.unmodifiable(handler.execute(context));
  }
}
