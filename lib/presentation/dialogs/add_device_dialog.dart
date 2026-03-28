import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Add or Edit an instrument (device).
/// Pass [initialName] to open in edit mode.
class AddDeviceDialog extends StatefulWidget {
  final String? initialName;
  const AddDeviceDialog({super.key, this.initialName});

  static Future<String?> show(BuildContext context, {String? initialName}) =>
      showDialog<String>(
          context: context,
          builder: (_) => AddDeviceDialog(initialName: initialName));

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  late final TextEditingController _ctrl;
  bool get _isEdit => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_isEdit ? 'Edit Instrument' : 'Add Instrument'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            _isEdit
                ? 'Change the device tag (name):'
                : 'Enter a unique device name (tag):',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'e.g. FIT200CA',
              prefixIcon: Icon(
                  _isEdit ? Icons.edit : Icons.developer_board, size: 16),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: Icon(_isEdit ? Icons.save : Icons.add, size: 16),
            label: Text(_isEdit ? 'Save' : 'Add'),
            onPressed: _submit,
          ),
        ],
      );

  void _submit() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, v);
  }
}
