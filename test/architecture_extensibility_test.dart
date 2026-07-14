import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/application/equipment/equipment_catalog.dart';
import 'package:process_simul/domain/equipment/equipment.dart';
import 'package:process_simul/domain/hart/hart_command_registry.dart';
import 'package:process_simul/domain/hart/hart_payload_parser.dart';

final class _FirstByte implements HartFunction {
  @override
  String get name => 'firstByte';

  @override
  Object interpret(HartCommandContext context, HartPayloadReader payload) =>
      payload.readUint8();
}

final class _FixtureCommand implements HartCommandHandler {
  @override
  int get command => 0x123;

  @override
  List<int> execute(HartCommandContext context) =>
      [0, 0, context.interpret<int>('firstByte')];
}

void main() {
  group('equipment catalog contract', () {
    test('registers and removes HART/Modbus definitions without infrastructure',
        () async {
      final catalog = EquipmentCatalog(InMemoryEquipmentRepository());
      final definition = EquipmentDefinition(
        id: EquipmentId('mixed-1'),
        protocols: {EquipmentProtocol.hart, EquipmentProtocol.modbus},
        profile: EquipmentProfile(key: 'generic'),
      );

      await catalog.register(definition);
      expect(await catalog.find(EquipmentId('mixed-1')), same(definition));
      await catalog.remove(EquipmentId('mixed-1'));
      expect(await catalog.list(), isEmpty);
    });

    test('rejects duplicate ids atomically', () async {
      final catalog = EquipmentCatalog(InMemoryEquipmentRepository());
      final first = EquipmentDefinition(
        id: EquipmentId('same'),
        protocols: {EquipmentProtocol.hart},
      );
      final second = EquipmentDefinition(
        id: EquipmentId('same'),
        protocols: {EquipmentProtocol.modbus},
      );

      await catalog.register(first);
      await expectLater(
        catalog.register(second),
        throwsA(isA<DuplicateEquipmentException>()),
      );
      expect(await catalog.list(), [same(first)]);
    });
  });

  group('HART extension contracts', () {
    test('registers, dispatches and removes handler and shared function', () {
      final functions = HartFunctionRegistry()..register(_FirstByte());
      final commands = HartCommandRegistry()..register(_FixtureCommand());
      final context = HartCommandContext(
        requestBody: [0x2a],
        device: const {},
        onWrite: (_, __) {},
        functions: functions,
      );

      expect(commands.dispatch(0x123, context), [0, 0, 0x2a]);
      commands.remove(0x123);
      functions.remove('firstByte');
      expect(commands.dispatch(0x123, context), [64, 0]);
    });

    test('rejects duplicate handlers/functions and truncated payloads', () {
      final functions = HartFunctionRegistry()..register(_FirstByte());
      final commands = HartCommandRegistry()..register(_FixtureCommand());

      expect(() => functions.register(_FirstByte()),
          throwsA(isA<HartRegistryException>()));
      expect(() => commands.register(_FixtureCommand()),
          throwsA(isA<HartRegistryException>()));
      expect(
        () => const HartPayloadCodec().reader(const []).readUint8(),
        throwsA(isA<HartPayloadException>()),
      );
    });
  });
}
