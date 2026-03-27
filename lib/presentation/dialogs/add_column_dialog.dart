import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Returns (colName, byteSize, typeStr, defaultHex) or null.
class AddColumnDialog extends StatefulWidget {
  const AddColumnDialog({super.key});

  static Future<(String, int, String, String)?> show(BuildContext context) =>
      showDialog<(String, int, String, String)>(
          context: context, builder: (_) => const AddColumnDialog());

  @override
  State<AddColumnDialog> createState() => _AddColumnDialogState();
}

class _AddColumnDialogState extends State<AddColumnDialog> {
  final _nameCtrl     = TextEditingController();
  final _byteSizeCtrl = TextEditingController(text: '4');
  final _defaultCtrl  = TextEditingController(text: '00000000');
  String _typeStr     = 'FLOAT';

  static const _types = [
    'FLOAT', 'UNSIGNED', 'INTEGER', 'PACKED_ASCII', 'DATE', 'ENUM00',
    'BIT_ENUM02',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _byteSizeCtrl.dispose();
    _defaultCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add Variable (Column)'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Column name',
                hintText: 'e.g. my_variable',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _typeStr,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: _types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t,
                          style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (v) => setState(() => _typeStr = v ?? _typeStr),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _byteSizeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Bytes'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _defaultCtrl,
              decoration: const InputDecoration(
                labelText: 'Default hex value',
                hintText: '00000000',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: const Text(
                'FLOAT=4 bytes · UNSIGNED=1-4 · PACKED_ASCII=6-32\n'
                'Default value must be a hex string (no spaces)',
                style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
            onPressed: _submit,
          ),
        ],
      );

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final byteSize = int.tryParse(_byteSizeCtrl.text) ?? 4;
    final defaultHex = _defaultCtrl.text.trim().toUpperCase();
    Navigator.pop(context, (name, byteSize, _typeStr, defaultHex));
  }
}
