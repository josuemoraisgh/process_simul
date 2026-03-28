import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'application/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite_common_ffi is required for Windows / Linux / macOS desktop.
  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
