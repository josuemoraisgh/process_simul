import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../application/providers/app_providers.dart';
import '../../../application/notifiers/hart_table_notifier.dart';
import '../../../domain/enums/db_model.dart';
import '../../dialogs/edit_cell_dialog.dart';
import '../../dialogs/add_device_dialog.dart';
import '../../dialogs/add_column_dialog.dart';

class HartTableScreen extends ConsumerWidget {
  const HartTableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hartTableProvider);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(state.error!),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: () => ref.read(hartTableProvider.notifier).load(),
              child: const Text('Retry')),
        ]),
      );
    }

    return Column(children: [
      _HartToolbar(state: state),
      Expanded(child: _HartTable(state: state)),
      _TableFooter(deviceCount: state.devices.length,
          colCount: state.visibleCols.length),
    ]);
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────
class _HartToolbar extends ConsumerWidget {
  final HartTableState state;
  const _HartToolbar({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        border: Border(bottom: BorderSide(color: AppColors.borderDark)),
      ),
      child: Row(children: [
        // ── Instrument (Row) buttons ──────────────────────────────────────
        const _ToolbarLabel('Instrument:'),
        const SizedBox(width: 6),
        _ToolBtn(
          icon: Icons.add,
          label: 'Add',
          color: AppColors.success,
          onTap: () => _addDevice(context, ref),
        ),
        const SizedBox(width: 4),
        _ToolBtn(
          icon: Icons.edit,
          label: 'Edit',
          color: AppColors.accent,
          onTap: () => _editDevice(context, ref, state),
        ),
        const SizedBox(width: 4),
        _ToolBtn(
          icon: Icons.remove,
          label: 'Remove',
          color: AppColors.error,
          onTap: () => _removeDevice(context, ref, state),
        ),
        _Sep(),
        // ── Variable (Column) buttons ─────────────────────────────────────
        const _ToolbarLabel('Variable:'),
        const SizedBox(width: 6),
        _ToolBtn(
          icon: Icons.add,
          label: 'Add',
          color: AppColors.success,
          onTap: () => _addColumn(context, ref),
        ),
        const SizedBox(width: 4),
        _ToolBtn(
          icon: Icons.edit,
          label: 'Edit',
          color: AppColors.accent,
          onTap: () => _editColumn(context, ref, state),
        ),
        const SizedBox(width: 4),
        _ToolBtn(
          icon: Icons.remove,
          label: 'Remove',
          color: AppColors.error,
          onTap: () => _removeColumn(context, ref, state),
        ),
        const Spacer(),
        Text(
          '${state.devices.length} instruments · ${state.visibleCols.length} variables',
          style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
        ),
      ]),
    );
  }

  Future<void> _addDevice(BuildContext ctx, WidgetRef ref) async {
    final name = await AddDeviceDialog.show(ctx);
    if (name != null && name.isNotEmpty) {
      await ref.read(hartTableProvider.notifier).addDevice(name.toUpperCase());
    }
  }

  Future<void> _editDevice(
      BuildContext ctx, WidgetRef ref, HartTableState state) async {
    if (state.devices.isEmpty) return;
    // Step 1 – pick which device to edit
    String? selected = state.devices.first;
    final pick = await showDialog<bool>(
      context: ctx,
      builder: (_) => _RemoveDialog(
        title: 'Edit Instrument – select',
        items: state.devices,
        selectedValue: selected,
        onChanged: (v) => selected = v,
        confirmLabel: 'Next',
        confirmColor: AppColors.accent,
      ),
    );
    if (pick != true || selected == null) return;
    if (!ctx.mounted) return;
    final oldName = selected!;
    // Step 2 – rename
    final newName = await AddDeviceDialog.show(ctx, initialName: oldName);
    if (newName == null || newName.trim().isEmpty || newName == oldName) return;
    await ref
        .read(hartTableProvider.notifier)
        .editDevice(oldName, newName.toUpperCase());
  }

  Future<void> _removeDevice(
      BuildContext ctx, WidgetRef ref, HartTableState state) async {
    if (state.devices.isEmpty) return;
    String? selected = state.devices.first;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => _RemoveDialog(
        title: 'Remove Instrument',
        items: state.devices,
        selectedValue: selected,
        onChanged: (v) => selected = v,
      ),
    );
    if (confirmed == true && selected != null) {
      await ref.read(hartTableProvider.notifier).removeDevice(selected!);
    }
  }

  Future<void> _addColumn(BuildContext ctx, WidgetRef ref) async {
    final spec = await AddColumnDialog.show(ctx);
    if (spec != null) {
      await ref
          .read(hartTableProvider.notifier)
          .addColumn(spec.$1, spec.$2, spec.$3, spec.$4);
    }
  }

  Future<void> _editColumn(
      BuildContext ctx, WidgetRef ref, HartTableState state) async {
    if (state.visibleCols.isEmpty) return;
    // Step 1 – pick which column to edit
    String? selected = state.visibleCols.first;
    final pick = await showDialog<bool>(
      context: ctx,
      builder: (_) => _RemoveDialog(
        title: 'Edit Variable – select',
        items: state.visibleCols,
        selectedValue: selected,
        onChanged: (v) => selected = v,
        confirmLabel: 'Next',
        confirmColor: AppColors.accent,
      ),
    );
    if (pick != true || selected == null) return;
    if (!ctx.mounted) return;
    final colName = selected!;
    // Step 2 – get current meta for the selected column
    final meta = state.data.values
        .expand((m) => m.entries)
        .where((e) => e.key == colName)
        .map((e) => e.value)
        .firstOrNull;
    final currentHex = meta?.rawValue ?? '00000000';
    final initial = (
      colName,
      meta?.byteSize ?? 4,
      meta?.typeStr ?? 'FLOAT',
      currentHex.startsWith('@') || currentHex.startsWith(r'$')
          ? '00000000'
          : currentHex,
    );
    final spec = await AddColumnDialog.show(ctx, initial: initial);
    if (spec == null) return;
    await ref
        .read(hartTableProvider.notifier)
        .editColumn(colName, spec.$1, spec.$2, spec.$3, spec.$4);
  }

  Future<void> _removeColumn(
      BuildContext ctx, WidgetRef ref, HartTableState state) async {
    if (state.visibleCols.isEmpty) return;
    String? selected = state.visibleCols.first;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => _RemoveDialog(
        title: 'Remove Variable',
        items: state.visibleCols,
        selectedValue: selected,
        onChanged: (v) => selected = v,
      ),
    );
    if (confirmed == true && selected != null) {
      await ref.read(hartTableProvider.notifier).removeColumn(selected!);
    }
  }
}

// ── Main table with synchronized scrollbars ───────────────────────────────────
class _HartTable extends StatefulWidget {
  final HartTableState state;
  const _HartTable({required this.state});

  @override
  State<_HartTable> createState() => _HartTableState();
}

class _HartTableState extends State<_HartTable> {
  static const double _rowH  = 38.0;
  static const double _colW  = 130.0;
  static const double _devW  = 110.0;
  static const double _headH = 36.0;

  final _vCtrl     = ScrollController();
  final _hHeadCtrl = ScrollController();
  final _hBodyCtrl = ScrollController();
  bool  _syncing   = false;

  @override
  void initState() {
    super.initState();
    _hHeadCtrl.addListener(_syncHeadToBody);
    _hBodyCtrl.addListener(_syncBodyToHead);
  }

  void _syncHeadToBody() {
    if (_syncing) return;
    _syncing = true;
    if (_hBodyCtrl.hasClients && _hBodyCtrl.offset != _hHeadCtrl.offset) {
      _hBodyCtrl.jumpTo(_hHeadCtrl.offset);
    }
    _syncing = false;
  }

  void _syncBodyToHead() {
    if (_syncing) return;
    _syncing = true;
    if (_hHeadCtrl.hasClients && _hHeadCtrl.offset != _hBodyCtrl.offset) {
      _hHeadCtrl.jumpTo(_hBodyCtrl.offset);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    _hHeadCtrl.dispose();
    _hBodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s       = widget.state;
    final numCols = s.visibleCols.length;
    final bodyW   = numCols * _colW;

    return Column(children: [
      // ── Column headers (sticky top) ───────────────────────────────────
      Container(
        height: _headH,
        color: AppColors.cardDark,
        child: Row(children: [
          // Device corner cell
          Container(
            width: _devW,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.borderDark))),
            child: const Text('DEVICE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary, letterSpacing: 1)),
          ),
          // Scrollable column headers (synced with body, no visible scrollbar)
          Expanded(
            child: SingleChildScrollView(
              controller: _hHeadCtrl,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: s.visibleCols
                    .map((c) => _ColHeader(label: c, width: _colW))
                    .toList(),
              ),
            ),
          ),
        ]),
      ),
      const Divider(height: 1),

      // ── Body ──────────────────────────────────────────────────────────
      Expanded(
        child: Row(children: [
          // Sticky device-name column (scrolls vertically only)
          SizedBox(
            width: _devW,
            child: ListView.builder(
              controller: _vCtrl,
              itemCount: s.devices.length,
              itemExtent: _rowH,
              itemBuilder: (_, i) => _DeviceNameCell(
                name: s.devices[i],
                index: i,
                height: _rowH,
                width: _devW,
              ),
            ),
          ),
          const VerticalDivider(width: 1),

          // Data area: horizontal + vertical scroll
          Expanded(
            child: Scrollbar(
              controller: _hBodyCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _hBodyCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: bodyW,
                  child: Scrollbar(
                    controller: _vCtrl,
                    thumbVisibility: true,
                    child: Consumer(builder: (ctx, ref, _) {
                      final state = ref.watch(hartTableProvider);
                      return ListView.builder(
                        controller: _vCtrl,
                        itemCount: state.devices.length,
                        itemExtent: _rowH,
                        itemBuilder: (_, i) {
                          final device = state.devices[i];
                          return _DataRow(
                            device: device,
                            cols: state.visibleCols,
                            state: state,
                            colW: _colW,
                            height: _rowH,
                            index: i,
                            onDoubleTap: (col) =>
                                _onCellDoubleTap(ctx, ref, device, col, state),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _onCellDoubleTap(BuildContext context, WidgetRef ref,
      String device, String col, HartTableState state) async {
    final v = state.data[device]?[col];
    if (v == null) return;
    final newVal = await EditCellDialog.show(context, v, state.showHuman);
    if (newVal != null) {
      await ref
          .read(hartTableProvider.notifier)
          .setCellValue(device, col, newVal);
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
class _ColHeader extends StatelessWidget {
  final String label;
  final double width;
  const _ColHeader({required this.label, required this.width});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 36,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.borderDark))),
        child: Tooltip(
          message: label,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3)),
        ),
      );
}

class _DeviceNameCell extends StatelessWidget {
  final String name;
  final int    index;
  final double height;
  final double width;
  const _DeviceNameCell(
      {required this.name, required this.index,
       required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    final isOdd = index.isOdd;
    return Container(
      height: height,
      width: width,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: isOdd ? AppColors.surfaceDark : AppColors.backgroundDark,
      child: Text(name,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
    );
  }
}

class _DataRow extends StatelessWidget {
  final String         device;
  final List<String>   cols;
  final HartTableState state;
  final double         colW;
  final double         height;
  final int            index;
  final void Function(String col) onDoubleTap;

  const _DataRow({
    required this.device,
    required this.cols,
    required this.state,
    required this.colW,
    required this.height,
    required this.index,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOdd = index.isOdd;
    final bg = isOdd ? AppColors.surfaceDark : AppColors.backgroundDark;
    return SizedBox(
      height: height,
      child: Row(
        children: cols.map((col) {
          final model   = state.cellModel(device, col);
          final display = state.cellDisplay(device, col);
          return _DataCell(
            display: display,
            model: model,
            width: colW,
            height: height,
            bg: bg,
            onDoubleTap: () => onDoubleTap(col),
          );
        }).toList(),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String    display;
  final DbModel   model;
  final double    width;
  final double    height;
  final Color     bg;
  final VoidCallback onDoubleTap;

  const _DataCell({
    required this.display,
    required this.model,
    required this.width,
    required this.height,
    required this.bg,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final (cellBg, textColor, prefix) = switch (model) {
      DbModel.func  => (AppColors.cellFunc,  AppColors.infoLight,   '@'),
      DbModel.tFunc => (AppColors.cellTFunc, AppColors.successLight, r'$'),
      _             => (bg,                  AppColors.textPrimary,  ''),
    };

    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Tooltip(
        message: display,
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: cellBg,
            border: const Border(
              right:  BorderSide(color: AppColors.borderDark, width: 0.5),
              bottom: BorderSide(color: AppColors.borderDark, width: 0.3),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: Row(children: [
            if (prefix.isNotEmpty) ...[
              Text(prefix,
                  style: TextStyle(
                      fontSize: 10,
                      color: textColor,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 2),
            ],
            Expanded(
              child: Text(display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: textColor,
                      fontFamily: 'monospace')),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TableFooter extends StatelessWidget {
  final int deviceCount;
  final int colCount;
  const _TableFooter({required this.deviceCount, required this.colCount});

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          border: Border(top: BorderSide(color: AppColors.borderDark))),
        child: Row(children: [
          const Icon(Icons.table_rows_outlined,
              size: 12, color: AppColors.textDisabled),
          const SizedBox(width: 4),
          Text('$deviceCount × $colCount',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textDisabled)),
          const Spacer(),
          const Text('Double-tap cell to edit',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textDisabled)),
        ]),
      );
}

// ── Shared toolbar widgets ────────────────────────────────────────────────────
class _ToolbarLabel extends StatelessWidget {
  final String text;
  const _ToolbarLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ]),
        ),
      );
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1, height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: AppColors.borderDark);
}

// ── Remove / Select dialog (shared for device and column) ────────────────────
class _RemoveDialog extends StatefulWidget {
  final String            title;
  final List<String>      items;
  final String?           selectedValue;
  final ValueChanged<String?> onChanged;
  final String            confirmLabel;
  final Color             confirmColor;

  const _RemoveDialog({
    required this.title,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
    this.confirmLabel = 'Remove',
    this.confirmColor = AppColors.error,
  });

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedValue;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
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
