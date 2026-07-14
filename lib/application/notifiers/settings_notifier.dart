import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/enums/db_model.dart';

class AppSettings {
  static const int minPort = 1;
  static const int maxPort = 65535;
  static const int minTfStepMs = 10;
  static const int maxTfStepMs = 5000;
  final CommMode hartMode;
  final String hartSerialPort;
  final String hartTcpHost;
  final int hartServerPort;
  final int modbusPort;
  final int tfStepMs;
  final bool darkTheme;

  const AppSettings({
    this.hartMode = CommMode.tcp,
    this.hartSerialPort = 'COM1',
    this.hartTcpHost = '127.0.0.1',
    this.hartServerPort = 5094,
    this.modbusPort = 502,
    this.tfStepMs = 50,
    this.darkTheme = true,
  });

  static bool isValidPort(int value) => value >= minPort && value <= maxPort;

  static bool isValidTfStep(int value) =>
      value >= minTfStepMs && value <= maxTfStepMs;

  static bool isValidBindAddress(String value) =>
      InternetAddress.tryParse(value.trim()) != null;

  void validate() {
    if (!isValidPort(hartServerPort)) {
      throw RangeError.range(
        hartServerPort,
        minPort,
        maxPort,
        'hartServerPort',
      );
    }
    if (!isValidPort(modbusPort)) {
      throw RangeError.range(modbusPort, minPort, maxPort, 'modbusPort');
    }
    if (!isValidTfStep(tfStepMs)) {
      throw RangeError.range(
        tfStepMs,
        minTfStepMs,
        maxTfStepMs,
        'tfStepMs',
      );
    }
    if (!isValidBindAddress(hartTcpHost)) {
      throw FormatException('Invalid server bind address', hartTcpHost);
    }
  }

  AppSettings copyWith({
    CommMode? hartMode,
    String? hartSerialPort,
    String? hartTcpHost,
    int? hartServerPort,
    int? modbusPort,
    int? tfStepMs,
    bool? darkTheme,
  }) =>
      AppSettings(
        hartMode: hartMode ?? this.hartMode,
        hartSerialPort: hartSerialPort ?? this.hartSerialPort,
        hartTcpHost: hartTcpHost ?? this.hartTcpHost,
        hartServerPort: hartServerPort ?? this.hartServerPort,
        modbusPort: modbusPort ?? this.modbusPort,
        tfStepMs: tfStepMs ?? this.tfStepMs,
        darkTheme: darkTheme ?? this.darkTheme,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _keyHartMode = 'hart_mode';
  static const _keySerialPort = 'hart_serial_port';
  static const _keyTcpHost = 'hart_tcp_host';
  static const _keySrvPort = 'hart_server_port';
  static const _keyModbusPort = 'modbus_port';
  static const _keyTfStepMs = 'tf_step_ms';
  static const _keyDarkTheme = 'dark_theme';

  SettingsNotifier() : super(const AppSettings());

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final storedHartPort = p.getInt(_keySrvPort) ?? 5094;
    final storedModbusPort = p.getInt(_keyModbusPort) ?? 502;
    final storedTfStep = p.getInt(_keyTfStepMs) ?? 50;
    state = AppSettings(
      hartMode: p.getString(_keyHartMode) == 'serial'
          ? CommMode.serial
          : CommMode.tcp,
      hartSerialPort: p.getString(_keySerialPort) ?? 'COM1',
      hartTcpHost: AppSettings.isValidBindAddress(
              p.getString(_keyTcpHost) ?? '127.0.0.1')
          ? p.getString(_keyTcpHost) ?? '127.0.0.1'
          : '127.0.0.1',
      hartServerPort:
          AppSettings.isValidPort(storedHartPort) ? storedHartPort : 5094,
      modbusPort:
          AppSettings.isValidPort(storedModbusPort) ? storedModbusPort : 502,
      tfStepMs: AppSettings.isValidTfStep(storedTfStep) ? storedTfStep : 50,
      darkTheme: p.getBool(_keyDarkTheme) ?? true,
    );
  }

  Future<void> save(AppSettings s) async {
    s.validate();
    state = s;
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _keyHartMode, s.hartMode == CommMode.serial ? 'serial' : 'tcp');
    await p.setString(_keySerialPort, s.hartSerialPort);
    await p.setString(_keyTcpHost, s.hartTcpHost);
    await p.setInt(_keySrvPort, s.hartServerPort);
    await p.setInt(_keyModbusPort, s.modbusPort);
    await p.setInt(_keyTfStepMs, s.tfStepMs);
    await p.setBool(_keyDarkTheme, s.darkTheme);
  }

  Future<void> update(AppSettings Function(AppSettings) updater) async {
    await save(updater(state));
  }
}
