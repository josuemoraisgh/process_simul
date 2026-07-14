import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Native Win32 boundary kept separate from cross-platform startup logic.
void setWindowsEnvironmentVariable(String name, String value) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setEnv = kernel32.lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>(
    'SetEnvironmentVariableW',
  );
  final pName = name.toNativeUtf16();
  final pValue = value.toNativeUtf16();
  try {
    setEnv(pName, pValue);
  } finally {
    malloc.free(pName);
    malloc.free(pValue);
  }
}
