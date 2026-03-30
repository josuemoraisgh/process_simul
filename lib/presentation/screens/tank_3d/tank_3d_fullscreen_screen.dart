import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'boiler_3d_viewer.dart';

class Tank3dFullscreenScreen extends StatefulWidget {
  const Tank3dFullscreenScreen({super.key});

  @override
  State<Tank3dFullscreenScreen> createState() => _Tank3dFullscreenScreenState();
}

class _Tank3dFullscreenScreenState extends State<Tank3dFullscreenScreen> {
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _scheduleHideUI();
    _enterFullscreen();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _goBack();
      return true;
    }
    return false;
  }

  Future<void> _enterFullscreen() async {
    if (!kIsWeb && Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setFullScreen(true);
    }
  }

  Future<void> _exitFullscreen() async {
    if (!kIsWeb && Platform.isWindows) {
      await windowManager.setFullScreen(false);
    }
  }

  void _scheduleHideUI() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _showUI) setState(() => _showUI = false);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _exitFullscreen();
    super.dispose();
  }

  void _goBack() async {
    await _exitFullscreen();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080b10),
      body: GestureDetector(
        onTap: () {
          setState(() => _showUI = !_showUI);
          if (_showUI) _scheduleHideUI();
        },
        child: Stack(
          children: [
            // Background
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [Color(0xFF141820), Color(0xFF080b10)],
                ),
              ),
            ),
            // 3D Boiler Viewer
            Positioned.fill(
              child: Boiler3dViewer(
                onEscapePressed: _goBack,
                onDoubleClick: _goBack,
              ),
            ),
            // Exit fullscreen button (top-right)
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showUI,
                  child: Material(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _goBack,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.fullscreen_exit,
                            color: Colors.white70, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
