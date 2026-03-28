import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers/app_providers.dart';

Future<void> main() async {
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
