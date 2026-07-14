// ignore_for_file: implementation_imports, depend_on_referenced_packages
// Imports from flutter_3d_controller/src/* are intentional to access the
// internal ModelViewer for full rendering control. flutter_inappwebview is a
// transitive dependency exposed by flutter_3d_controller.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_3d_controller/src/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'boiler_model_viewer_adapter.dart';
import 'boiler_state.dart';

/// 3D Boiler viewer using ModelViewer directly for full control
/// over background, lighting, environment, and shadow.
class Boiler3dViewer extends StatefulWidget {
  final BoilerState state;
  final ValueChanged<BoilerState>? onStateChanged;
  final bool showControls;
  final VoidCallback? onEscapePressed;
  final VoidCallback? onDoubleClick;
  final VoidCallback? playAnimation;
  final VoidCallback? pauseAnimation;
  final FutureOr<void> Function(String source)? javascriptEvaluator;
  final ValueChanged<void Function(List<dynamic> args)>? onCameraHandlerReady;
  final Duration cameraSaveDelay;
  final Widget Function(
    void Function(String modelAddress) onLoad,
    void Function(Object error) onError,
  )? viewerBuilder;

  const Boiler3dViewer({
    super.key,
    this.state = const BoilerState(),
    this.onStateChanged,
    this.showControls = false,
    this.onEscapePressed,
    this.onDoubleClick,
    this.playAnimation,
    this.pauseAnimation,
    this.javascriptEvaluator,
    this.onCameraHandlerReady,
    this.cameraSaveDelay = const Duration(milliseconds: 800),
    this.viewerBuilder,
  });

  @override
  State<Boiler3dViewer> createState() => _Boiler3dViewerState();
}

class _Boiler3dViewerState extends State<Boiler3dViewer> {
  late final Flutter3DController _controller;
  late final String _id;
  final Utils _utils = Utils();
  bool _isLoaded = false;
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
    initializeBoilerControllerForWeb(_controller, _id);
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
    _saveTimer = Timer(widget.cameraSaveDelay, () async {
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
      (widget.playAnimation ?? _controller.playAnimation)();
    } else {
      (widget.pauseAnimation ?? _controller.pauseAnimation)();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.onModelLoaded.dispose();
    super.dispose();
  }

  void _injectJsHandlers() {
    final evaluator = widget.javascriptEvaluator;
    if (evaluator == null) return;
    // Apply tone-mapping and extra rendering attributes via JS
    evaluator('''
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
      evaluator('''
        document.addEventListener('keydown', function(e) {
          if (e.key === 'Escape') {
            e.preventDefault();
            window.flutter_inappwebview.callHandler('onEscapePressed');
          }
        });
      ''');
    }
    if (widget.onDoubleClick != null) {
      evaluator('''
        document.addEventListener('dblclick', function(e) {
          e.preventDefault();
          window.flutter_inappwebview.callHandler('onDoubleClick');
        });
      ''');
    }
  }

  void _handleModelLoad(String modelAddress) {
    _controller.onModelLoaded.value = true;
    setState(() => _isLoaded = true);
    _syncModelState();
    _injectJsHandlers();
  }

  void _handleModelError(Object error) {
    _controller.onModelLoaded.value = false;
    debugPrint('Boiler3dViewer error: $error');
  }

  void _handleCameraChange(List<dynamic> args) {
    if (args.isEmpty) return;
    final parts = args[0].toString().split('||');
    if (parts.length == 3) {
      _saveCameraState(parts[0], parts[1], parts[2]);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.onCameraHandlerReady?.call(_handleCameraChange);
    if (!_cameraReady) {
      return const ColoredBox(
        color: Color(0xFF1a1a2e),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final viewerBuilder = widget.viewerBuilder;
    if (viewerBuilder != null) {
      return viewerBuilder(_handleModelLoad, _handleModelError);
    }
    return buildBoilerModelViewer(
      id: _id,
      controller: _controller,
      utils: _utils,
      cameraOrbit: _cameraOrbit!,
      cameraTarget: _cameraTarget,
      fieldOfView: _fieldOfView,
      onLoad: _handleModelLoad,
      onError: _handleModelError,
      onCameraChange: _handleCameraChange,
      onEscapePressed: widget.onEscapePressed,
      onDoubleClick: widget.onDoubleClick,
    );
  }
}
