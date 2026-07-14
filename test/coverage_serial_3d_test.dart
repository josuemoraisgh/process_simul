import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:process_simul/app.dart';
import 'package:process_simul/application/providers/app_providers.dart';
import 'package:process_simul/data/datasources/sqlite_datasource.dart';
import 'package:process_simul/application/notifiers/log_notifier.dart';
import 'package:process_simul/infrastructure/hart/hart_serial_comm.dart';
import 'package:process_simul/infrastructure/hart/hart_frame.dart';
import 'package:process_simul/domain/entities/react_var.dart';
import 'package:process_simul/presentation/screens/tank_3d/boiler_3d_viewer.dart';
import 'package:process_simul/presentation/screens/tank_3d/boiler_state.dart';
import 'package:process_simul/presentation/screens/tank_3d/tank_3d_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_simul/main.dart' as entrypoint;

final class _FakeSerialChannel implements HartSerialChannel {
  _FakeSerialChannel(
      {this.opens = true, this.maxWrite, this.throwOnWrite = false});

  final bool opens;
  final int? maxWrite;
  final bool throwOnWrite;
  final controller = StreamController<Uint8List>.broadcast(sync: true);
  final written = <int>[];
  bool configured = false;
  bool open = false;
  bool throwOnCleanup = false;

  @override
  bool openReadWrite() => open = opens;

  @override
  String get lastError => 'fake open error';

  @override
  void configureHart() => configured = true;

  @override
  Stream<Uint8List> get input => controller.stream;

  @override
  void closeReader() {
    if (throwOnCleanup) throw StateError('reader cleanup');
  }

  @override
  bool get isOpen => open;

  @override
  bool close() {
    open = false;
    if (throwOnCleanup) throw StateError('close cleanup');
    return true;
  }

  @override
  int write(Uint8List bytes) {
    if (throwOnWrite) throw StateError('write');
    final count = maxWrite == null
        ? bytes.length
        : maxWrite! < bytes.length
            ? maxWrite!
            : bytes.length;
    if (count > 0) written.addAll(bytes.take(count));
    return count;
  }

  @override
  void dispose() {
    if (throwOnCleanup) throw StateError('dispose cleanup');
  }
}

ReactVar _serialCell(String name, String value) => ReactVar(
      tableName: 'HART',
      rowName: 'SERIAL',
      colName: name,
      byteSize: 1,
      typeStr: 'UNSIGNED',
      rawValue: value,
    );

Map<String, Map<String, ReactVar>> _serialTable() => {
      'SERIAL': {
        'polling_address': _serialCell('polling_address', '01'),
        'manufacturer_id': _serialCell('manufacturer_id', '0A'),
        'device_type': _serialCell('device_type', '0B'),
        'device_id': _serialCell('device_id', '010203'),
        'error_code': _serialCell('error_code', '0000'),
      },
    };

void main() {
  setUpAll(() => initGlobalLog(LogNotifier()));

  test('BoilerState defaults and copyWith expose every state field', () {
    const initial = BoilerState();
    expect(initial.waterLevel, 0.65);
    expect(initial.highlightedComponent, isNull);

    final changed = initial.copyWith(
      waterLevel: 0.1,
      flameOn: false,
      flameIntensity: 0.2,
      forcedDraftFanSpeed: 0.3,
      inducedDraftFanSpeed: 0.4,
      airDamperOpen: 0.5,
      flueGasDamperOpen: 0.6,
      fuelValveOpen: 0.7,
      highlightedComponent: 'drum',
      wavePhase: 0.8,
      fanPhase: 0.9,
    );
    expect(changed.waterLevel, 0.1);
    expect(changed.flameOn, isFalse);
    expect(changed.flameIntensity, 0.2);
    expect(changed.forcedDraftFanSpeed, 0.3);
    expect(changed.inducedDraftFanSpeed, 0.4);
    expect(changed.airDamperOpen, 0.5);
    expect(changed.flueGasDamperOpen, 0.6);
    expect(changed.fuelValveOpen, 0.7);
    expect(changed.highlightedComponent, 'drum');
    expect(changed.wavePhase, 0.8);
    expect(changed.fanPhase, 0.9);

    final preserved = changed.copyWith();
    expect(preserved.waterLevel, changed.waterLevel);
    expect(preserved.highlightedComponent, changed.highlightedComponent);
  });

  test('serial lifecycle rejects unavailable standard and virtual ports',
      () async {
    for (final name in const [
      'COM_PROCESS_SIMUL_DOES_NOT_EXIST_999',
      'PROCESS_SIMUL_DOES_NOT_EXIST_999',
    ]) {
      final server = HartSerialServer(
        portName: name,
        getTable: () => const {},
        writeCell: (_, __, ___) {},
      );
      expect(server.isRunning, isFalse);
      await server.stop();
      await expectLater(server.start(), throwsA(anything));
      expect(server.isRunning, isFalse);
    }
    try {
      expect(HartSerialServer.availablePorts(), isA<List<String>>());
    } catch (error) {
      // The native DLL is intentionally absent in headless CI.
      expect(error, isNotNull);
    }
  });

  test('serial channel processes short, long, unknown and overflow frames',
      () async {
    final channel = _FakeSerialChannel(maxWrite: 3);
    final writes = <String>[];
    final server = HartSerialServer(
      portName: 'FAKE',
      getTable: _serialTable,
      writeCell: (device, column, value) =>
          writes.add('$device:$column:$value'),
      channelFactory: (_) => channel,
      nativeSettleDelay: Duration.zero,
    );
    await server.start();
    await server.start();
    expect(server.isRunning, isTrue);
    expect(channel.configured, isTrue);

    channel.controller.add(
      HartFrame(delimiter: 0x02, address: 1, command: 0xFE).build(),
    );
    channel.controller.add(
      HartFrame(
        delimiter: 0x82,
        longAddress: const [0x0A, 0x0B, 1, 2, 3],
        command: 0xFE,
      ).build(),
    );
    channel.controller.add(
      HartFrame(delimiter: 0x02, address: 63, command: 0xFE).build(),
    );
    channel.controller.add(
      HartFrame(delimiter: 0x06, address: 1, command: 0xFE).build(),
    );
    channel.controller.addError(StateError('read'));
    channel.controller.add(Uint8List.fromList(List.filled(5000, 0xFF)));
    channel.controller.add(
      HartFrame(
        delimiter: 0x02,
        address: 1,
        command: 0x06,
        body: const [2, 1],
      ).build(),
    );
    await Future<void>.delayed(Duration.zero);
    expect(channel.written, isNotEmpty);
    expect(writes, isNotEmpty);

    channel.throwOnCleanup = true;
    await server.stop();
    await server.stop();
    expect(server.isRunning, isFalse);
    await channel.controller.close();
  });

  test('serial channel handles open, stalled write and write exceptions',
      () async {
    final failed = _FakeSerialChannel(opens: false);
    final failedServer = HartSerialServer(
      portName: 'FAIL',
      getTable: _serialTable,
      writeCell: (_, __, ___) {},
      channelFactory: (_) => failed,
    );
    await expectLater(failedServer.start(), throwsException);

    for (final channel in [
      _FakeSerialChannel(maxWrite: 0),
      _FakeSerialChannel(throwOnWrite: true),
    ]) {
      final server = HartSerialServer(
        portName: 'FAKE',
        getTable: _serialTable,
        writeCell: (_, __, ___) {},
        channelFactory: (_) => channel,
        nativeSettleDelay: Duration.zero,
      );
      await server.start();
      channel.controller.add(
        HartFrame(delimiter: 0x02, address: 1, command: 0xFE).build(),
      );
      await Future<void>.delayed(Duration.zero);
      await server.stop();
      await channel.controller.close();
    }

    final delayed = _FakeSerialChannel();
    final delayedServer = HartSerialServer(
      portName: 'FAKE',
      getTable: _serialTable,
      writeCell: (_, __, ___) {},
      channelFactory: (_) => delayed,
      nativeSettleDelay: const Duration(milliseconds: 1),
    );
    await delayedServer.start();
    await delayedServer.stop();
    await delayed.controller.close();
  });

  testWidgets('3D viewer has a deterministic loading state and safe teardown',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.pumpWidget(
      const MaterialApp(home: Boiler3dViewer()),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'ModelViewer'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('3D viewer load, error and state synchronization callbacks',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {
      'tank3d_camera_orbit': '1deg 2deg 3m',
      'tank3d_camera_target': '1m 2m 3m',
      'tank3d_field_of_view': '20deg',
    });
    var played = 0;
    var paused = 0;
    final scripts = <String>[];
    void Function(String)? onLoad;
    void Function(Object)? onError;
    void Function(List<dynamic>)? cameraChange;
    Widget viewer(BoilerState state) => MaterialApp(
          home: Boiler3dViewer(
            state: state,
            playAnimation: () => played++,
            pauseAnimation: () => paused++,
            javascriptEvaluator: scripts.add,
            cameraSaveDelay: Duration.zero,
            onCameraHandlerReady: (handler) => cameraChange = handler,
            onEscapePressed: () {},
            onDoubleClick: () {},
            viewerBuilder: (load, error) {
              onLoad = load;
              onError = error;
              return const SizedBox(key: Key('fake-3d-viewer'));
            },
          ),
        );

    await tester.pumpWidget(viewer(const BoilerState()));
    await tester.pump();
    expect(find.byKey(const Key('fake-3d-viewer')), findsOneWidget);
    onError!('forced');
    onLoad!('asset');
    await tester.pump();
    expect(played, 1);
    expect(scripts, hasLength(3));
    cameraChange!(const []);
    cameraChange!(const ['invalid']);
    cameraChange!(const ['4deg||5m||6deg']);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tank3d_camera_orbit'), '4deg');

    await tester.pumpWidget(viewer(const BoilerState(flameOn: false)));
    await tester.pump();
    expect(paused, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('application router builds its initial shell and theme',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final router = createAppRouter(overrides: {
      for (final path in const [
        '/tank3d',
        '/hart',
        '/modbus',
        '/settings',
        '/logs',
      ])
        path: (_) => Text(path, textDirection: TextDirection.ltr),
    });
    await tester.pumpWidget(
      ProviderScope(child: ProcessSimulApp(routerConfig: router)),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('/tank3d'), findsOneWidget);
    for (final icon in const [
      Icons.table_chart_outlined,
      Icons.settings_ethernet,
      Icons.tune,
      Icons.receipt_long_outlined,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    router.dispose();

    // Exercise the production router and default 3D viewer only through its
    // deterministic loading frame; no native WebView is created in the test.
    await tester.pumpWidget(const ProviderScope(child: ProcessSimulApp()));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('application initializer opens services and emits the root widget',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final temp = Directory.systemTemp.createTempSync('bootstrap-coverage-');
    final datasource = SqliteDatasource(documentsDirectory: () async => temp);
    final container = ProviderContainer(overrides: [
      sqliteDatasourceProvider.overrideWithValue(datasource),
    ]);
    Widget? root;
    try {
      await entrypoint.initializeApplication(
        providerContainerFactory: () => container,
        runner: (app) => root = app,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(root, isA<UncontrolledProviderScope>());
      expect(File('${temp.path}/process_simul.db').existsSync(), isTrue);
    } finally {
      container.dispose();
      datasource.close();
      temp.deleteSync(recursive: true);
    }
  });

  test('bootstrap and WebView2 redirect cover cross-platform startup',
      () async {
    var redirected = 0;
    var bound = 0;
    var initialized = 0;
    await entrypoint.bootstrapApplication(
      isWindows: true,
      redirectWebViewData: () => redirected++,
      ensureBinding: () => bound++,
      initializer: () async => initialized++,
    );
    expect((redirected, bound, initialized), (1, 1, 1));
    await entrypoint.bootstrapApplication(
      isWindows: false,
      ensureBinding: () => bound++,
      initializer: () async => initialized++,
    );

    entrypoint.applicationInitializerOverride = () async => initialized++;
    await entrypoint.main();
    entrypoint.applicationInitializerOverride = null;

    entrypoint.redirectWebView2UserDataFolder(environment: const {});
    String? directory;
    String? assignment;
    entrypoint.redirectWebView2UserDataFolder(
      environment: const {'LOCALAPPDATA': r'C:\Users\test\AppData\Local'},
      createDirectory: (path) => directory = path,
      setEnvironment: (name, value) => assignment = '$name=$value',
    );
    expect(directory, endsWith(r'process_simul\WebView2'));
    expect(assignment, contains('WEBVIEW2_USER_DATA_FOLDER='));
    entrypoint.redirectWebView2UserDataFolder(
      environment: const {'LOCALAPPDATA': 'x'},
      createDirectory: (_) => throw StateError('filesystem'),
      setEnvironment: (_, __) {},
    );
  });

  testWidgets('tank screen enters, times out and exits fullscreen',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final fullscreenValues = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Tank3dScreen(
        fullscreenSetter: (value) async => fullscreenValues.add(value),
        viewerBuilder: (_, __) => const ColoredBox(color: Colors.black),
      ),
    ));
    expect(find.text('Caldeira Aquatubular'), findsOneWidget);
    expect(isFullscreenNotifier.value, isFalse);

    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pump();
    expect(isFullscreenNotifier.value, isTrue);
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(isFullscreenNotifier.value, isFalse);
    expect(find.text('Caldeira Aquatubular'), findsOneWidget);
    expect(fullscreenValues, [true, false]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tank screen default desktop fullscreen and dispose paths',
      (tester) async {
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getBounds'
          ? {'x': 0.0, 'y': 0.0, 'width': 800.0, 'height': 600.0}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
      home: Tank3dScreen(
        viewerBuilder: (_, __) => const SizedBox.expand(),
      ),
    ));
    await tester.tap(find.byIcon(Icons.fullscreen));
    await tester.pump();
    await tester.pump();
    expect(isFullscreenNotifier.value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(isFullscreenNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
