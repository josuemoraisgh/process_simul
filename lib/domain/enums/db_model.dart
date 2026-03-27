/// Represents which kind of data a ReactVar cell holds.
enum DbModel {
  /// Plain hexadecimal value stored directly.
  value,

  /// An expression starting with '@' evaluated at runtime.
  func,

  /// A transfer-function spec starting with '$' simulated in the background.
  tFunc,
}

/// Represents the display/conversion state requested for a ReactVar value.
enum DbState {
  /// Raw hex string as stored in the database.
  originValue,

  /// Hex string (same as origin for value; computed hex for func/tFunc).
  machineValue,

  /// Engineering-unit human-readable string.
  humanValue,
}

/// HART/Modbus communication mode.
enum CommMode { serial, tcp }

/// Connection state for HART or Modbus services.
enum ConnectionState { disconnected, connecting, connected, error }
