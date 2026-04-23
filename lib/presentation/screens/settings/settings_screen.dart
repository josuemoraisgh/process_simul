import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../application/providers/app_providers.dart';
import '../../../domain/enums/db_model.dart';
import '../../dialogs/custom_type_dialogs.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _tcpHostCtrl;
  late TextEditingController _hartSrvPortCtrl;
  late TextEditingController _modbusPortCtrl;
  late TextEditingController _tfStepMsCtrl;

  String _selectedPort = 'COM1';
  List<String> _availablePorts = [];
  bool _loadingPorts = false;
  bool _importing = false;
  final bool _exporting = false;
  String? _importResult;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _selectedPort = s.hartSerialPort;
    _tcpHostCtrl = TextEditingController(text: s.hartTcpHost);
    _hartSrvPortCtrl = TextEditingController(text: s.hartServerPort.toString());
    _modbusPortCtrl = TextEditingController(text: s.modbusPort.toString());
    _tfStepMsCtrl = TextEditingController(text: s.tfStepMs.toString());
    _refreshPorts();
  }

  @override
  void dispose() {
    _tcpHostCtrl.dispose();
    _hartSrvPortCtrl.dispose();
    _modbusPortCtrl.dispose();
    _tfStepMsCtrl.dispose();
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
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '[System.IO.Ports.SerialPort]::GetPortNames() -join ","',
      ]);
      final out = result.stdout.toString().trim();
      if (out.isEmpty) return _fallbackPorts();
      final ports = out
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      ports.sort();
      return ports;
    } catch (_) {
      return _fallbackPorts();
    }
  }

  List<String> _fallbackPorts() {
    final ports = <String>[];
    for (int i = 1; i <= 20; i++) {
      ports.add('COM$i');
    }
    // Add common virtual com0com ports
    for (int i = 0; i <= 3; i++) {
      ports.add('CNCA$i');
      ports.add('CNCB$i');
    }
    return ports;
  }

  // ── Import from XLS ──────────────────────────────────────────────────────
  Future<void> _importXls() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      dialogTitle: 'Selecione o arquivo XLSX para importar',
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;

    setState(() {
      _importing = true;
      _importResult = null;
    });
    try {
      final repo = ref.read(dbRepositoryProvider);
      final count = await repo.importFromXls(path);
      await ref.read(hartTableProvider.notifier).load();
      await ref.read(modbusTableProvider.notifier).load();
      ref.read(customTypesProvider.notifier).load();
      if (!mounted) return;
      setState(() =>
          _importResult = 'Importado $count linhas de ${_baseName(path)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _importResult = 'Falha na importação: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Export to XLS ──────────────────────────────────────────────────────────
  Future<void> _exportXls() async {
    final outPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar XLSX',
      fileName: 'process_simul_export.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (outPath == null) return;
    try {
      final repo = ref.read(dbRepositoryProvider);
      await repo.exportToXls(outPath);
      if (!mounted) return;
      setState(() => _importResult = 'Exportado para ${_baseName(outPath)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _importResult = 'Falha na exportação: $e');
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
              // ── Transfer Function ──────────────────────────────────────
              const _SectionTitle(
                  icon: Icons.functions, label: 'Transfer Function (TF)'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                _LabelRow(
                  label: 'Intervalo de iteração (ms)',
                  child: _SmallField(
                      ctrl: _tfStepMsCtrl, hint: '50', numeric: true),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Período do timer de simulação das células \$tFunc.\n'
                  'Valores menores = mais fluido, porém mais uso de CPU.\n'
                  'Recomendado: 20–200 ms.',
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                ),
              ]),

              const SizedBox(height: 24),
              // ── HART Server ───────────────────────────────────────────────
              const _SectionTitle(
                  icon: Icons.developer_board, label: 'HART Server'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                _LabelRow(
                  label: 'Connection mode',
                  child: SegmentedButton<CommMode>(
                    segments: const [
                      ButtonSegment(
                          value: CommMode.tcp,
                          label: Text('TCP / IP'),
                          icon: Icon(Icons.wifi, size: 14)),
                      ButtonSegment(
                          value: CommMode.serial,
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
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                if (settings.hartMode == CommMode.tcp) ...[
                  _LabelRow(
                    label: 'TCP host (client target)',
                    child: _SmallField(ctrl: _tcpHostCtrl, hint: '127.0.0.1'),
                  ),
                  const SizedBox(height: 8),
                  _LabelRow(
                    label: 'HART server listen port',
                    child: _SmallField(
                        ctrl: _hartSrvPortCtrl, hint: '5094', numeric: true),
                  ),
                ] else ...[
                  _LabelRow(
                    label: 'Serial port',
                    child: Row(children: [
                      Expanded(
                        child: _PortDropdown(
                          value: _availablePorts.contains(_selectedPort)
                              ? _selectedPort
                              : (_availablePorts.isNotEmpty
                                  ? _availablePorts.first
                                  : null),
                          items: _availablePorts,
                          loading: _loadingPorts,
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedPort = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Refresh ports',
                        icon: _loadingPorts
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh, size: 18),
                        onPressed: _loadingPorts ? null : _refreshPorts,
                        color: AppColors.primaryLight,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Lists available COM and CNCA/CNCB (com0com) ports.\nBaud: 1200, 8O1 (HART standard) — desktop only.',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textDisabled),
                  ),
                ],
              ]),

              const SizedBox(height: 24),
              // ── Modbus TCP ────────────────────────────────────────────────
              const _SectionTitle(
                  icon: Icons.settings_ethernet, label: 'Modbus TCP'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                _LabelRow(
                  label: 'Modbus TCP listen port',
                  child: _SmallField(
                      ctrl: _modbusPortCtrl, hint: '502', numeric: true),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Port 502 requires admin/root on most systems.\n'
                  'Use 5020 or higher for non-privileged mode.',
                  style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
                ),
              ]),

              const SizedBox(height: 24),
              // ── Import / Export ────────────────────────────────────────────
              const _SectionTitle(
                  icon: Icons.swap_vert, label: 'Importar / Exportar XLS'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                const Text(
                  'Importa ou exporta os dados HART, Modbus, ENUM e BIT_ENUM '
                  'através de um arquivo XLSX.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  ElevatedButton.icon(
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file, size: 16),
                    label:
                        Text(_importing ? 'Importando…' : 'Importar de .xlsx'),
                    onPressed: _importing ? null : _importXls,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Exportar para .xlsx'),
                    onPressed: _exporting ? null : _exportXls,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ]),
                if (_importResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _importResult!.startsWith('Falha')
                          ? AppColors.error.withValues(alpha: 0.12)
                          : AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _importResult!.startsWith('Falha')
                            ? AppColors.error.withValues(alpha: 0.4)
                            : AppColors.success.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        _importResult!.startsWith('Falha')
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 14,
                        color: _importResult!.startsWith('Falha')
                            ? AppColors.error
                            : AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_importResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _importResult!.startsWith('Falha')
                                  ? AppColors.error
                                  : AppColors.success,
                            )),
                      ),
                    ]),
                  ),
                ],
              ]),

              const SizedBox(height: 24),
              // ── Custom Types ──────────────────────────────────────────────
              const _SectionTitle(
                  icon: Icons.category,
                  label: 'Custom Types (ENUM / BIT_ENUM / Commands)'),
              const SizedBox(height: 12),
              _CustomTypesSection(),

              const SizedBox(height: 24),
              // ── About ─────────────────────────────────────────────────────
              const _SectionTitle(icon: Icons.info_outline, label: 'About'),
              const SizedBox(height: 12),

              const _SettingsCard(children: [
                _InfoRow(label: 'Version', value: '1.0.0'),
                Divider(),
                _InfoRow(label: 'Protocol', value: 'HART 5 · Modbus TCP'),
                Divider(),
                _InfoRow(label: 'Author', value: 'Josué Morais'),
                Divider(),
                _InfoRow(label: 'Platform', value: 'Windows & Android'),
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
          hartTcpHost: _tcpHostCtrl.text.trim(),
          hartServerPort: int.tryParse(_hartSrvPortCtrl.text) ?? 5094,
          modbusPort: int.tryParse(_modbusPortCtrl.text) ?? 502,
          tfStepMs: (int.tryParse(_tfStepMsCtrl.text) ?? 50).clamp(10, 5000),
        ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Settings saved'), duration: Duration(seconds: 2)),
    );
  }
}

// ── Port dropdown ─────────────────────────────────────────────────────────────
class _PortDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final bool loading;
  final ValueChanged<String?> onChanged;
  const _PortDropdown(
      {this.value,
      required this.items,
      required this.loading,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const LinearProgressIndicator(minHeight: 32);
    }
    return InputDecorator(
      decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: AppColors.textPrimary),
        items: items
            .map((p) => DropdownMenuItem(
                value: p,
                child: Text(p,
                    style: const TextStyle(
                        fontSize: 13, fontFamily: 'monospace'))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
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
                letterSpacing: 0.3)),
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
        Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))),
        Expanded(flex: 4, child: child),
      ]);
}

class _SmallField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final bool numeric;
  const _SmallField(
      {required this.ctrl, required this.hint, this.numeric = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
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
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

// ── Custom Types section (ENUM / BIT_ENUM / COMMANDS CRUD) ───────────────────
class _CustomTypesSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CustomTypesSection> createState() =>
      _CustomTypesSectionState();
}

class _CustomTypesSectionState extends ConsumerState<_CustomTypesSection> {
  bool _showEnums = false;
  bool _showBitEnums = false;
  bool _showCommands = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customTypesProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctState = ref.watch(customTypesProvider);
    if (ctState.loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── ENUM groups ──────────────────────────────────────────────────
        _SettingsCard(children: [
          InkWell(
            onTap: () => setState(() => _showEnums = !_showEnums),
            child: Row(children: [
              Icon(_showEnums ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              const Icon(Icons.list_alt,
                  size: 16, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              const Text('ENUMs',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Text('(${ctState.enums.length} grupos)',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textDisabled)),
              const Spacer(),
              if (_showEnums)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label:
                      const Text('Novo grupo', style: TextStyle(fontSize: 12)),
                  onPressed: () => _addEnumGroup(context),
                ),
            ]),
          ),
          if (_showEnums) ...[
            const Divider(),
            if (ctState.enums.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum grupo ENUM definido.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textDisabled)),
              )
            else
              ...ctState.enums.entries.map((group) => _EnumGroupTile(
                    enumIndex: group.key,
                    entries: group.value,
                    onAdd: () => _addEnumEntry(context, group.key),
                    onEdit: (key) => _editEnumEntry(
                        context, group.key, key, group.value[key]!),
                    onRemoveEntry: (key) => _removeEnumEntry(group.key, key),
                    onRemoveGroup: () => _removeEnumGroup(context, group.key),
                  )),
          ],
        ]),

        const SizedBox(height: 16),

        // ── BIT_ENUM groups ──────────────────────────────────────────────
        _SettingsCard(children: [
          InkWell(
            onTap: () => setState(() => _showBitEnums = !_showBitEnums),
            child: Row(children: [
              Icon(_showBitEnums ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              const Icon(Icons.memory, size: 16, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              const Text('BIT_ENUMs',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Text('(${ctState.bitEnums.length} grupos)',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textDisabled)),
              const Spacer(),
              if (_showBitEnums)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label:
                      const Text('Novo grupo', style: TextStyle(fontSize: 12)),
                  onPressed: () => _addBitEnumGroup(context),
                ),
            ]),
          ),
          if (_showBitEnums) ...[
            const Divider(),
            if (ctState.bitEnums.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum grupo BIT_ENUM definido.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textDisabled)),
              )
            else
              ...ctState.bitEnums.entries.map((group) => _BitEnumGroupTile(
                    bitEnumIndex: group.key,
                    entries: group.value,
                    onAdd: () => _addBitEnumEntry(context, group.key),
                    onEdit: (mask) => _editBitEnumEntry(
                        context, group.key, mask, group.value[mask]!),
                    onRemoveEntry: (mask) =>
                        _removeBitEnumEntry(group.key, mask),
                    onRemoveGroup: () =>
                        _removeBitEnumGroup(context, group.key),
                  )),
          ],
        ]),

        const SizedBox(height: 16),

        // ── COMMANDS ─────────────────────────────────────────────────────
        _SettingsCard(children: [
          InkWell(
            onTap: () => setState(() => _showCommands = !_showCommands),
            child: Row(children: [
              Icon(_showCommands ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              const Icon(Icons.terminal,
                  size: 16, color: AppColors.primaryLight),
              const SizedBox(width: 8),
              const Text('Commands',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 8),
              Text('(${ctState.commands.length} comandos)',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textDisabled)),
              const Spacer(),
              if (_showCommands)
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Novo cmd', style: TextStyle(fontSize: 12)),
                  onPressed: () => _addCommand(context),
                ),
            ]),
          ),
          if (_showCommands) ...[
            const Divider(),
            if (ctState.commands.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum comando definido.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textDisabled)),
              )
            else
              ...ctState.commands.entries.map((entry) => _CommandTile(
                    command: entry.key,
                    data: entry.value,
                    onEdit: () => _editCommand(context, entry.key, entry.value),
                    onRemove: () => _removeCommand(context, entry.key),
                  )),
          ],
        ]),
      ],
    );
  }

  // ── ENUM actions ──────────────────────────────────────────────────────────
  Future<void> _addEnumGroup(BuildContext ctx) async {
    final idx = await NewGroupDialog.show(ctx, 'ENUM');
    if (idx == null) return;
    ref.read(customTypesProvider.notifier).addEnumEntry(idx, '00', '(new)');
  }

  Future<void> _addEnumEntry(BuildContext ctx, int enumIndex) async {
    final result = await EditEnumEntryDialog.show(ctx);
    if (result == null) return;
    ref
        .read(customTypesProvider.notifier)
        .addEnumEntry(enumIndex, result.$1, result.$2);
  }

  Future<void> _editEnumEntry(
      BuildContext ctx, int enumIndex, String hexKey, String desc) async {
    final result =
        await EditEnumEntryDialog.show(ctx, hexKey: hexKey, description: desc);
    if (result == null) return;
    ref
        .read(customTypesProvider.notifier)
        .updateEnumEntry(enumIndex, result.$1, result.$2);
  }

  void _removeEnumEntry(int enumIndex, String hexKey) {
    ref.read(customTypesProvider.notifier).removeEnumEntry(enumIndex, hexKey);
  }

  Future<void> _removeEnumGroup(BuildContext ctx, int enumIndex) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Remover grupo'),
        content: Text('Remover todo o grupo ENUM$enumIndex?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(customTypesProvider.notifier).removeEnumGroup(enumIndex);
    }
  }

  // ── BIT_ENUM actions ──────────────────────────────────────────────────────
  Future<void> _addBitEnumGroup(BuildContext ctx) async {
    final idx = await NewGroupDialog.show(ctx, 'BIT_ENUM');
    if (idx == null) return;
    ref.read(customTypesProvider.notifier).addBitEnumEntry(idx, 0, '(new)');
  }

  Future<void> _addBitEnumEntry(BuildContext ctx, int bitEnumIndex) async {
    final result = await EditBitEnumEntryDialog.show(ctx);
    if (result == null) return;
    ref
        .read(customTypesProvider.notifier)
        .addBitEnumEntry(bitEnumIndex, result.$1, result.$2);
  }

  Future<void> _editBitEnumEntry(
      BuildContext ctx, int bitEnumIndex, int mask, String desc) async {
    final result =
        await EditBitEnumEntryDialog.show(ctx, mask: mask, description: desc);
    if (result == null) return;
    ref
        .read(customTypesProvider.notifier)
        .updateBitEnumEntry(bitEnumIndex, result.$1, result.$2);
  }

  void _removeBitEnumEntry(int bitEnumIndex, int mask) {
    ref
        .read(customTypesProvider.notifier)
        .removeBitEnumEntry(bitEnumIndex, mask);
  }

  Future<void> _removeBitEnumGroup(BuildContext ctx, int bitEnumIndex) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Remover grupo'),
        content: Text('Remover todo o grupo BIT_ENUM$bitEnumIndex?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(customTypesProvider.notifier).removeBitEnumGroup(bitEnumIndex);
    }
  }

  // ── COMMAND actions ───────────────────────────────────────────────────────
  Future<void> _addCommand(BuildContext ctx) async {
    final result = await EditCommandDialog.show(ctx);
    if (result == null) return;
    ref
        .read(customTypesProvider.notifier)
        .addCommand(result.$1, result.$2, result.$3, result.$4, result.$5);
  }

  Future<void> _editCommand(
      BuildContext ctx, String cmd, Map<String, dynamic> data) async {
    final result = await EditCommandDialog.show(ctx,
        command: cmd,
        description: data['description'] as String,
        req: (data['req'] as List).cast<String>(),
        resp: (data['resp'] as List).cast<String>(),
        write: (data['write'] as List).cast<String>());
    if (result == null) return;
    ref
        .read(customTypesProvider.notifier)
        .updateCommand(result.$1, result.$2, result.$3, result.$4, result.$5);
  }

  Future<void> _removeCommand(BuildContext ctx, String cmd) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Remover comando'),
        content: Text('Remover o comando 0x$cmd?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(customTypesProvider.notifier).removeCommand(cmd);
    }
  }
}

// ── ENUM group expandable tile ───────────────────────────────────────────────
class _EnumGroupTile extends StatelessWidget {
  final int enumIndex;
  final Map<String, String> entries;
  final VoidCallback onAdd;
  final void Function(String hexKey) onEdit;
  final void Function(String hexKey) onRemoveEntry;
  final VoidCallback onRemoveGroup;

  const _EnumGroupTile({
    required this.enumIndex,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onRemoveEntry,
    required this.onRemoveGroup,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      title: Row(children: [
        Text('ENUM${enumIndex.toString().padLeft(2, '0')}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: AppColors.textPrimary)),
        const SizedBox(width: 8),
        Text('(${entries.length} itens)',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
      ]),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'Inserir entrada',
            onPressed: onAdd,
            color: AppColors.primaryLight,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Remover grupo',
            onPressed: onRemoveGroup,
            color: AppColors.error,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      children: entries.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 60,
              child: Text(e.key,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.primaryLight)),
            ),
            Expanded(
              child: Text(e.value,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textPrimary)),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 14),
              onPressed: () => onEdit(e.key),
              visualDensity: VisualDensity.compact,
              color: AppColors.textSecondary,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: () => onRemoveEntry(e.key),
              visualDensity: VisualDensity.compact,
              color: AppColors.error,
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ── BIT_ENUM group expandable tile ───────────────────────────────────────────
class _BitEnumGroupTile extends StatelessWidget {
  final int bitEnumIndex;
  final Map<int, String> entries;
  final VoidCallback onAdd;
  final void Function(int mask) onEdit;
  final void Function(int mask) onRemoveEntry;
  final VoidCallback onRemoveGroup;

  const _BitEnumGroupTile({
    required this.bitEnumIndex,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
    required this.onRemoveEntry,
    required this.onRemoveGroup,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      title: Row(children: [
        Text('BIT_ENUM${bitEnumIndex.toString().padLeft(2, '0')}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: AppColors.textPrimary)),
        const SizedBox(width: 8),
        Text('(${entries.length} itens)',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
      ]),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'Inserir entrada',
            onPressed: onAdd,
            color: AppColors.primaryLight,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Remover grupo',
            onPressed: onRemoveGroup,
            color: AppColors.error,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      children: entries.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 60,
              child: Text('0x${e.key.toRadixString(16).toUpperCase()}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.primaryLight)),
            ),
            Expanded(
              child: Text(e.value,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textPrimary)),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 14),
              onPressed: () => onEdit(e.key),
              visualDensity: VisualDensity.compact,
              color: AppColors.textSecondary,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: () => onRemoveEntry(e.key),
              visualDensity: VisualDensity.compact,
              color: AppColors.error,
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ── HART command tile ────────────────────────────────────────────────────────
class _CommandTile extends StatelessWidget {
  final String command;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _CommandTile({
    required this.command,
    required this.data,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final desc = data['description'] as String? ?? '';
    final resp = (data['resp'] as List?)?.cast<String>() ?? [];
    final req = (data['req'] as List?)?.cast<String>() ?? [];
    final write = (data['write'] as List?)?.cast<String>() ?? [];

    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      title: Row(children: [
        Text('0x$command',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: AppColors.primaryLight)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(desc,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
        ),
      ]),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Editar comando',
            onPressed: onEdit,
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            tooltip: 'Remover comando',
            onPressed: onRemove,
            color: AppColors.error,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      children: [
        if (resp.isNotEmpty) _cmdFieldRow('resp', resp.join(', ')),
        if (req.isNotEmpty) _cmdFieldRow('req', req.join(', ')),
        if (write.isNotEmpty) _cmdFieldRow('write', write.join(', ')),
      ],
    );
  }

  Widget _cmdFieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 50,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary)),
        ),
      ]),
    );
  }
}
