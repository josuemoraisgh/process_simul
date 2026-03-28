import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../application/providers/app_providers.dart';
import '../../../application/notifiers/modbus_table_notifier.dart';
import '../../../infrastructure/hart/hart_type_converter.dart';

class ModbusTableScreen extends ConsumerStatefulWidget {
  const ModbusTableScreen({super.key});

  @override
  ConsumerState<ModbusTableScreen> createState() => _ModbusTableScreenState();
}

class _ModbusTableScreenState extends ConsumerState<ModbusTableScreen> {
  final _scrollCtrl = ScrollController();

  static const _cols = [
    'Name', 'Bytes', 'Type', 'MB Point', 'Address', 'Formula / Value'
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(modbusTableProvider.notifier).load());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ModbusTableState mbState = ref.watch(modbusTableProvider);
    final hart = ref.watch(hartTableProvider);
    final rows = mbState.data.entries.toList();

    if (mbState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (mbState.error != null) {
      return Center(child: Text('Error: ${mbState.error}',
          style: const TextStyle(color: AppColors.error)));
    }

    return Column(children: [
      // ── Toolbar ──────────────────────────────────────────────────────────
      _ModbusToolbar(
        onAdd:    () => _addVariable(context),
        onEdit:   () => _editVariable(context, rows),
        onRemove: () => _removeVariable(context, rows),
      ),
      // ── Header ──────────────────────────────────────────────────────────
      Container(
        height: 36,
        color: AppColors.cardDark,
        child: Row(
          children: [
            for (int i = 0; i < _cols.length; i++)
              _HeaderCell(
                label: _cols[i],
                flex: i == _cols.length - 1 ? 2 : 1,
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      // ── Body ─────────────────────────────────────────────────────────────
      Expanded(
        child: Scrollbar(
          controller: _scrollCtrl,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollCtrl,
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final name = rows[i].key;
              final (byteSize, typeStr, mbPoint, address, formula) =
                  rows[i].value;
              final isHr = mbPoint == 'hr';

              // Compute live value from HART table if formula is an expression
              String liveVal = formula;
              if (formula.startsWith('@')) {
                try {
                  final result = HartTransmitter.evaluateExpr(
                    formula.substring(1), hart.data);
                  liveVal = result.truncate().toString();
                } catch (_) {
                  liveVal = '?';
                }
              }

              return _ModbusRow(
                index: i,
                name: name,
                byteSize: byteSize,
                typeStr: typeStr,
                mbPoint: mbPoint,
                address: address,
                formula: formula,
                liveVal: liveVal,
                isWritable: isHr || mbPoint == 'co',
              );
            },
          ),
        ),
      ),
      // ── Footer ───────────────────────────────────────────────────────────
      Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.surfaceDark,
        child: Row(children: [
          const Icon(Icons.settings_ethernet, size: 12,
              color: AppColors.textDisabled),
          const SizedBox(width: 6),
          Text('${rows.length} variables  ·  '
              '${rows.where((e) => e.value.$3 == 'ir' || e.value.$3 == 'di').length} readable  ·  '
              '${rows.where((e) => e.value.$3 == 'hr' || e.value.$3 == 'co').length} writable',
              style: const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
        ]),
      ),
    ]);
  }

  Future<void> _addVariable(BuildContext ctx) async {
    final spec = await _AddModbusVariableDialog.show(ctx);
    if (spec == null) return;
    await ref.read(modbusTableProvider.notifier).addVariable(
      spec.$1, spec.$2, spec.$3, spec.$4, spec.$5, spec.$6,
    );
  }

  Future<void> _editVariable(BuildContext ctx,
      List<MapEntry<String, (int, String, String, String, String)>> rows) async {
    if (rows.isEmpty) return;
    String? selected = rows.first.key;
    // Step 1 – pick which variable to edit
    final pick = await showDialog<bool>(
      context: ctx,
      builder: (_) => _RemoveVariableDialog(
        items: rows.map((e) => e.key).toList(),
        selectedValue: selected,
        onChanged: (v) => selected = v,
        confirmLabel: 'Next',
        confirmColor: AppColors.accent,
      ),
    );
    if (pick != true || selected == null) return;
    if (!ctx.mounted) return;
    final oldName = selected!;
    final current = rows.firstWhere((e) => e.key == oldName).value;
    // Step 2 – open pre-filled edit dialog
    final spec = await _AddModbusVariableDialog.show(ctx, initial: (
      oldName,
      current.$1,
      current.$2,
      current.$3,
      current.$4,
      current.$5,
    ));
    if (spec == null) return;
    await ref.read(modbusTableProvider.notifier).editVariable(
      oldName, spec.$1, spec.$2, spec.$3, spec.$4, spec.$5, spec.$6,
    );
  }

  Future<void> _removeVariable(BuildContext ctx,
      List<MapEntry<String, (int, String, String, String, String)>> rows) async {
    if (rows.isEmpty) return;
    String? selected = rows.first.key;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => _RemoveVariableDialog(
        items: rows.map((e) => e.key).toList(),
        selectedValue: selected,
        onChanged: (v) => selected = v,
      ),
    );
    if (confirmed == true && selected != null) {
      await ref.read(modbusTableProvider.notifier).removeVariable(selected!);
    }
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────
class _ModbusToolbar extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  const _ModbusToolbar(
      {required this.onAdd, required this.onEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          border: Border(bottom: BorderSide(color: AppColors.borderDark)),
        ),
        child: Row(children: [
          const Text('Variable:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 6),
          _ToolBtn(icon: Icons.add,    label: 'Add',    color: AppColors.success, onTap: onAdd),
          const SizedBox(width: 4),
          _ToolBtn(icon: Icons.edit,   label: 'Edit',   color: AppColors.accent,  onTap: onEdit),
          const SizedBox(width: 4),
          _ToolBtn(icon: Icons.remove, label: 'Remove', color: AppColors.error,   onTap: onRemove),
          const Spacer(),
        ]),
      );
}

class _ToolBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;
  const _ToolBtn(
      {required this.icon, required this.label,
       required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      );
}

// ── Header / row widgets ──────────────────────────────────────────────────────
class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  const _HeaderCell({required this.label, this.flex = 1});

  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.borderDark)),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 0.4)),
        ),
      );
}

class _ModbusRow extends StatelessWidget {
  final int    index;
  final String name;
  final int    byteSize;
  final String typeStr;
  final String mbPoint;
  final String address;
  final String formula;
  final String liveVal;
  final bool   isWritable;

  const _ModbusRow({
    required this.index,    required this.name,     required this.byteSize,
    required this.typeStr,  required this.mbPoint,  required this.address,
    required this.formula,  required this.liveVal,  required this.isWritable,
  });

  @override
  Widget build(BuildContext context) {
    final bg = index.isOdd ? AppColors.surfaceDark : AppColors.backgroundDark;
    final pointColor = switch (mbPoint) {
      'ir' => AppColors.infoLight,
      'hr' => AppColors.accentLight,
      'di' => AppColors.infoLight,
      'co' => AppColors.warningLight,
      _    => AppColors.textSecondary,
    };

    return Container(
      height: 40,
      color: bg,
      child: Row(children: [
        // Name
        Expanded(child: _Cell(
          child: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w600,
                  fontSize: 12, color: AppColors.textPrimary)),
        )),
        // Bytes
        Expanded(child: _Cell(
          child: Text('$byteSize B',
              style: const TextStyle(fontSize: 12,
                  color: AppColors.textSecondary, fontFamily: 'monospace')),
        )),
        // Type
        Expanded(child: _Cell(
          child: Text(typeStr,
              style: const TextStyle(fontSize: 11,
                  color: AppColors.textSecondary)),
        )),
        // MB Point chip
        Expanded(child: _Cell(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: pointColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: pointColor.withValues(alpha: 0.5)),
            ),
            child: Text(mbPoint.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: pointColor)),
          ),
        )),
        // Address
        Expanded(child: _Cell(
          child: Text(address,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace',
                  color: AppColors.textSecondary)),
        )),
        // Formula / live value
        Expanded(flex: 2, child: _Cell(
          child: Tooltip(
            message: formula,
            child: Row(children: [
              if (formula.startsWith('@')) ...[
                const Icon(Icons.functions, size: 12, color: AppColors.info),
                const SizedBox(width: 4),
              ],
              Expanded(child: Text(
                formula.startsWith('@') ? liveVal : formula,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: formula.startsWith('@')
                      ? AppColors.infoLight
                      : AppColors.textPrimary,
                ),
              )),
            ]),
          ),
        )),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  final Widget child;
  const _Cell({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(
            right:  BorderSide(color: AppColors.borderDark, width: 0.5),
            bottom: BorderSide(color: AppColors.borderDark, width: 0.3),
          ),
        ),
        child: child,
      );
}

// ── Add / Edit variable dialog ────────────────────────────────────────────────
class _AddModbusVariableDialog extends StatefulWidget {
  /// When non-null, the dialog opens in edit mode with fields pre-filled.
  /// Tuple: (name, byteSize, typeStr, mbPoint, address, formula)
  final (String, int, String, String, String, String)? initial;
  const _AddModbusVariableDialog({this.initial});

  /// Returns (name, byteSize, typeStr, mbPoint, address, formula) or null.
  static Future<(String, int, String, String, String, String)?> show(
      BuildContext context,
      {(String, int, String, String, String, String)? initial}) =>
      showDialog<(String, int, String, String, String, String)>(
          context: context,
          builder: (_) => _AddModbusVariableDialog(initial: initial));

  @override
  State<_AddModbusVariableDialog> createState() =>
      _AddModbusVariableDialogState();
}

class _AddModbusVariableDialogState extends State<_AddModbusVariableDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bytesCtrl;
  late final TextEditingController _addrCtrl;
  late final TextEditingController _formulaCtrl;
  late String _typeStr;
  late String _mbPoint;
  bool get _isEdit => widget.initial != null;

  static const _types    = ['UNSIGNED', 'INTEGER', 'FLOAT', 'PACKED_ASCII'];
  static const _mbPoints = ['ir', 'hr', 'di', 'co'];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtrl    = TextEditingController(text: init?.$1 ?? '');
    _bytesCtrl   = TextEditingController(text: (init?.$2 ?? 4).toString());
    _typeStr     = init?.$3 ?? 'UNSIGNED';
    _mbPoint     = init?.$4 ?? 'ir';
    _addrCtrl    = TextEditingController(text: init?.$5 ?? '01');
    _formulaCtrl = TextEditingController(text: init?.$6 ?? '');
    if (!_types.contains(_typeStr)) _typeStr = 'UNSIGNED';
    if (!_mbPoints.contains(_mbPoint)) _mbPoint = 'ir';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bytesCtrl.dispose();
    _addrCtrl.dispose();
    _formulaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_isEdit ? 'Edit Modbus Variable' : 'Add Modbus Variable'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Variable name',
                prefixIcon: Icon(_isEdit ? Icons.edit : Icons.add, size: 16),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _typeStr,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: _types
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (v) => setState(() => _typeStr = v ?? _typeStr),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _bytesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Bytes'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _mbPoint,
                  decoration: const InputDecoration(labelText: 'MB Point'),
                  items: _mbPoints
                      .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.toUpperCase(),
                              style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (v) => setState(() => _mbPoint = v ?? _mbPoint),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _addrCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _formulaCtrl,
              decoration: const InputDecoration(
                labelText: 'Formula / default value',
                hintText: 'e.g. 00000000 or @int(65535*HART.TAG.col)',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: Icon(_isEdit ? Icons.save : Icons.add, size: 16),
            label: Text(_isEdit ? 'Save' : 'Add'),
            onPressed: _submit,
          ),
        ],
      );

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final byteSize = int.tryParse(_bytesCtrl.text) ?? 4;
    final addr     = _addrCtrl.text.trim();
    final formula  = _formulaCtrl.text.trim();
    Navigator.pop(context, (name, byteSize, _typeStr, _mbPoint, addr, formula));
  }
}

// ── Remove variable dialog ────────────────────────────────────────────────────
class _RemoveVariableDialog extends StatefulWidget {
  final List<String>          items;
  final String?               selectedValue;
  final ValueChanged<String?> onChanged;
  final String                confirmLabel;
  final Color                 confirmColor;

  const _RemoveVariableDialog({
    required this.items,
    required this.selectedValue,
    required this.onChanged,
    this.confirmLabel = 'Remove',
    this.confirmColor = AppColors.error,
  });

  @override
  State<_RemoveVariableDialog> createState() => _RemoveVariableDialogState();
}

class _RemoveVariableDialogState extends State<_RemoveVariableDialog> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedValue;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.confirmLabel == 'Remove'
            ? 'Remove Modbus Variable'
            : 'Select Variable to Edit'),
        content: DropdownButton<String>(
          value: _selected,
          isExpanded: true,
          items: widget.items
              .map((i) => DropdownMenuItem(value: i, child: Text(i)))
              .toList(),
          onChanged: (v) {
            setState(() => _selected = v);
            widget.onChanged(v);
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: widget.confirmColor),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

// Forward reference for expression evaluation in UI
class HartTransmitter {
  static double evaluateExpr(
      String expr, Map<String, Map<String, dynamic>> allDevices) {
    try {
      String resolved = expr;
      resolved = resolved.replaceAllMapped(
        RegExp(r'HART\.(\w+)\.(\w+)'),
        (m) {
          final device = m.group(1)!;
          final col    = m.group(2)!;
          final v      = allDevices[device]?[col];
          if (v == null) return '0';
          final hex = v.evaluatedHex?.isEmpty == false
              ? v.evaluatedHex
              : v.rawValue;
          if (v.typeStr?.toUpperCase().contains('FLOAT') == true) {
            return HartTypeConverter.hexToDouble(hex).toString();
          }
          return int.tryParse(hex, radix: 16)?.toString() ?? '0';
        },
      );
      resolved = resolved.replaceAllMapped(
        RegExp(r'int\(([^)]+)\)'),
        (m) => _eval(m.group(1)!).truncate().toString(),
      );
      return _eval(resolved);
    } catch (_) {
      return 0.0;
    }
  }

  static double _eval(String e) {
    e = e.trim();
    for (int i = e.length - 1; i > 0; i--) {
      if (e[i] == '+') return _eval(e.substring(0, i)) + _eval(e.substring(i + 1));
      if (e[i] == '-') return _eval(e.substring(0, i)) - _eval(e.substring(i + 1));
    }
    for (int i = e.length - 1; i > 0; i--) {
      if (e[i] == '*') return _eval(e.substring(0, i)) * _eval(e.substring(i + 1));
      if (e[i] == '/') {
        final r = _eval(e.substring(i + 1));
        return r == 0 ? 0 : _eval(e.substring(0, i)) / r;
      }
    }
    return double.tryParse(e) ?? 0.0;
  }
}
