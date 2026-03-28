import 'package:flutter/material.dart';

/// Dialog to add or edit an ENUM entry (hex_key → description).
class EditEnumEntryDialog extends StatefulWidget {
  final String? initialHexKey;
  final String? initialDescription;

  const EditEnumEntryDialog({
    super.key,
    this.initialHexKey,
    this.initialDescription,
  });

  static Future<(String, String)?> show(BuildContext context,
      {String? hexKey, String? description}) {
    return showDialog<(String, String)>(
      context: context,
      builder: (_) => EditEnumEntryDialog(
        initialHexKey: hexKey,
        initialDescription: description,
      ),
    );
  }

  @override
  State<EditEnumEntryDialog> createState() => _EditEnumEntryDialogState();
}

class _EditEnumEntryDialogState extends State<EditEnumEntryDialog> {
  late TextEditingController _keyCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.initialHexKey ?? '');
    _descCtrl = TextEditingController(text: widget.initialDescription ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialHexKey != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar Entrada ENUM' : 'Nova Entrada ENUM'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(
              labelText: 'Chave Hex (ex: 00, F0-F9)',
              hintText: '00',
            ),
            enabled: !isEdit,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descrição',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final key = _keyCtrl.text.trim();
            final desc = _descCtrl.text.trim();
            if (key.isEmpty || desc.isEmpty) return;
            Navigator.pop(context, (key, desc));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Dialog to add or edit a BIT_ENUM entry (hex_mask → description).
class EditBitEnumEntryDialog extends StatefulWidget {
  final int? initialMask;
  final String? initialDescription;

  const EditBitEnumEntryDialog({
    super.key,
    this.initialMask,
    this.initialDescription,
  });

  static Future<(int, String)?> show(BuildContext context,
      {int? mask, String? description}) {
    return showDialog<(int, String)>(
      context: context,
      builder: (_) => EditBitEnumEntryDialog(
        initialMask: mask,
        initialDescription: description,
      ),
    );
  }

  @override
  State<EditBitEnumEntryDialog> createState() => _EditBitEnumEntryDialogState();
}

class _EditBitEnumEntryDialogState extends State<EditBitEnumEntryDialog> {
  late TextEditingController _maskCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _maskCtrl = TextEditingController(
      text: widget.initialMask != null ? '${widget.initialMask}' : '',
    );
    _descCtrl = TextEditingController(text: widget.initialDescription ?? '');
  }

  @override
  void dispose() {
    _maskCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialMask != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar Entrada BIT_ENUM' : 'Nova Entrada BIT_ENUM'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _maskCtrl,
            decoration: const InputDecoration(
              labelText: 'Máscara (inteiro, ex: 1, 2, 4, 8 ...)',
              hintText: '1',
            ),
            keyboardType: TextInputType.number,
            enabled: !isEdit,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descrição',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final mask = int.tryParse(_maskCtrl.text.trim());
            final desc = _descCtrl.text.trim();
            if (mask == null || desc.isEmpty) return;
            Navigator.pop(context, (mask, desc));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Dialog to add a new ENUM or BIT_ENUM group (just the index).
class NewGroupDialog extends StatefulWidget {
  final String groupType; // 'ENUM' or 'BIT_ENUM'

  const NewGroupDialog({super.key, required this.groupType});

  static Future<int?> show(BuildContext context, String groupType) {
    return showDialog<int>(
      context: context,
      builder: (_) => NewGroupDialog(groupType: groupType),
    );
  }

  @override
  State<NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<NewGroupDialog> {
  late TextEditingController _indexCtrl;

  @override
  void initState() {
    super.initState();
    _indexCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _indexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Novo grupo ${widget.groupType}'),
      content: TextField(
        controller: _indexCtrl,
        decoration: InputDecoration(
          labelText: 'Índice do grupo (ex: 29)',
          hintText: '${widget.groupType == 'ENUM' ? 29 : 5}',
        ),
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final idx = int.tryParse(_indexCtrl.text.trim());
            if (idx == null || idx < 0) return;
            Navigator.pop(context, idx);
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}

/// Dialog to add or edit a HART command definition.
/// Returns (command, description, req, resp, write) or null.
class EditCommandDialog extends StatefulWidget {
  final String? initialCommand;
  final String? initialDescription;
  final List<String>? initialReq;
  final List<String>? initialResp;
  final List<String>? initialWrite;

  const EditCommandDialog({
    super.key,
    this.initialCommand,
    this.initialDescription,
    this.initialReq,
    this.initialResp,
    this.initialWrite,
  });

  static Future<(String, String, List<String>, List<String>, List<String>)?>
      show(
    BuildContext context, {
    String? command,
    String? description,
    List<String>? req,
    List<String>? resp,
    List<String>? write,
  }) {
    return showDialog<
        (String, String, List<String>, List<String>, List<String>)>(
      context: context,
      builder: (_) => EditCommandDialog(
        initialCommand: command,
        initialDescription: description,
        initialReq: req,
        initialResp: resp,
        initialWrite: write,
      ),
    );
  }

  @override
  State<EditCommandDialog> createState() => _EditCommandDialogState();
}

class _EditCommandDialogState extends State<EditCommandDialog> {
  late TextEditingController _cmdCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _reqCtrl;
  late TextEditingController _respCtrl;
  late TextEditingController _writeCtrl;

  @override
  void initState() {
    super.initState();
    _cmdCtrl = TextEditingController(text: widget.initialCommand ?? '');
    _descCtrl = TextEditingController(text: widget.initialDescription ?? '');
    _reqCtrl = TextEditingController(text: widget.initialReq?.join(', ') ?? '');
    _respCtrl =
        TextEditingController(text: widget.initialResp?.join(', ') ?? '');
    _writeCtrl =
        TextEditingController(text: widget.initialWrite?.join(', ') ?? '');
  }

  @override
  void dispose() {
    _cmdCtrl.dispose();
    _descCtrl.dispose();
    _reqCtrl.dispose();
    _respCtrl.dispose();
    _writeCtrl.dispose();
    super.dispose();
  }

  List<String> _parseList(String text) {
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialCommand != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar Comando HART' : 'Novo Comando HART'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _cmdCtrl,
              decoration: const InputDecoration(
                labelText: 'Comando (hex, ex: 00, 0B)',
                hintText: '00',
              ),
              enabled: !isEdit,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _respCtrl,
              decoration: const InputDecoration(
                labelText: 'Resp (campos separados por vírgula)',
                hintText: 'error_code, \$IDENTITY_BLOCK',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reqCtrl,
              decoration: const InputDecoration(
                labelText: 'Req (campos separados por vírgula)',
                hintText: 'polling_address',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _writeCtrl,
              decoration: const InputDecoration(
                labelText: 'Write (campos separados por vírgula)',
                hintText: 'polling_address',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final cmd = _cmdCtrl.text.trim().toUpperCase();
            final desc = _descCtrl.text.trim();
            if (cmd.isEmpty) return;
            Navigator.pop(context, (
              cmd,
              desc,
              _parseList(_reqCtrl.text),
              _parseList(_respCtrl.text),
              _parseList(_writeCtrl.text),
            ));
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
