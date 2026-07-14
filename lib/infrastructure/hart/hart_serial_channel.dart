import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

abstract interface class HartSerialChannel {
  bool openReadWrite();
  String get lastError;
  void configureHart();
  Stream<Uint8List> get input;
  void closeReader();
  bool get isOpen;
  bool close();
  int write(Uint8List bytes);
  void dispose();
}

typedef HartSerialChannelFactory = HartSerialChannel Function(String name);

/// Thin platform adapter; protocol behavior remains independently testable
/// without loading the native serial library.
final class NativeHartSerialChannel implements HartSerialChannel {
  NativeHartSerialChannel(String name) : _port = SerialPort(name);

  final SerialPort _port;
  SerialPortReader? _reader;

  @override
  bool openReadWrite() => _port.openReadWrite();

  @override
  String get lastError => SerialPort.lastError?.message ?? 'Unknown error';

  @override
  void configureHart() {
    final config = SerialPortConfig()
      ..baudRate = 1200
      ..bits = 8
      ..parity = SerialPortParity.odd
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    try {
      _port.config = config;
    } finally {
      config.dispose();
    }
    _reader = SerialPortReader(_port);
  }

  @override
  Stream<Uint8List> get input => _reader!.stream;

  @override
  void closeReader() => _reader?.close();

  @override
  bool get isOpen => _port.isOpen;

  @override
  bool close() => _port.close();

  @override
  int write(Uint8List bytes) => _port.write(bytes);

  @override
  void dispose() => _port.dispose();
}
