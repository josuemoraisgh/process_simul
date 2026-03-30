import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'boiler_state.dart';

/// 3D Boiler viewer for Android using flutter_3d_controller (model-viewer native).
class Boiler3dViewerAndroid extends StatefulWidget {
  final BoilerState state;
  final ValueChanged<BoilerState>? onStateChanged;

  const Boiler3dViewerAndroid({
    super.key,
    required this.state,
    this.onStateChanged,
  });

  @override
  State<Boiler3dViewerAndroid> createState() => _Boiler3dViewerAndroidState();
}

class _Boiler3dViewerAndroidState extends State<Boiler3dViewerAndroid> {
  late final Flutter3DController _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = Flutter3DController();
  }

  @override
  void didUpdateWidget(Boiler3dViewerAndroid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isLoaded) {
      _syncModelState();
    }
  }

  void _syncModelState() {
    final s = widget.state;

    // Control flame visibility via animation or camera
    // flutter_3d_controller supports playAnimation, pauseAnimation,
    // setCameraOrbit, setCameraTarget
    // For node-level control, we use JavaScript evaluation

    // Play/pause built-in animations
    if (s.flameOn && s.flameIntensity > 0.02) {
      _controller.playAnimation();
    } else {
      _controller.pauseAnimation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Flutter3DViewer(
      controller: _controller,
      src: 'assets/models/boiler.glb',
      onLoad: (_) {
        setState(() => _isLoaded = true);
        _syncModelState();
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
