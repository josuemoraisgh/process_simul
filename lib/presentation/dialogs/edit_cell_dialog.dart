import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/react_var.dart';
import '../../domain/enums/db_model.dart';
import '../../infrastructure/hart/hart_type_converter.dart';

/// Dialog for editing a ReactVar cell.
/// Supports three modes: plain value, @expression, $transfer-function.
class EditCellDialog extends StatefulWidget {
  final ReactVar variable;
  final bool showHuman;
  final Map<String, String>? enumMap;
  final Map<int, String>? bitEnumMap;

  const EditCellDialog({
    super.key,
    required this.variable,
    required this.showHuman,
    this.enumMap,
    this.bitEnumMap,
  });

  /// Shows the dialog and returns the new raw value, or null if cancelled.
  static Future<String?> show(BuildContext context, ReactVar v, bool showHuman,
      {Map<String, String>? enumMap, Map<int, String>? bitEnumMap}) {
    return showDialog<String>(
      context: context,
      builder: (_) => EditCellDialog(
        variable: v,
        showHuman: showHuman,
        enumMap: enumMap,
        bitEnumMap: bitEnumMap,
      ),
    );
  }

  @override
  State<EditCellDialog> createState() => _EditCellDialogState();
}

class _EditCellDialogState extends State<EditCellDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late TextEditingController _valueCtrl;
  late TextEditingController _funcCtrl;
  late TextEditingController _tfuncCtrl;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);

    final v = widget.variable;
    final hex = v.evaluatedHex.isEmpty ? v.rawValue : v.evaluatedHex;
    final humanVal = HartTypeConverter.hexToHuman(hex, v.typeStr,
        enumMap: widget.enumMap, bitEnumMap: widget.bitEnumMap);

    _valueCtrl = TextEditingController(
      text: widget.showHuman ? humanVal : hex,
    );
    _funcCtrl = TextEditingController(
      text: v.model == DbModel.func ? v.funcBody : '',
    );
    _tfuncCtrl = TextEditingController(
      text: v.model == DbModel.tFunc ? v.tFuncBody : '[1],[1,2,1],0.1,x',
    );

    // Pre-select the correct tab
    _tab.index = switch (v.model) {
      DbModel.func => 1,
      DbModel.tFunc => 2,
      _ => 0,
    };
  }

  @override
  void dispose() {
    _tab.dispose();
    _valueCtrl.dispose();
    _funcCtrl.dispose();
    _tfuncCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = widget.variable;
    String result;
    switch (_tab.index) {
      case 0: // plain value
        final text = _valueCtrl.text.trim();
        if (widget.showHuman) {
          result = HartTypeConverter.humanToHex(text, v.typeStr, v.byteSize,
              enumMap: widget.enumMap, bitEnumMap: widget.bitEnumMap);
        } else {
          result = text.toUpperCase();
        }
      case 1: // expression
        result = '@${_funcCtrl.text.trim()}';
      case 2: // transfer function
        result = r'$' + _tfuncCtrl.text.trim();
      default:
        result = v.rawValue;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.variable;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  _typeChip(v.model),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${v.rowName} › ${v.colName}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textPrimary),
                        ),
                        Text(
                          '${v.typeStr} · ${v.byteSize} byte${v.byteSize > 1 ? "s" : ""}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            // ── Tab bar ────────────────────────────────────────────────
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'Value'),
                Tab(text: '@ Function'),
                Tab(text: r'$ Transfer Fn'),
              ],
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            // ── Tab content ────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _ValueTab(
                      ctrl: _valueCtrl,
                      variable: v,
                      showHuman: widget.showHuman),
                  _FuncTab(ctrl: _funcCtrl),
                  _TFuncTab(ctrl: _tfuncCtrl),
                ],
              ),
            ),
            // ── Actions ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(DbModel model) {
    final (label, color) = switch (model) {
      DbModel.func => ('Function', AppColors.cellFunc),
      DbModel.tFunc => ('TF Sim', AppColors.cellTFunc),
      _ => ('Value', AppColors.cellValue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70)),
    );
  }
}

// ── Tab panels ────────────────────────────────────────────────────────────────

class _ValueTab extends StatelessWidget {
  final TextEditingController ctrl;
  final ReactVar variable;
  final bool showHuman;
  const _ValueTab(
      {required this.ctrl, required this.variable, required this.showHuman});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showHuman
                ? 'Enter engineering value (${variable.typeStr})'
                : 'Enter hex value (${variable.byteSize * 2} hex chars)',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: showHuman ? 'e.g. 50.0' : 'e.g. 42480000',
              prefixIcon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
          const Spacer(),
          if (!showHuman)
            const Text(
              'Tip: Hex values are big-endian. FLOAT = 4 bytes IEEE-754.',
              style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
            ),
        ],
      ),
    );
  }
}

class _FuncTab extends StatelessWidget {
  final TextEditingController ctrl;
  const _FuncTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expression evaluated at runtime.\nPrefix "@" is added automatically.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 4,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'e.g. HART.FIT100CA.percent_of_range * 100',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('References:',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLight)),
                SizedBox(height: 4),
                Text('HART.DEVICE.column   →  float value',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textSecondary)),
                Text('Operators: + - * / ( )',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textDisabled)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TFuncTab extends StatelessWidget {
  final TextEditingController ctrl;
  const _TFuncTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transfer function simulated in background (50 ms steps).\nPrefix "\$" is added automatically.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: r'[1],[1,2,1],0.1,x',
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Format:  \$[num],[den],delay,input',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryLight)),
                SizedBox(height: 6),
                Text('[num]   numerator coefficients',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                Text('[den]   denominator coefficients',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                Text('delay   pure time delay (seconds)',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                Text('input   expression or "x" for percent_of_range',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                SizedBox(height: 6),
                Text('Example: [1],[1,2,1],0.2,x  →  2nd-order, delay=0.2s',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppColors.textDisabled)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
