import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_3d_controller/src/core/modules/model_viewer/model_viewer.dart';
import 'package:flutter_3d_controller/src/data/datasources/i_flutter_3d_datasource.dart';
import 'package:flutter_3d_controller/src/data/repositories/flutter_3d_repository.dart';
import 'package:flutter_3d_controller/src/utils/utils.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String? _cameraOrbit;
  String? _cameraTarget;
  String? _fieldOfView;
  Timer? _saveTimer;
  bool _cameraReady = false;

  static const _kOrbitKey = 'tank3d_camera_orbit';
  static const _kTargetKey = 'tank3d_camera_target';
  static const _kFovKey = 'tank3d_field_of_view';
  static const _kDefaultOrbit = '30deg 65deg 7m';
  static const _kDefaultTarget = 'auto auto auto';
  static const _kDefaultFov = 'auto';

  @override
  void initState() {
    super.initState();
    _id = _utils.generateId();
    _controller = Flutter3DController();
    if (kIsWeb) {
      _controller
          .init(Flutter3DRepository(IFlutter3DDatasource(_id, null, false)));
    }
    _loadCameraState();
  }

  Future<void> _loadCameraState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _cameraOrbit = prefs.getString(_kOrbitKey) ?? _kDefaultOrbit;
        _cameraTarget = prefs.getString(_kTargetKey) ?? _kDefaultTarget;
        _fieldOfView = prefs.getString(_kFovKey) ?? _kDefaultFov;
        _cameraReady = true;
      });
    }
  }

  void _saveCameraState(String orbit, String target, String fov) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kOrbitKey, orbit);
      await prefs.setString(_kTargetKey, target);
      await prefs.setString(_kFovKey, fov);
    });
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
    _saveTimer?.cancel();
    _controller.onModelLoaded.dispose();
    super.dispose();
  }

  void _injectJsHandlers() {
    final wvc = _webViewController;
    if (wvc == null) return;
    // Apply tone-mapping and extra rendering attributes via JS
    wvc.evaluateJavascript(source: '''
      var mv = document.querySelector('model-viewer');
      if (mv) {
        mv.setAttribute('tone-mapping', 'commerce');
        mv.setAttribute('environment-intensity', '1.8');
        mv.setAttribute('shadow-intensity', '2');
        mv.addEventListener('camera-change', function(e) {
          if (e.detail && e.detail.source === 'user-interaction') {
            var co = mv.getCameraOrbit();
            var ct = mv.getCameraTarget();
            var fov = mv.getFieldOfView();
            var data = co.toString() + '||' + ct.toString() + '||' + fov.toString() + 'deg';
            window.flutter_inappwebview.callHandler('onCameraChange', data);
          }
        });
      }
    ''');
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
    if (!_cameraReady) {
      return const ColoredBox(
        color: Color(0xFF1a1a2e),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ModelViewer(
      id: _id,
      src: 'assets/models/tank.glb',
      backgroundColor: const Color(0xFF1a1a2e),
      environmentImage: 'neutral',
      exposure: 1.2,
      shadowIntensity: 1.0,
      shadowSoftness: 0.8,
      cameraControls: true,
      autoRotate: false,
      cameraOrbit: _cameraOrbit!,
      cameraTarget: _cameraTarget,
      fieldOfView: _fieldOfView,
      interactionPrompt: InteractionPrompt.none,
      disableTap: true,
      ar: false,
      autoPlay: false,
      debugLogging: false,
      activeGestureInterceptor: true,
      relatedCss: '''
        model-viewer {
          --poster-color: #1a1a2e;
          --progress-bar-color: #4fc3f7;
        }
      ''',
      relatedJs: _utils.injectedJS(_id, 'flutter-3d-controller'),
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
              webViewController.addJavaScriptHandler(
                handlerName: 'onCameraChange',
                callback: (args) {
                  if (args.isNotEmpty) {
                    final parts = args[0].toString().split('||');
                    if (parts.length == 3) {
                      _saveCameraState(parts[0], parts[1], parts[2]);
                    }
                  }
                },
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
