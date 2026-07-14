import '../../domain/equipment/equipment.dart';

sealed class EquipmentCatalogException implements Exception {
  const EquipmentCatalogException(this.id);

  final EquipmentId id;
}

final class DuplicateEquipmentException extends EquipmentCatalogException {
  const DuplicateEquipmentException(super.id);
}

final class EquipmentNotFoundException extends EquipmentCatalogException {
  const EquipmentNotFoundException(super.id);
}

/// Persistence port. Implementations must make each mutation atomic and reject
/// duplicate ids; callers never need to know whether storage is SQLite, a file,
/// memory, or remote.
abstract interface class EquipmentRepository {
  Future<void> add(EquipmentDefinition definition);
  Future<void> remove(EquipmentId id);
  Future<EquipmentDefinition?> find(EquipmentId id);
  Future<List<EquipmentDefinition>> list();
}

/// The UI-facing application API for inserting/removing equipment.
final class EquipmentCatalog {
  const EquipmentCatalog(this._repository);

  final EquipmentRepository _repository;

  Future<void> register(EquipmentDefinition definition) =>
      _repository.add(definition);

  Future<void> remove(EquipmentId id) => _repository.remove(id);

  Future<EquipmentDefinition?> find(EquipmentId id) => _repository.find(id);

  Future<List<EquipmentDefinition>> list() => _repository.list();
}

/// Small functional adapter useful for composition and tests. A persistent
/// adapter can replace it without changing [EquipmentCatalog].
final class InMemoryEquipmentRepository implements EquipmentRepository {
  final Map<EquipmentId, EquipmentDefinition> _items = {};

  @override
  Future<void> add(EquipmentDefinition definition) async {
    if (_items.containsKey(definition.id)) {
      throw DuplicateEquipmentException(definition.id);
    }
    _items[definition.id] = definition;
  }

  @override
  Future<EquipmentDefinition?> find(EquipmentId id) async => _items[id];

  @override
  Future<List<EquipmentDefinition>> list() async =>
      List.unmodifiable(_items.values);

  @override
  Future<void> remove(EquipmentId id) async {
    if (_items.remove(id) == null) {
      throw EquipmentNotFoundException(id);
    }
  }
}
