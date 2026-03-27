import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../application/providers/app_providers.dart';
import '../../../domain/enums/db_model.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _serialPortCtrl;
  late TextEditingController _tcpHostCtrl;
  late TextEditingController _tcpPortCtrl;
  late TextEditingController _hartSrvPortCtrl;
  late TextEditingController _modbusPortCtrl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _serialPortCtrl  = TextEditingController(text: s.hartSerialPort);
    _tcpHostCtrl     = TextEditingController(text: s.hartTcpHost);
    _tcpPortCtrl     = TextEditingController(text: s.hartTcpPort.toString());
    _hartSrvPortCtrl = TextEditingController(text: s.hartServerPort.toString());
    _modbusPortCtrl  = TextEditingController(text: s.modbusPort.toString());
  }

  @override
  void dispose() {
    _serialPortCtrl.dispose();
    _tcpHostCtrl.dispose();
    _tcpPortCtrl.dispose();
    _hartSrvPortCtrl.dispose();
    _modbusPortCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                  icon: Icons.developer_board, label: 'HART Server'),
              const SizedBox(height: 12),

              // ── HART mode ─────────────────────────────────────────────
              _SettingsCard(children: [
                _LabelRow(
                  label: 'Connection mode',
                  child: SegmentedButton<CommMode>(
                    segments: const [
                      ButtonSegment(value: CommMode.tcp,
                          label: Text('TCP / IP'),
                          icon: Icon(Icons.wifi, size: 14)),
                      ButtonSegment(value: CommMode.serial,
                          label: Text('Serial'),
                          icon: Icon(Icons.cable, size: 14)),
                    ],
                    selected: {settings.hartMode},
                    onSelectionChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(hartMode: v.first)),
                    style: ButtonStyle(
                      textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
                const Divider(),
                if (settings.hartMode == CommMode.tcp) ...[
                  _LabelRow(
                    label: 'TCP host (client target)',
                    child: _SmallField(ctrl: _tcpHostCtrl,
                        hint: '127.0.0.1'),
                  ),
                  const SizedBox(height: 8),
                  _LabelRow(
                    label: 'TCP port (client target)',
                    child: _SmallField(ctrl: _tcpPortCtrl,
                        hint: '5094', numeric: true),
                  ),
                ] else ...[
                  _LabelRow(
                    label: 'Serial port',
                    child: _SmallField(ctrl: _serialPortCtrl,
                        hint: 'COM1 / /dev/ttyS0'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Note: Serial port is available on desktop only.\n'
                    'Baud: 1200, 8N1 (HART standard)',
                    style: TextStyle(fontSize: 11,
                        color: AppColors.textDisabled),
                  ),
                ],
                const Divider(),
                _LabelRow(
                  label: 'HART server listen port',
                  child: _SmallField(ctrl: _hartSrvPortCtrl,
                      hint: '5094', numeric: true),
                ),
              ]),

              const SizedBox(height: 24),
              const _SectionTitle(
                  icon: Icons.settings_ethernet, label: 'Modbus TCP'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                _LabelRow(
                  label: 'Modbus TCP listen port',
                  child: _SmallField(ctrl: _modbusPortCtrl,
                      hint: '502', numeric: true),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Port 502 requires admin/root on most systems.\n'
                  'Use 5020 or higher for non-privileged mode.',
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                ),
              ]),

              const SizedBox(height: 24),
              const _SectionTitle(
                  icon: Icons.info_outline, label: 'About'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                const _InfoRow(label: 'Version',   value: '1.0.0'),
                const Divider(),
                const _InfoRow(label: 'Protocol',  value: 'HART 5 · Modbus TCP'),
                const Divider(),
                const _InfoRow(label: 'Devices',   value: '11 HART field transmitters'),
                const Divider(),
                const _InfoRow(label: 'Platform',  value: 'Windows & Android'),
              ]),

              const SizedBox(height: 32),

              // ── Save button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save Settings'),
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    final s = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).save(s.copyWith(
      hartSerialPort: _serialPortCtrl.text.trim(),
      hartTcpHost:    _tcpHostCtrl.text.trim(),
      hartTcpPort:    int.tryParse(_tcpPortCtrl.text) ?? 5094,
      hartServerPort: int.tryParse(_hartSrvPortCtrl.text) ?? 5094,
      modbusPort:     int.tryParse(_modbusPortCtrl.text) ?? 502,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppColors.primaryLight),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.3,
            )),
      ]);
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

class _LabelRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(fontSize: 13,
                    color: AppColors.textSecondary)),
          ),
          Expanded(flex: 4, child: child),
        ],
      );
}

class _SmallField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final bool numeric;
  const _SmallField({required this.ctrl, required this.hint,
      this.numeric = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace',
            color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13,
                    color: AppColors.textSecondary)),
          ),
          Text(value,
              style: const TextStyle(fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}
