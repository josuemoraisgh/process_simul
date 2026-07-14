import 'dart:convert';

import '../../application/equipment/equipment_catalog.dart';
import '../../domain/equipment/equipment.dart';
import '../datasources/sqlite_datasource.dart';

/// Persistent equipment catalog that provisions HART and stores Modbus as
/// transport-independent metadata until the Modbus point identity is defined.
final class SqliteEquipmentRepository implements EquipmentRepository {
  const SqliteEquipmentRepository(this._datasource);

  final SqliteDatasource _datasource;

  @override
  Future<void> add(EquipmentDefinition definition) async {
    try {
      _datasource.addEquipmentDefinition(
        id: definition.id.value,
        protocolsJson: jsonEncode(
          definition.protocols.map((protocol) => protocol.name).toList(),
        ),
        profileJson: definition.profile == null
            ? null
            : jsonEncode({
                'key': definition.profile!.key,
                'label': definition.profile!.label,
                'values': definition.profile!.values,
              }),
        attributesJson: jsonEncode(definition.attributes),
        provisionHart: definition.protocols.contains(EquipmentProtocol.hart),
      );
    } on StateError {
      throw DuplicateEquipmentException(definition.id);
    }
  }

  @override
  Future<EquipmentDefinition?> find(EquipmentId id) async {
    final stored = _datasource.getEquipmentDefinition(id.value);
    if (stored != null) return _decode(stored);

    // Compatibility for HART devices created before equipment_catalog.
    if (_datasource.getHartDevices().contains(id.value)) {
      return EquipmentDefinition(
        id: id,
        protocols: const {EquipmentProtocol.hart},
      );
    }
    return null;
  }

  @override
  Future<List<EquipmentDefinition>> list() async {
    final stored = _datasource
        .getEquipmentDefinitions()
        .map(_decode)
        .toList(growable: true);
    final knownIds = stored.map((item) => item.id.value).toSet();
    for (final name in _datasource.getHartDevices()) {
      if (knownIds.add(name)) {
        stored.add(EquipmentDefinition(
          id: EquipmentId(name),
          protocols: const {EquipmentProtocol.hart},
        ));
      }
    }
    return List.unmodifiable(stored);
  }

  @override
  Future<void> remove(EquipmentId id) async {
    final definition = await find(id);
    if (definition == null) throw EquipmentNotFoundException(id);
    _datasource.removeEquipmentDefinition(
      id.value,
      removeHart: definition.protocols.contains(EquipmentProtocol.hart),
    );
  }

  EquipmentDefinition _decode(Map<String, Object?> row) {
    final protocolNames =
        (jsonDecode(row['protocols_json']! as String) as List<dynamic>)
            .cast<String>();
    final profileValue = row['profile_json'] as String?;
    final profileMap = profileValue == null
        ? null
        : jsonDecode(profileValue) as Map<String, dynamic>;
    return EquipmentDefinition(
      id: EquipmentId(row['id']! as String),
      protocols: protocolNames
          .map((name) => EquipmentProtocol.values.byName(name))
          .toSet(),
      profile: profileMap == null
          ? null
          : EquipmentProfile(
              key: profileMap['key'] as String,
              label: profileMap['label'] as String?,
              values: Map<String, Object?>.from(
                profileMap['values'] as Map<String, dynamic>,
              ),
            ),
      attributes: Map<String, Object?>.from(
        jsonDecode(row['attributes_json']! as String) as Map<String, dynamic>,
      ),
    );
  }
}
