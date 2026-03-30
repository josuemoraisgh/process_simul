import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'boiler_3d_viewer.dart';
import 'boiler_state.dart';

class Tank3dScreen extends StatefulWidget {
  const Tank3dScreen({super.key});

  @override
  State<Tank3dScreen> createState() => _Tank3dScreenState();
}

class _Tank3dScreenState extends State<Tank3dScreen> {
  var _state = const BoilerState();

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
      child: Column(
        children: [
          // Header bar
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                  onPressed: () => context.push('/tank3d-fullscreen'),
                ),
              ],
            ),
          ),
          // 3D Canvas
          Expanded(
            child: Boiler3dViewer(
              state: _state,
              onStateChanged: (s) => setState(() => _state = s),
            ),
          ),
          // Controls
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSliderRow(
            icon: Icons.water_drop_outlined,
            iconColor: const Color(0xFF4fc3f7),
            label: 'Nível',
            value: _state.waterLevel,
            onChanged: (v) =>
                setState(() => _state = _state.copyWith(waterLevel: v)),
          ),
          _buildSliderRow(
            icon: Icons.local_fire_department_outlined,
            iconColor: const Color(0xFFff9800),
            label: 'Chama',
            value: _state.flameIntensity,
            onChanged: (v) => setState(() =>
                _state = _state.copyWith(flameIntensity: v, flameOn: v > 0.02)),
          ),
          _buildSliderRow(
            icon: Icons.air,
            iconColor: const Color(0xFF4dd0e1),
            label: 'FD Fan',
            value: _state.forcedDraftFanSpeed,
            onChanged: (v) => setState(
                () => _state = _state.copyWith(forcedDraftFanSpeed: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 5),
          SizedBox(
            width: 40,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: iconColor.withOpacity(0.7),
                inactiveTrackColor: const Color(0xFF1e3a5f),
                thumbColor: iconColor,
                overlayColor: iconColor.withOpacity(0.15),
              ),
              child: Slider(value: value, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: iconColor, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
