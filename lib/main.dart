import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers/app_providers.dart';

Future<void> main() async {
  // WebView2 (used by flutter_inappwebview / flutter_3d_controller) creates
  // its user-data folder next to the executable by default. When installed
  // in C:\Program Files, that folder is read-only and WebView2 fails
  // silently → blank 3D viewer. Setting WEBVIEW2_USER_DATA_FOLDER before
  // WebView2 initialises makes it write into LOCALAPPDATA instead.
  //
  // We do NOT change Directory.current, because Flutter Windows uses it to
  // locate `data/flutter_assets/`.
  if (!kIsWeb && Platform.isWindows) {
    _redirectWebView2UserDataFolder();
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Create a ProviderContainer to initialise services before first frame.
  final container = ProviderContainer();

  // Initialise database
  await container.read(dbRepositoryProvider).init();

  // Initialise global log so infrastructure layers can log via globalLog
  container.read(logProvider);

  // Load persisted settings
  await container.read(settingsProvider.notifier).load();

  // Load HART table (non-blocking – UI shows loader while pending)
  container.read(hartTableProvider.notifier).load();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ProcessSimulApp(),
    ),
  );
}

/// Sets WEBVIEW2_USER_DATA_FOLDER for the current process via Win32
/// SetEnvironmentVariableW so WebView2 writes its user data into LOCALAPPDATA.
void _redirectWebView2UserDataFolder() {
  try {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null) return;
    final folder = '$localAppData\\process_simul\\WebView2';
    Directory(folder).createSync(recursive: true);

    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setEnv = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)>(
      'SetEnvironmentVariableW',
    );
    final pName = 'WEBVIEW2_USER_DATA_FOLDER'.toNativeUtf16();
    final pValue = folder.toNativeUtf16();
    try {
      setEnv(pName, pValue);
    } finally {
      malloc.free(pName);
      malloc.free(pValue);
    }
  } catch (_) {
    // Silently ignore — WebView2 will fall back to default behaviour.
  }
}
