import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/repositories/i_db_repository.dart';

/// State holding all custom ENUM, BIT_ENUM and COMMAND definitions from the database.
class CustomTypesState {
  final Map<int, Map<String, String>> enums; // enumIndex → { hexKey → desc }
  final Map<int, Map<int, String>> bitEnums; // bitEnumIndex → { mask → desc }
  final Map<String, Map<String, dynamic>>
      commands; // cmd → { description, req, resp, write }
  final bool loading;

  const CustomTypesState({
    this.enums = const {},
    this.bitEnums = const {},
    this.commands = const {},
    this.loading = true,
  });

  CustomTypesState copyWith({
    Map<int, Map<String, String>>? enums,
    Map<int, Map<int, String>>? bitEnums,
    Map<String, Map<String, dynamic>>? commands,
    bool? loading,
  }) =>
      CustomTypesState(
        enums: enums ?? this.enums,
        bitEnums: bitEnums ?? this.bitEnums,
        commands: commands ?? this.commands,
        loading: loading ?? this.loading,
      );
}

class CustomTypesNotifier extends StateNotifier<CustomTypesState> {
  final IDbRepository _repo;

  CustomTypesNotifier(this._repo) : super(const CustomTypesState());

  void load() {
    state = state.copyWith(
      enums: _repo.getAllEnums(),
      bitEnums: _repo.getAllBitEnums(),
      commands: _repo.getAllCommands(),
      loading: false,
    );
  }

  // ── ENUM operations ───────────────────────────────────────────────────────
  void addEnumEntry(int enumIndex, String hexKey, String description) {
    _repo.addEnumEntry(enumIndex, hexKey, description);
    load();
  }

  void updateEnumEntry(int enumIndex, String hexKey, String description) {
    _repo.updateEnumEntry(enumIndex, hexKey, description);
    load();
  }

  void removeEnumEntry(int enumIndex, String hexKey) {
    _repo.removeEnumEntry(enumIndex, hexKey);
    load();
  }

  void removeEnumGroup(int enumIndex) {
    _repo.removeEnumGroup(enumIndex);
    load();
  }

  // ── BIT_ENUM operations ───────────────────────────────────────────────────
  void addBitEnumEntry(int bitEnumIndex, int hexMask, String description) {
    _repo.addBitEnumEntry(bitEnumIndex, hexMask, description);
    load();
  }

  void updateBitEnumEntry(int bitEnumIndex, int hexMask, String description) {
    _repo.updateBitEnumEntry(bitEnumIndex, hexMask, description);
    load();
  }

  void removeBitEnumEntry(int bitEnumIndex, int hexMask) {
    _repo.removeBitEnumEntry(bitEnumIndex, hexMask);
    load();
  }

  void removeBitEnumGroup(int bitEnumIndex) {
    _repo.removeBitEnumGroup(bitEnumIndex);
    load();
  }

  // ── COMMAND operations ────────────────────────────────────────────────────
  void addCommand(String command, String description, List<String> req,
      List<String> resp, List<String> write) {
    _repo.addCommand(command, description, req, resp, write);
    load();
  }

  void updateCommand(String command, String description, List<String> req,
      List<String> resp, List<String> write) {
    _repo.updateCommand(command, description, req, resp, write);
    load();
  }

  void removeCommand(String command) {
    _repo.removeCommand(command);
    load();
  }
}
