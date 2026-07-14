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
  NativeHartSerialChannel(
    String name, {
    SerialPort Function(String name)? portFactory,
    SerialPortConfig Function()? configFactory,
    SerialPortReader Function(SerialPort port)? readerFactory,
    String Function()? errorGetter,
  })  : _port = (portFactory ?? SerialPort.new)(name),
        _configFactory = configFactory ?? SerialPortConfig.new,
        _readerFactory = readerFactory ?? SerialPortReader.new,
        _errorGetter = errorGetter ??
            (() => SerialPort.lastError?.message ?? 'Unknown error');

  final SerialPort _port;
  final SerialPortConfig Function() _configFactory;
  final SerialPortReader Function(SerialPort port) _readerFactory;
  final String Function() _errorGetter;
  SerialPortReader? _reader;

  @override
  bool openReadWrite() => _port.openReadWrite();

  @override
  String get lastError => _errorGetter();

  @override
  void configureHart() {
    final config = _configFactory()
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
    _reader = _readerFactory(_port);
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
