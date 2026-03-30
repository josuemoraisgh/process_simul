import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';
import 'boiler_3d_viewer.dart';
import 'boiler_state.dart';

class Tank3dFullscreenScreen extends StatefulWidget {
  const Tank3dFullscreenScreen({super.key});

  @override
  State<Tank3dFullscreenScreen> createState() => _Tank3dFullscreenScreenState();
}

class _Tank3dFullscreenScreenState extends State<Tank3dFullscreenScreen> {
  var _state = const BoilerState();
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
                state: _state,
                onStateChanged: (s) => setState(() => _state = s),
                showControls: false,
                onEscapePressed: _goBack,
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
            // Controls panel
            Positioned(
              left: 40,
              right: 40,
              bottom: 30,
              child: AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showUI,
                  child: Material(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      child: Row(
                        children: [
                          _buildMiniSlider(
                              Icons.water_drop_outlined,
                              const Color(0xFF4fc3f7),
                              _state.waterLevel,
                              (v) => setState(() =>
                                  _state = _state.copyWith(waterLevel: v))),
                          const SizedBox(width: 12),
                          _buildMiniSlider(
                              Icons.local_fire_department_outlined,
                              const Color(0xFFff9800),
                              _state.flameIntensity,
                              (v) => setState(() => _state = _state.copyWith(
                                  flameIntensity: v, flameOn: v > 0.02))),
                          const SizedBox(width: 12),
                          _buildMiniSlider(
                              Icons.air,
                              const Color(0xFF4dd0e1),
                              _state.forcedDraftFanSpeed,
                              (v) => setState(() => _state =
                                  _state.copyWith(forcedDraftFanSpeed: v))),
                        ],
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

  Widget _buildMiniSlider(IconData icon, Color color, double value,
      ValueChanged<double> onChanged) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: color.withOpacity(0.7),
                inactiveTrackColor: const Color(0xFF1e3a5f),
                thumbColor: color,
                overlayColor: color.withOpacity(0.15),
              ),
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
          Text('${(value * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
