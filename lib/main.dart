import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // WebView2 (used by flutter_inappwebview for the 3D viewer) creates its user
  // data folder inside the current working directory. When the app is installed
  // in C:\Program Files, that directory is read-only for regular users, which
  // causes WebView2 to fail silently and the 3D view to stay blank.
  // Redirecting Directory.current to LOCALAPPDATA makes WebView2 write there.
  if (!kIsWeb && Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null) {
      final dataDir = Directory('$localAppData\\process_simul');
      await dataDir.create(recursive: true);
      Directory.current = dataDir;
    }
  }

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
