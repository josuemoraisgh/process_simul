import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_3d_controller/src/core/modules/model_viewer/model_viewer.dart';
import 'package:flutter_3d_controller/src/data/datasources/i_flutter_3d_datasource.dart';
import 'package:flutter_3d_controller/src/data/repositories/flutter_3d_repository.dart';
import 'package:flutter_3d_controller/src/utils/utils.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'boiler_state.dart';

/// 3D Boiler viewer using ModelViewer directly for full control
/// over background, lighting, environment, and shadow.
class Boiler3dViewer extends StatefulWidget {
  final BoilerState state;
  final ValueChanged<BoilerState>? onStateChanged;
  final bool showControls;
  final VoidCallback? onEscapePressed;
  final VoidCallback? onDoubleClick;

  const Boiler3dViewer({
    super.key,
    this.state = const BoilerState(),
    this.onStateChanged,
    this.showControls = false,
    this.onEscapePressed,
    this.onDoubleClick,
  });

  @override
  State<Boiler3dViewer> createState() => _Boiler3dViewerState();
}

class _Boiler3dViewerState extends State<Boiler3dViewer> {
  late final Flutter3DController _controller;
  late final String _id;
  final Utils _utils = Utils();
  bool _isLoaded = false;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _id = _utils.generateId();
    _controller = Flutter3DController();
    if (kIsWeb) {
      _controller
          .init(Flutter3DRepository(IFlutter3DDatasource(_id, null, false)));
    }
  }

  @override
  void didUpdateWidget(Boiler3dViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isLoaded) {
      _syncModelState();
    }
  }

  void _syncModelState() {
    final s = widget.state;
    if (s.flameOn && s.flameIntensity > 0.02) {
      _controller.playAnimation();
    } else {
      _controller.pauseAnimation();
    }
  }

  @override
  void dispose() {
    _controller.onModelLoaded.dispose();
    super.dispose();
  }

  void _injectJsHandlers() {
    final wvc = _webViewController;
    if (wvc == null) return;
    if (widget.onEscapePressed != null) {
      wvc.evaluateJavascript(source: '''
        document.addEventListener('keydown', function(e) {
          if (e.key === 'Escape') {
            e.preventDefault();
            window.flutter_inappwebview.callHandler('onEscapePressed');
          }
        });
      ''');
    }
    if (widget.onDoubleClick != null) {
      wvc.evaluateJavascript(source: '''
        document.addEventListener('dblclick', function(e) {
          e.preventDefault();
          window.flutter_inappwebview.callHandler('onDoubleClick');
        });
      ''');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      id: _id,
      src: 'assets/models/boiler.glb',
      backgroundColor: const Color(0xFF0d1117),
      environmentImage: 'neutral',
      exposure: 1.0,
      shadowIntensity: 0.4,
      shadowSoftness: 0.8,
      cameraControls: true,
      autoRotate: false,
      cameraOrbit: '45deg 55deg 105%',
      interactionPrompt: InteractionPrompt.none,
      disableTap: true,
      ar: false,
      autoPlay: false,
      debugLogging: false,
      activeGestureInterceptor: true,
      relatedJs: _utils.injectedJS(_id, 'flutter-3d-controller'),
      onProgress: null,
      onLoad: (modelAddress) {
        _controller.onModelLoaded.value = true;
        setState(() => _isLoaded = true);
        _syncModelState();
        _injectJsHandlers();
      },
      onError: (error) {
        _controller.onModelLoaded.value = false;
        debugPrint('Boiler3dViewer error: $error');
      },
      onWebViewCreated: kIsWeb
          ? null
          : (InAppWebViewController webViewController) {
              _webViewController = webViewController;
              _controller.init(
                Flutter3DRepository(
                  IFlutter3DDatasource(_id, webViewController, true),
                ),
              );
              if (widget.onEscapePressed != null) {
                webViewController.addJavaScriptHandler(
                  handlerName: 'onEscapePressed',
                  callback: (_) => widget.onEscapePressed!(),
                );
              }
              if (widget.onDoubleClick != null) {
                webViewController.addJavaScriptHandler(
                  handlerName: 'onDoubleClick',
                  callback: (_) => widget.onDoubleClick!(),
                );
              }
            },
    );
  }
}
