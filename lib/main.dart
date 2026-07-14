import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers/app_providers.dart';
import 'infrastructure/windows/webview2_environment.dart';

/// Optional process-level hook used by embedders and deterministic tests.
Future<void> Function()? applicationInitializerOverride;

Future<void> main() async {
  await bootstrapApplication(initializer: applicationInitializerOverride);
}

Future<void> bootstrapApplication({
  bool? isWindows,
  VoidCallback? redirectWebViewData,
  VoidCallback? ensureBinding,
  Future<void> Function()? initializer,
}) async {
  // WebView2 (used by flutter_inappwebview / flutter_3d_controller) creates
  // its user-data folder next to the executable by default. When installed
  // in C:\Program Files, that folder is read-only and WebView2 fails
  // silently → blank 3D viewer. Setting WEBVIEW2_USER_DATA_FOLDER before
  // WebView2 initialises makes it write into LOCALAPPDATA instead.
  //
  // We do NOT change Directory.current, because Flutter Windows uses it to
  // locate `data/flutter_assets/`.
  if (!kIsWeb && (isWindows ?? Platform.isWindows)) {
    (redirectWebViewData ?? redirectWebView2UserDataFolder)();
  }

  (ensureBinding ?? WidgetsFlutterBinding.ensureInitialized)();

  await (initializer ?? initializeApplication)();
}

/// Initializes application services and hands the root widget to [runner].
/// Optional injection keeps startup fully testable without touching the real
/// documents database or installing a global Flutter view.
Future<void> initializeApplication({
  ProviderContainer? providerContainer,
  ProviderContainer Function() providerContainerFactory = ProviderContainer.new,
  void Function(Widget app)? runner,
}) async {
  final container = providerContainer ?? providerContainerFactory();
  final appRunner = runner ?? runApp;

  // Create a ProviderContainer to initialise services before first frame.
  // Initialise database
  await container.read(dbRepositoryProvider).init();

  // Initialise global log so infrastructure layers can log via globalLog
  container.read(logProvider);

  // Load persisted settings
  await container.read(settingsProvider.notifier).load();

  // Load HART table (non-blocking – UI shows loader while pending)
  container.read(hartTableProvider.notifier).load();

  // Load Modbus variable/address table (non-blocking) so register values are
  // available as soon as the Modbus server is started, without requiring the
  // user to open the Modbus table screen first.
  container.read(modbusTableProvider.notifier).load();

  appRunner(
    UncontrolledProviderScope(
      container: container,
      child: const ProcessSimulApp(),
    ),
  );
}

/// Sets WEBVIEW2_USER_DATA_FOLDER for the current process via Win32
/// SetEnvironmentVariableW so WebView2 writes its user data into LOCALAPPDATA.
void redirectWebView2UserDataFolder({
  Map<String, String>? environment,
  void Function(String path)? createDirectory,
  void Function(String name, String value)? setEnvironment,
}) {
  try {
    final localAppData = (environment ?? Platform.environment)['LOCALAPPDATA'];
    if (localAppData == null) return;
    final folder = '$localAppData\\process_simul\\WebView2';
    (createDirectory ??
        (path) => Directory(path).createSync(recursive: true))(folder);
    (setEnvironment ?? setWindowsEnvironmentVariable)(
        'WEBVIEW2_USER_DATA_FOLDER', folder);
  } catch (_) {
    // Silently ignore — WebView2 will fall back to default behaviour.
  }
}
