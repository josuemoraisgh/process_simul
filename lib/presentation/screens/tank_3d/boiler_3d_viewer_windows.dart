import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';
import 'boiler_state.dart';

/// 3D Boiler viewer for Windows using webview_windows (WebView2) + model-viewer.
class Boiler3dViewerWindows extends StatefulWidget {
  final BoilerState state;
  final ValueChanged<BoilerState>? onStateChanged;
  final bool showControls;

  const Boiler3dViewerWindows({
    super.key,
    required this.state,
    this.onStateChanged,
    this.showControls = false,
  });

  @override
  State<Boiler3dViewerWindows> createState() => _Boiler3dViewerWindowsState();
}

class _Boiler3dViewerWindowsState extends State<Boiler3dViewerWindows> {
  final _webController = WebviewController();
  bool _isReady = false;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      // 1. Copy assets to temp directory
      final tempDir = await getTemporaryDirectory();
      final modelDir = Directory(p.join(tempDir.path, 'boiler_3d'));
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      // Copy HTML
      final htmlBytes =
          await rootBundle.load('assets/models/model_viewer.html');
      final htmlFile = File(p.join(modelDir.path, 'model_viewer.html'));
      await htmlFile.writeAsBytes(htmlBytes.buffer.asUint8List());

      // Copy GLB model (may not exist yet)
      try {
        final glbBytes = await rootBundle.load('assets/models/boiler.glb');
        final glbFile = File(p.join(modelDir.path, 'boiler.glb'));
        await glbFile.writeAsBytes(glbBytes.buffer.asUint8List());
      } catch (e) {
        debugPrint('GLB model not found in assets (expected): $e');
      }

      // 2. Initialize WebView2
      await _webController.initialize();

      if (!mounted) return;
      setState(() => _isInitialized = true);

      // 3. Set up listeners BEFORE loading the URL
      _webController.webMessage.listen((message) {
        _onJsMessage(message);
      });

      _webController.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted && mounted) {
          setState(() => _isReady = true);
          _syncState();
          if (!widget.showControls) {
            _webController.postWebMessage(
              jsonEncode({'hideControls': true}),
            );
          }
        }
      });

      // 4. Load the HTML file
      final htmlUri = Uri.file(htmlFile.path).toString();
      debugPrint('Loading WebView URL: $htmlUri');
      await _webController.loadUrl(htmlUri);
    } catch (e, stack) {
      debugPrint('WebView init failed: $e\n$stack');
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  @override
  void didUpdateWidget(Boiler3dViewerWindows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isReady) {
      _syncState();
    }
  }

  void _syncState() {
    if (!_isReady) return;
    final msg = jsonEncode({
      'waterLevel': widget.state.waterLevel,
      'flameIntensity': widget.state.flameIntensity,
      'fanSpeed': widget.state.forcedDraftFanSpeed,
    });
    _webController.postWebMessage(msg);
  }

  void _onJsMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString()) as Map<String, dynamic>;
      final param = data['param'] as String?;
      final value = (data['value'] as num?)?.toDouble();
      if (param == null || value == null) return;

      final current = widget.state;
      BoilerState newState;
      switch (param) {
        case 'waterLevel':
          newState = current.copyWith(waterLevel: value);
          break;
        case 'flameIntensity':
          newState = current.copyWith(
            flameIntensity: value,
            flameOn: value > 0.02,
          );
          break;
        case 'fanSpeed':
          newState = current.copyWith(forcedDraftFanSpeed: value);
          break;
        default:
          return;
      }
      widget.onStateChanged?.call(newState);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                'Erro ao inicializar WebView:\n$_errorMessage',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF58a6ff)),
            SizedBox(height: 12),
            Text('Inicializando WebView2...',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      );
    }
    return Webview(_webController);
  }

  @override
  void dispose() {
    _webController.dispose();
    super.dispose();
  }
}
