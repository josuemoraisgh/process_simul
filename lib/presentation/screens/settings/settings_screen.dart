import 'dart:io';
import 'package:file_picker/file_picker.dart';
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
  late TextEditingController _tcpHostCtrl;
  late TextEditingController _tcpPortCtrl;
  late TextEditingController _hartSrvPortCtrl;
  late TextEditingController _modbusPortCtrl;

  String _selectedPort = 'COM1';
  List<String> _availablePorts = [];
  bool _loadingPorts = false;
  bool _importing = false;
  String? _importResult;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _selectedPort    = s.hartSerialPort;
    _tcpHostCtrl     = TextEditingController(text: s.hartTcpHost);
    _tcpPortCtrl     = TextEditingController(text: s.hartTcpPort.toString());
    _hartSrvPortCtrl = TextEditingController(text: s.hartServerPort.toString());
    _modbusPortCtrl  = TextEditingController(text: s.modbusPort.toString());
    _refreshPorts();
  }

  @override
  void dispose() {
    _tcpHostCtrl.dispose();
    _tcpPortCtrl.dispose();
    _hartSrvPortCtrl.dispose();
    _modbusPortCtrl.dispose();
    super.dispose();
  }

  // ── COM port enumeration ──────────────────────────────────────────────────
  Future<void> _refreshPorts() async {
    if (!mounted) return;
    setState(() => _loadingPorts = true);
    final ports = await _enumeratePorts();
    if (!mounted) return;
    setState(() {
      _availablePorts = ports;
      _loadingPorts = false;
      if (ports.isNotEmpty && !ports.contains(_selectedPort)) {
        _selectedPort = ports.first;
      }
      if (ports.isEmpty) {
        _availablePorts = ['COM1'];
        if (!_availablePorts.contains(_selectedPort)) _selectedPort = 'COM1';
      }
    });
  }

  Future<List<String>> _enumeratePorts() async {
    if (!Platform.isWindows) return [];
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        '[System.IO.Ports.SerialPort]::GetPortNames() -join ","',
      ]);
      final out = result.stdout.toString().trim();
      if (out.isEmpty) return _fallbackPorts();
      final ports = out.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      ports.sort();
      return ports;
    } catch (_) {
      return _fallbackPorts();
    }
  }

  List<String> _fallbackPorts() {
    final ports = <String>[];
    for (int i = 1; i <= 20; i++) ports.add('COM$i');
    // Add common virtual com0com ports
    for (int i = 0; i <= 3; i++) {
      ports.add('CNCA$i');
      ports.add('CNCB$i');
    }
    return ports;
  }

  // ── Import from .db ──────────────────────────────────────────────────────
  Future<void> _importDb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      dialogTitle: 'Select SQLite database file',
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;

    setState(() { _importing = true; _importResult = null; });
    try {
      final repo = ref.read(dbRepositoryProvider);
      final count = await repo.importFromDb(path);
      // Reload both tables
      await ref.read(hartTableProvider.notifier).load();
      await ref.read(modbusTableProvider.notifier).load();
      if (!mounted) return;
      setState(() => _importResult = 'Imported $count rows from ${_baseName(path)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _importResult = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

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
              // ── HART Server ───────────────────────────────────────────────
              const _SectionTitle(icon: Icons.developer_board, label: 'HART Server'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                _LabelRow(
                  label: 'Connection mode',
                  child: SegmentedButton<CommMode>(
                    segments: const [
                      ButtonSegment(value: CommMode.tcp,
                          label: Text('TCP / IP'), icon: Icon(Icons.wifi, size: 14)),
                      ButtonSegment(value: CommMode.serial,
                          label: Text('Serial'),   icon: Icon(Icons.cable, size: 14)),
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
                    child: _SmallField(ctrl: _tcpHostCtrl, hint: '127.0.0.1'),
                  ),
                  const SizedBox(height: 8),
                  _LabelRow(
                    label: 'TCP port (client target)',
                    child: _SmallField(ctrl: _tcpPortCtrl, hint: '5094', numeric: true),
                  ),
                ] else ...[
                  _LabelRow(
                    label: 'Serial port',
                    child: Row(children: [
                      Expanded(
                        child: _PortDropdown(
                          value: _availablePorts.contains(_selectedPort)
                              ? _selectedPort
                              : (_availablePorts.isNotEmpty ? _availablePorts.first : null),
                          items: _availablePorts,
                          loading: _loadingPorts,
                          onChanged: (v) { if (v != null) setState(() => _selectedPort = v); },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh ports',
                        icon: _loadingPorts
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 18),
                        onPressed: _loadingPorts ? null : _refreshPorts,
                        color: AppColors.primaryLight,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Lists available COM and CNCA/CNCB (com0com) ports.\nBaud: 1200, 8N1 (HART standard) — desktop only.',
                    style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                  ),
                ],
                const Divider(),
                _LabelRow(
                  label: 'HART server listen port',
                  child: _SmallField(ctrl: _hartSrvPortCtrl, hint: '5094', numeric: true),
                ),
              ]),

              const SizedBox(height: 24),
              // ── Modbus TCP ────────────────────────────────────────────────
              const _SectionTitle(icon: Icons.settings_ethernet, label: 'Modbus TCP'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                _LabelRow(
                  label: 'Modbus TCP listen port',
                  child: _SmallField(ctrl: _modbusPortCtrl, hint: '502', numeric: true),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Port 502 requires admin/root on most systems.\n'
                  'Use 5020 or higher for non-privileged mode.',
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                ),
              ]),

              const SizedBox(height: 24),
              // ── Import ────────────────────────────────────────────────────
              const _SectionTitle(icon: Icons.upload_file, label: 'Import Database'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                const Text(
                  'Select a SQLite .db file with the same schema (hart_meta, hart_data, modbus_data) '
                  'to replace all current table data.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  ElevatedButton.icon(
                    icon: _importing
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file, size: 16),
                    label: Text(_importing ? 'Importing…' : 'Import from .db file'),
                    onPressed: _importing ? null : _importDb,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ]),
                if (_importResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _importResult!.startsWith('Import failed')
                          ? AppColors.error.withValues(alpha: 0.12)
                          : AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _importResult!.startsWith('Import failed')
                            ? AppColors.error.withValues(alpha: 0.4)
                            : AppColors.success.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        _importResult!.startsWith('Import failed')
                            ? Icons.error_outline : Icons.check_circle_outline,
                        size: 14,
                        color: _importResult!.startsWith('Import failed')
                            ? AppColors.error : AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_importResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _importResult!.startsWith('Import failed')
                                  ? AppColors.error : AppColors.success,
                            )),
                      ),
                    ]),
                  ),
                ],
              ]),

              const SizedBox(height: 24),
              // ── About ─────────────────────────────────────────────────────
              const _SectionTitle(icon: Icons.info_outline, label: 'About'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                const _InfoRow(label: 'Version',  value: '1.0.0'),
                const Divider(),
                const _InfoRow(label: 'Protocol', value: 'HART 5 · Modbus TCP'),
                const Divider(),
                const _InfoRow(label: 'Devices',  value: '11 HART field transmitters'),
                const Divider(),
                const _InfoRow(label: 'Platform', value: 'Windows & Android'),
              ]),

              const SizedBox(height: 32),
              // ── Save ──────────────────────────────────────────────────────
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
      hartSerialPort: _selectedPort,
      hartTcpHost:    _tcpHostCtrl.text.trim(),
      hartTcpPort:    int.tryParse(_tcpPortCtrl.text) ?? 5094,
      hartServerPort: int.tryParse(_hartSrvPortCtrl.text) ?? 5094,
      modbusPort:     int.tryParse(_modbusPortCtrl.text) ?? 502,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 2)),
    );
  }
}

// ── Port dropdown ─────────────────────────────────────────────────────────────
class _PortDropdown extends StatelessWidget {
  final String?         value;
  final List<String>    items;
  final bool            loading;
  final ValueChanged<String?> onChanged;
  const _PortDropdown({this.value, required this.items, required this.loading,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const LinearProgressIndicator(minHeight: 32);
    }
    return InputDecorator(
      decoration: const InputDecoration(isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace',
            color: AppColors.textPrimary),
        items: items.map((p) => DropdownMenuItem(value: p,
            child: Text(p, style: const TextStyle(
                fontSize: 13, fontFamily: 'monospace')))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: AppColors.primaryLight),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary, letterSpacing: 0.3)),
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
  Widget build(BuildContext context) => Row(children: [
        Expanded(flex: 3,
            child: Text(label, style: const TextStyle(fontSize: 13,
                color: AppColors.textSecondary))),
        Expanded(flex: 4, child: child),
      ]);
}

class _SmallField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final bool numeric;
  const _SmallField({required this.ctrl, required this.hint, this.numeric = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace',
            color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
          Expanded(child: Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary,
              fontWeight: FontWeight.w500)),
        ]),
      );
}
