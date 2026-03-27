import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/enums/db_model.dart';

class AppSettings {
  final CommMode hartMode;
  final String hartSerialPort;
  final String hartTcpHost;
  final int hartTcpPort;
  final int hartServerPort;
  final int modbusPort;
  final bool darkTheme;

  const AppSettings({
    this.hartMode       = CommMode.tcp,
    this.hartSerialPort = 'COM1',
    this.hartTcpHost    = '127.0.0.1',
    this.hartTcpPort    = 5094,
    this.hartServerPort = 5094,
    this.modbusPort     = 502,
    this.darkTheme      = true,
  });

  AppSettings copyWith({
    CommMode? hartMode,
    String?   hartSerialPort,
    String?   hartTcpHost,
    int?      hartTcpPort,
    int?      hartServerPort,
    int?      modbusPort,
    bool?     darkTheme,
  }) => AppSettings(
    hartMode:       hartMode       ?? this.hartMode,
    hartSerialPort: hartSerialPort ?? this.hartSerialPort,
    hartTcpHost:    hartTcpHost    ?? this.hartTcpHost,
    hartTcpPort:    hartTcpPort    ?? this.hartTcpPort,
    hartServerPort: hartServerPort ?? this.hartServerPort,
    modbusPort:     modbusPort     ?? this.modbusPort,
    darkTheme:      darkTheme      ?? this.darkTheme,
  );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _keyHartMode    = 'hart_mode';
  static const _keySerialPort  = 'hart_serial_port';
  static const _keyTcpHost     = 'hart_tcp_host';
  static const _keyTcpPort     = 'hart_tcp_port';
  static const _keySrvPort     = 'hart_server_port';
  static const _keyModbusPort  = 'modbus_port';
  static const _keyDarkTheme   = 'dark_theme';

  SettingsNotifier() : super(const AppSettings());

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    state = AppSettings(
      hartMode:       p.getString(_keyHartMode) == 'serial' ? CommMode.serial : CommMode.tcp,
      hartSerialPort: p.getString(_keySerialPort)  ?? 'COM1',
      hartTcpHost:    p.getString(_keyTcpHost)     ?? '127.0.0.1',
      hartTcpPort:    p.getInt(_keyTcpPort)        ?? 5094,
      hartServerPort: p.getInt(_keySrvPort)        ?? 5094,
      modbusPort:     p.getInt(_keyModbusPort)     ?? 502,
      darkTheme:      p.getBool(_keyDarkTheme)     ?? true,
    );
  }

  Future<void> save(AppSettings s) async {
    state = s;
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyHartMode,   s.hartMode == CommMode.serial ? 'serial' : 'tcp');
    await p.setString(_keySerialPort, s.hartSerialPort);
    await p.setString(_keyTcpHost,    s.hartTcpHost);
    await p.setInt(_keyTcpPort,       s.hartTcpPort);
    await p.setInt(_keySrvPort,       s.hartServerPort);
    await p.setInt(_keyModbusPort,    s.modbusPort);
    await p.setBool(_keyDarkTheme,    s.darkTheme);
  }

  Future<void> update(AppSettings Function(AppSettings) updater) async {
    await save(updater(state));
  }
}
