import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:process_simul/application/equipment/equipment_catalog.dart';
import 'package:process_simul/data/datasources/sqlite_datasource.dart';
import 'package:process_simul/data/repositories/sqlite_equipment_repository.dart';
import 'package:process_simul/domain/equipment/equipment.dart';

void main() {
  test('persists HART, Modbus and mixed definitions without Modbus assumptions',
      () async {
    final directory = await Directory.systemTemp.createTemp('equipment-test');
    final datasource = SqliteDatasource()
      ..openAt('${directory.path}/catalog.db');
    final catalog = EquipmentCatalog(SqliteEquipmentRepository(datasource));
    addTearDown(() async {
      datasource.close();
      await directory.delete(recursive: true);
    });

    final hart = EquipmentDefinition(
      id: EquipmentId('HART-ONLY'),
      protocols: const {EquipmentProtocol.hart},
    );
    final modbus = EquipmentDefinition(
      id: EquipmentId('MODBUS-ONLY'),
      protocols: const {EquipmentProtocol.modbus},
      profile: EquipmentProfile(key: 'generic-modbus'),
    );
    final mixed = EquipmentDefinition(
      id: EquipmentId('MIXED'),
      protocols: const {
        EquipmentProtocol.hart,
        EquipmentProtocol.modbus,
      },
      attributes: const {'note': 'no unit-id implied'},
    );

    await catalog.register(hart);
    await catalog.register(modbus);
    await catalog.register(mixed);

    expect((await catalog.find(hart.id))!.protocols, {EquipmentProtocol.hart});
    expect(
        (await catalog.find(modbus.id))!.protocols, {EquipmentProtocol.modbus});
    expect((await catalog.find(mixed.id))!.protocols,
        {EquipmentProtocol.hart, EquipmentProtocol.modbus});
    expect(datasource.getHartDevices(), containsAll(['HART-ONLY', 'MIXED']));
    expect(datasource.getHartDevices(), isNot(contains('MODBUS-ONLY')));

    datasource.renameHartDevice('MIXED', 'MIXED-RENAMED');
    final renamedId = EquipmentId('MIXED-RENAMED');
    expect(datasource.getEquipmentDefinition('MIXED'), isNull);
    expect(datasource.getHartDevices(), isNot(contains('MIXED')));
    expect(await catalog.find(mixed.id), isNull);
    expect((await catalog.find(renamedId))!.protocols,
        {EquipmentProtocol.hart, EquipmentProtocol.modbus});
    expect((await catalog.list()).map((item) => item.id), contains(renamedId));

    await catalog.remove(hart.id);
    await catalog.remove(modbus.id);
    await catalog.remove(renamedId);
    expect(await catalog.find(hart.id), isNull);
    expect(await catalog.find(modbus.id), isNull);
    expect(await catalog.find(renamedId), isNull);
  });
}
