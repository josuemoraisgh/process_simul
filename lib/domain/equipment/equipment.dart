import 'dart:collection';

/// Opaque application identity. It deliberately does not imply a Modbus
/// unit-id, address, database row, or HART polling address.
final class EquipmentId {
  EquipmentId(String value) : value = value.trim() {
    if (this.value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is EquipmentId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

enum EquipmentProtocol { hart, modbus }

/// Optional, transport-independent defaults for a family of equipment.
final class EquipmentProfile {
  EquipmentProfile(
      {required this.key, this.label, Map<String, Object?> values = const {}})
      : values = UnmodifiableMapView(Map.of(values)) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
  }

  final String key;
  final String? label;
  final Map<String, Object?> values;
}

/// Definition consumed by application use cases, never by a concrete widget,
/// SQL table, socket, or serial port.
final class EquipmentDefinition {
  EquipmentDefinition({
    required this.id,
    required Set<EquipmentProtocol> protocols,
    this.profile,
    Map<String, Object?> attributes = const {},
  })  : protocols = UnmodifiableSetView(Set.of(protocols)),
        attributes = UnmodifiableMapView(Map.of(attributes)) {
    if (protocols.isEmpty) {
      throw ArgumentError.value(protocols, 'protocols', 'must not be empty');
    }
  }

  final EquipmentId id;
  final Set<EquipmentProtocol> protocols;
  final EquipmentProfile? profile;
  final Map<String, Object?> attributes;
}

/// Optional grouping for legacy Modbus points. Both fields may remain null,
/// preserving the current model which has no confirmed equipment identity.
final class ModbusEquipmentAssociation {
  const ModbusEquipmentAssociation({this.equipmentId, this.profileKey});

  final EquipmentId? equipmentId;
  final String? profileKey;
}
