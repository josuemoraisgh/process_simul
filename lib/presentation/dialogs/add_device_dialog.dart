import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key});

  static Future<String?> show(BuildContext context) =>
      showDialog<String>(
          context: context, builder: (_) => const AddDeviceDialog());

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add Instrument'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter a unique device name (tag):',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. FIT200CA',
              prefixIcon: Icon(Icons.developer_board, size: 16),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add'),
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
