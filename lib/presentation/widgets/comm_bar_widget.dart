import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../application/providers/app_providers.dart';
import '../../application/notifiers/log_notifier.dart';
import '../../domain/enums/db_model.dart';

/// Top bar showing TF status, HART server status, Modbus status and Hex/Human toggle.
class CommBarWidget extends ConsumerWidget {
  const CommBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final hart = ref.watch(hartTableProvider);
    final settings = ref.watch(settingsProvider);
    final tfRunning = ref.watch(tfRunningProvider);

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(bottom: BorderSide(color: AppColors.borderDark)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // ── Transfer Function ──────────────────────────────────────────
          _StatusDot(active: tfRunning),
          const SizedBox(width: 6),
          const Text('TF',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 4),
          Text(':${settings.tfStepMs}ms',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
          const SizedBox(width: 6),
          _SmallButton(
            label: tfRunning ? 'Stop' : 'Start',
            active: tfRunning,
            onTap: () => _toggleTf(ref),
          ),

          const _VSep(),

          // ── HART Server ───────────────────────────────────────────────
          _StatusDot(active: conn.hartServerRunning),
          const SizedBox(width: 6),
          const Text('HART',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 6),
          _SegmentedToggle(
            options: const ['TCP', 'Serial'],
            selected: settings.hartMode == CommMode.tcp ? 0 : 1,
            onChanged: (i) {
              final mode = i == 0 ? CommMode.tcp : CommMode.serial;
              // Stop running server before switching mode
              if (conn.hartServerRunning) {
                ref.read(connectionProvider.notifier).stopHartServer();
                globalLog.info('HART', 'HART server stopped (mode change)');
              }
              ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(hartMode: mode));
              globalLog.info('HART',
                  'Communication mode changed to ${mode == CommMode.tcp ? 'TCP' : 'Serial'}');
            },
          ),
          const SizedBox(width: 6),
          _SmallButton(
            label: conn.hartServerRunning ? 'Stop' : 'Start',
            active: conn.hartServerRunning,
            onTap: () => _toggleHart(ref, conn.hartServerRunning,
                settings.hartServerPort, settings.hartMode),
          ),

          const _VSep(),

          // ── Modbus Server ─────────────────────────────────────────────
          _StatusDot(active: conn.modbusRunning),
          const SizedBox(width: 6),
          const Text('Modbus',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 4),
          Text(':${conn.modbusPort}',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
          const SizedBox(width: 6),
          _SmallButton(
            label: conn.modbusRunning ? 'Stop' : 'Start',
            active: conn.modbusRunning,
            onTap: () =>
                _toggleModbus(ref, conn.modbusRunning, settings.modbusPort),
          ),

          const _VSep(),

          // ── Error banners (if any) ────────────────────────────────────
          if (conn.hartError != null) ...[
            const Icon(Icons.error_outline, size: 14, color: AppColors.error),
            const SizedBox(width: 4),
            Text(conn.hartError!,
                style: const TextStyle(fontSize: 11, color: AppColors.error),
                overflow: TextOverflow.ellipsis),
            const SizedBox(width: 8),
          ],

          const Spacer(),

          // ── Human / Hex toggle ────────────────────────────────────────
          const Text('View:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(width: 6),
          _SegmentedToggle(
            options: const ['Human', 'Hex'],
            selected: hart.showHuman ? 0 : 1,
            onChanged: (i) =>
                ref.read(hartTableProvider.notifier).setShowHuman(i == 0),
          ),
        ],
      ),
    );
  }

  void _toggleTf(WidgetRef ref) {
    final simul = ref.read(simulTfProvider);
    final running = ref.read(tfRunningProvider);
    if (running) {
      simul.stop();
      globalLog.info('TF', 'Transfer Function stopped');
    } else {
      simul.start();
      globalLog.info(
          'TF', 'Transfer Function started (${simul.stepMs.toInt()}ms)');
    }
    ref.read(tfRunningProvider.notifier).state = !running;
  }

  Future<void> _toggleHart(
      WidgetRef ref, bool running, int port, CommMode mode) async {
    final notifier = ref.read(connectionProvider.notifier);
    if (running) {
      await notifier.stopHartServer();
      globalLog.info('HART', 'HART server stopped');
    } else if (mode == CommMode.serial) {
      final serialPort = ref.read(settingsProvider).hartSerialPort;
      final hartNotifier = ref.read(hartTableProvider.notifier);
      notifier.startHartSerial(
        serialPort,
        () => ref.read(hartTableProvider).data,
        (device, col, hex) => hartNotifier.setCellValue(device, col, hex),
      );
      globalLog.info('HART', 'HART Serial opening $serialPort');
    } else {
      final hartNotifier = ref.read(hartTableProvider.notifier);
      notifier.startHartServer(
        port,
        () => ref.read(hartTableProvider).data,
        (device, col, hex) => hartNotifier.setCellValue(device, col, hex),
      );
      globalLog.info('HART', 'HART TCP server started on port $port');
    }
  }

  void _toggleModbus(WidgetRef ref, bool running, int port) {
    final notifier = ref.read(connectionProvider.notifier);
    if (running) {
      notifier.stopModbus();
      globalLog.info('Modbus', 'Modbus server stopped');
    } else {
      notifier.startModbus(port);
      globalLog.info('Modbus', 'Modbus server started on port $port');
    }
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final bool active;
  const _StatusDot({required this.active});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.connected : AppColors.disconnected,
          boxShadow: active
              ? [
                  BoxShadow(
                      color: AppColors.connected.withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1)
                ]
              : null,
        ),
      );
}

class _SmallButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SmallButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? AppColors.error.withValues(alpha: 0.15)
                : AppColors.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? AppColors.error : AppColors.success,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.error : AppColors.successLight,
            ),
          ),
        ),
      );
}

class _VSep extends StatelessWidget {
  const _VSep();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: AppColors.borderDark,
      );
}

class _SegmentedToggle extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const _SegmentedToggle(
      {required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(options.length, (i) {
        final isSelected = i == selected;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.cardDark,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(i == 0 ? 5 : 0),
                right: Radius.circular(i == options.length - 1 ? 5 : 0),
              ),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: Text(
              options[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }),
    );
  }
}
