import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'boiler_3d_viewer.dart';

/// Global notifier so MainShell can hide its chrome in fullscreen mode.
final isFullscreenNotifier = ValueNotifier<bool>(false);

class Tank3dScreen extends StatefulWidget {
  const Tank3dScreen({super.key});

  @override
  State<Tank3dScreen> createState() => _Tank3dScreenState();
}

class _Tank3dScreenState extends State<Tank3dScreen> {
  bool _isFullscreen = false;
  bool _showExitButton = true;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    if (_isFullscreen) {
      isFullscreenNotifier.value = false;
      _setFullscreen(false);
    }
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (_isFullscreen &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _toggleFullscreen();
      return true;
    }
    return false;
  }

  Future<void> _setFullscreen(bool value) async {
    if (!kIsWeb && Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setFullScreen(value);
    }
  }

  void _toggleFullscreen() async {
    final goFull = !_isFullscreen;
    setState(() {
      _isFullscreen = goFull;
      _showExitButton = goFull;
    });
    isFullscreenNotifier.value = goFull;
    await _setFullscreen(goFull);
    if (goFull) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && _showExitButton) {
          setState(() => _showExitButton = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0d1117), Color(0xFF161b22), Color(0xFF0d1117)],
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Header bar (hidden in fullscreen)
              if (!_isFullscreen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.view_in_ar,
                          color: Color(0xFF58a6ff), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Caldeira Aquatubular',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1e3a5f),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DIGITAL TWIN',
                          style: TextStyle(
                            color: Color(0xFF4fc3f7),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.fullscreen,
                            color: Colors.white54, size: 22),
                        tooltip: 'Tela cheia',
                        onPressed: _toggleFullscreen,
                      ),
                    ],
                  ),
                ),
              // 3D Canvas
              Expanded(
                child: Boiler3dViewer(
                  onEscapePressed: _isFullscreen ? _toggleFullscreen : null,
                  onDoubleClick: _toggleFullscreen,
                ),
              ),
            ],
          ),
          // Exit fullscreen button (top-right, only in fullscreen)
          if (_isFullscreen)
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedOpacity(
                opacity: _showExitButton ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showExitButton,
                  child: Material(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _toggleFullscreen,
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
    );
  }
}
