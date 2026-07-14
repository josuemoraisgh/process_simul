import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/application/equipment/equipment_catalog.dart';
import 'package:process_simul/application/notifiers/log_notifier.dart';
import 'package:process_simul/application/notifiers/settings_notifier.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/domain/enums/db_model.dart';
import 'package:process_simul/domain/equipment/equipment.dart';
import 'package:process_simul/domain/expression/expression_engine.dart';
import 'package:process_simul/domain/hart/hart_command_registry.dart';
import 'package:process_simul/domain/hart/hart_payload_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('application settings', () {
    test('copyWith changes every field and preserves omitted fields', () {
      const original = AppSettings();
      final changed = original.copyWith(
        hartMode: CommMode.serial,
        hartSerialPort: 'COM9',
        hartTcpHost: '::1',
        hartServerPort: 1234,
        modbusPort: 5678,
        tfStepMs: 100,
        darkTheme: false,
      );
      expect(changed.hartMode, CommMode.serial);
      expect(changed.hartSerialPort, 'COM9');
      expect(changed.hartTcpHost, '::1');
      expect(changed.hartServerPort, 1234);
      expect(changed.modbusPort, 5678);
      expect(changed.tfStepMs, 100);
      expect(changed.darkTheme, isFalse);
      expect(changed.copyWith().hartServerPort, 1234);
    });

    test('save, update and load round-trip every preference', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = SettingsNotifier();
      addTearDown(notifier.dispose);
      await notifier.save(const AppSettings(
        hartMode: CommMode.serial,
        hartSerialPort: 'COM7',
        hartTcpHost: '::1',
        hartServerPort: 1200,
        modbusPort: 1201,
        tfStepMs: 75,
        darkTheme: false,
      ));
      await notifier.update((value) => value.copyWith(tfStepMs: 80));
      final loaded = SettingsNotifier();
      addTearDown(loaded.dispose);
      await loaded.load();
      expect(loaded.state.hartMode, CommMode.serial);
      expect(loaded.state.hartSerialPort, 'COM7');
      expect(loaded.state.hartTcpHost, '::1');
      expect(loaded.state.hartServerPort, 1200);
      expect(loaded.state.modbusPort, 1201);
      expect(loaded.state.tfStepMs, 80);
      expect(loaded.state.darkTheme, isFalse);
    });
  });

  group('application log', () {
    test('formats all levels and timestamp and exposes immutable state', () {
      final timestamp = DateTime(2024, 1, 1, 2, 3, 4, 50);
      for (final pair in <(LogLevel, String)>[
        (LogLevel.debug, 'DBG'),
        (LogLevel.info, 'INF'),
        (LogLevel.warning, 'WRN'),
        (LogLevel.error, 'ERR'),
      ]) {
        final entry = LogEntry(
          timestamp: timestamp,
          level: pair.$1,
          source: 'test',
          message: 'message',
        );
        expect(entry.levelLabel, pair.$2);
        expect(entry.timeStr, '02:03:04.05');
      }

      final notifier = LogNotifier()..info('test', 'entry');
      addTearDown(notifier.dispose);
      expect(() => notifier.state.length = 0, throwsUnsupportedError);
      expect(
        () => notifier.state[0] = LogEntry(
          timestamp: timestamp,
          level: LogLevel.error,
          source: 'x',
          message: 'x',
        ),
        throwsUnsupportedError,
      );
    });

    test('global log can be explicitly initialized', () {
      final notifier = LogNotifier();
      addTearDown(notifier.dispose);
      initGlobalLog(notifier);
      expect(globalLog, same(notifier));
    });
  });

  group('equipment model and catalog', () {
    test('validates identities, profiles and protocol sets', () {
      expect(() => EquipmentId('  '), throwsArgumentError);
      final id = EquipmentId(' device-1 ');
      expect(id.value, 'device-1');
      expect(id.toString(), 'device-1');
      expect(id, EquipmentId('device-1'));
      expect(id.hashCode, EquipmentId('device-1').hashCode);
      expect(() => EquipmentProfile(key: ' '), throwsArgumentError);
      final profile = EquipmentProfile(
        key: 'profile',
        label: 'Profile',
        values: {'range': 10},
      );
      expect(profile.values['range'], 10);
      expect(
        () => EquipmentDefinition(id: id, protocols: {}),
        throwsArgumentError,
      );
      final definition = EquipmentDefinition(
        id: id,
        protocols: {EquipmentProtocol.hart, EquipmentProtocol.modbus},
        profile: profile,
        attributes: {'vendor': 'test'},
      );
      expect(definition.attributes['vendor'], 'test');
      final association = ModbusEquipmentAssociation(profileKey: profile.key);
      expect(association.profileKey, 'profile');
      expect(association.equipmentId, isNull);
    });

    test('catalog delegates CRUD and reports duplicate/missing ids', () async {
      final repository = InMemoryEquipmentRepository();
      final catalog = EquipmentCatalog(repository);
      final id = EquipmentId('device');
      final definition = EquipmentDefinition(
        id: id,
        protocols: {EquipmentProtocol.hart},
      );
      await catalog.register(definition);
      expect(await catalog.find(id), same(definition));
      expect(await catalog.list(), [definition]);
      await expectLater(
        catalog.register(definition),
        throwsA(isA<DuplicateEquipmentException>()),
      );
      await catalog.remove(id);
      expect(await catalog.find(id), isNull);
      await expectLater(
        catalog.remove(id),
        throwsA(isA<EquipmentNotFoundException>()),
      );
    });
  });

  group('HART payload and registries', () {
    test('codec validates, converts and bounds payload reads', () {
      const codec = HartPayloadCodec(maxPayloadBytes: 2);
      expect(codec.hexToBytes('0a FF'), [10, 255]);
      expect(const HartPayloadCodec().bytesToHex([0, 10, 255]), '000AFF');
      expect(() => codec.hexToBytes('0'), throwsA(isA<HartPayloadException>()));
      expect(
          () => codec.hexToBytes('GG'), throwsA(isA<HartPayloadException>()));
      expect(
          () => codec.reader([1, 2, 3]), throwsA(isA<HartPayloadException>()));
      expect(() => codec.reader([-1]), throwsA(isA<HartPayloadException>()));
      expect(() => codec.reader([256]), throwsA(isA<HartPayloadException>()));
      final reader = codec.reader([1, 2]);
      expect(reader.offset, 0);
      expect(reader.readUint8(), 1);
      expect(reader.remaining, 1);
      expect(reader.readRemaining(), [2]);
      expect(() => reader.readBytes(-1), throwsA(isA<HartPayloadException>()));
      const exception = HartPayloadException('bad', offset: 3);
      expect(exception.toString(), 'HartPayloadException(bad, offset: 3)');
    });

    test('function and command registries cover typed lifecycle', () {
      final functions = HartFunctionRegistry();
      final function = _ByteFunction('byte');
      functions.register(function);
      expect(functions.contains('byte'), isTrue);
      expect(() => functions.register(function),
          throwsA(isA<HartRegistryException>()));
      expect(() => functions.register(_ByteFunction(' ')),
          throwsA(isA<HartRegistryException>()));
      final context = HartCommandContext(
        requestBody: [7],
        device: {},
        onWrite: (_, __) {},
        functions: functions,
      );
      expect(context.interpret<int>('byte'), 7);
      expect(
        () => context.interpret<String>('byte'),
        throwsA(isA<HartRegistryException>()),
      );
      expect(functions.remove('byte'), same(function));
      expect(() => functions.remove('byte'),
          throwsA(isA<HartRegistryException>()));
      expect(
        () => functions.invoke<int>('missing', context, context.newReader()),
        throwsA(isA<HartRegistryException>()),
      );

      final commands = HartCommandRegistry();
      final handler = FunctionalHartCommandHandler(42, (_) => [1, 2]);
      commands.register(handler);
      expect(commands.contains(42), isTrue);
      expect(commands.dispatch(42, context), [1, 2]);
      expect(commands.dispatch(99, context), [64, 0]);
      expect(() => commands.register(handler),
          throwsA(isA<HartRegistryException>()));
      expect(
        () => commands.register(FunctionalHartCommandHandler(-1, (_) => [])),
        throwsA(isA<HartRegistryException>()),
      );
      expect(commands.remove(42), same(handler));
      expect(() => commands.remove(42), throwsA(isA<HartRegistryException>()));
      const exception = HartRegistryException('bad');
      expect(exception.toString(), 'HartRegistryException(bad)');
    });
  });

  group('expression engine edge paths', () {
    double zero(ExpressionReference _) => 0;

    test('covers registry functions, literals, references and cache reset', () {
      final registry = ExpressionFunctionRegistry.standard();
      expect(registry.resolve('math.sqrt').invoke([9]), 3);
      expect(registry.resolve('abs').invoke([-2]), 2);
      expect(registry.resolve('log').invoke([0]), 0);
      expect(registry.resolve('ln').invoke([1]), 0);
      expect(registry.resolve('int').invoke([1.8]), 1);
      expect(registry.resolve('pow').invoke([2, 3]), 8);
      expect(
        () => registry.resolve('pow').invoke([2]),
        throwsA(isA<ExpressionException>()),
      );
      expect(() => registry.resolve('missing'),
          throwsA(isA<ExpressionException>()));
      expect(
        () => registry.register(ExpressionFunctionSpec(
          name: ' ',
          function: (_) => 0,
          minArguments: 0,
          maxArguments: 0,
        )),
        throwsA(isA<ExpressionException>()),
      );

      final engine = ExpressionEngine(functions: registry);
      expect(
          engine.evaluate(' .5 + 1E+2 + 1e-2 ', zero), closeTo(100.51, 1e-9));
      expect(engine.evaluate('unknown_name', zero), 0);
      expect(engine.evaluate('', zero), 0);
      engine.clearCache();
      expect(engine.metrics.cachedExpressions, 0);
      const exception = ExpressionException('bad', offset: 4);
      expect(exception.toString(), 'ExpressionException(bad, offset: 4)');
    });

    test('rejects every malformed-input and configured-limit path', () {
      expect(() => ExpressionEngine(maxCacheEntries: 0), throwsArgumentError);
      final engine = ExpressionEngine(maxTokens: 2, maxParseDepth: 4);
      for (final expression in ['#', '(1', 'sqrt(1', '1e+']) {
        expect(
          () => engine.compile(expression),
          throwsA(isA<ExpressionException>()),
          reason: expression,
        );
      }
      expect(() => engine.compile('1+2'), throwsA(isA<ExpressionException>()));
      final normalEngine = ExpressionEngine();
      expect(
        () => normalEngine.compile('1 2'),
        throwsA(isA<ExpressionException>()),
      );
      expect(
        () => normalEngine.compile('1+'),
        throwsA(isA<ExpressionException>()),
      );
      expect(
        () => ExpressionEngine(maxParseDepth: 1).compile('-1'),
        throwsA(isA<ExpressionException>()),
      );
    });
  });

  test('ReactVar exposes debugging representation and state helpers', () {
    final value = ReactVar(
      tableName: 'T',
      rowName: 'R',
      colName: 'C',
      byteSize: 1,
      typeStr: 'uint8',
      rawValue: '01',
    );
    expect(value.model, DbModel.value);
    expect(value.funcBody, '');
    expect(value.tFuncBody, '');
    expect(value.toString(), 'ReactVar(T.R.C [uint8] = 01)');
  });
}

final class _ByteFunction implements HartFunction {
  _ByteFunction(this.name);

  @override
  final String name;

  @override
  Object? interpret(HartCommandContext context, HartPayloadReader payload) =>
      payload.readUint8();
}
