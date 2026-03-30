import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'boiler_state.dart';

/// 3D Boiler viewer using flutter_3d_controller.
/// Works on Android, iOS, Windows, macOS, Linux, and Web
/// (all via model-viewer / flutter_inappwebview).
class Boiler3dViewer extends StatefulWidget {
  final BoilerState state;
  final ValueChanged<BoilerState>? onStateChanged;
  final bool showControls;

  const Boiler3dViewer({
    super.key,
    required this.state,
    this.onStateChanged,
    this.showControls = false,
  });

  @override
  State<Boiler3dViewer> createState() => _Boiler3dViewerState();
}

class _Boiler3dViewerState extends State<Boiler3dViewer> {
  late final Flutter3DController _controller;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = Flutter3DController();
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
}
