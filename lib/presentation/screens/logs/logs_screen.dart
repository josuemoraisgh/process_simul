import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../application/providers/app_providers.dart';
import '../../../application/notifiers/log_notifier.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollCtrl = ScrollController();
  LogLevel? _filterLevel;
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logProvider);
    final filtered = _filterLevel == null
        ? logs
        : logs.where((e) => e.level == _filterLevel).toList();

    // Auto-scroll to bottom when new entries arrive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return Column(children: [
      // ── Toolbar ─────────────────────────────────────────────────────────
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          border: Border(bottom: BorderSide(color: AppColors.borderDark)),
        ),
        child: Row(children: [
          const Icon(Icons.receipt_long_outlined, size: 16,
              color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('${filtered.length} entries',
              style: const TextStyle(fontSize: 12,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          // Level filter chips
          ...[null, LogLevel.info, LogLevel.warning, LogLevel.error,
              LogLevel.debug].map((lv) {
            final label = lv == null ? 'All' : switch (lv) {
              LogLevel.debug   => 'Debug',
              LogLevel.info    => 'Info',
              LogLevel.warning => 'Warning',
              LogLevel.error   => 'Error',
            };
            final isSelected = _filterLevel == lv;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(label,
                    style: TextStyle(fontSize: 11,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary)),
                selected: isSelected,
                onSelected: (_) =>
                    setState(() => _filterLevel = lv),
                selectedColor: lv == null
                    ? AppColors.primary
                    : _levelColor(lv),
                backgroundColor: AppColors.cardDark,
                side: const BorderSide(color: AppColors.borderDark),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
          const Spacer(),
          // Auto-scroll toggle
          Row(children: [
            const Text('Auto-scroll',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(width: 4),
            Switch(
              value: _autoScroll,
              onChanged: (v) => setState(() => _autoScroll = v),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
          const SizedBox(width: 8),
          // Copy all
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 16),
            tooltip: 'Copy all to clipboard',
            onPressed: () {
              final text = filtered.map((e) =>
                '[${e.timeStr}] [${e.levelLabel}] [${e.source}] ${e.message}'
              ).join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1)));
            },
          ),
          // Clear
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            tooltip: 'Clear logs',
            style: IconButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () {
              ref.read(logProvider.notifier).clear();
            },
          ),
        ]),
      ),

      // ── Log list ─────────────────────────────────────────────────────────
      Expanded(
        child: filtered.isEmpty
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_outlined, size: 48,
                      color: AppColors.textDisabled),
                  SizedBox(height: 8),
                  Text('No log entries',
                      style: TextStyle(color: AppColors.textDisabled)),
                ]),
              )
            : Scrollbar(
                controller: _scrollCtrl,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: filtered.length,
                  itemExtent: 28,
                  itemBuilder: (_, i) => _LogRow(
                    entry: filtered[i],
                    index: i,
                  ),
                ),
              ),
      ),

      // ── Status bar ───────────────────────────────────────────────────────
      Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: AppColors.surfaceDark,
        child: Row(children: [
          _LevelCount(logs, LogLevel.error,   AppColors.error),
          const SizedBox(width: 12),
          _LevelCount(logs, LogLevel.warning, AppColors.warning),
          const SizedBox(width: 12),
          _LevelCount(logs, LogLevel.info,    AppColors.info),
        ]),
      ),
    ]);
  }

  Color _levelColor(LogLevel lv) => switch (lv) {
    LogLevel.debug   => AppColors.textDisabled,
    LogLevel.info    => AppColors.info,
    LogLevel.warning => AppColors.warning,
    LogLevel.error   => AppColors.error,
  };
}

// ── Log row ───────────────────────────────────────────────────────────────────
class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final int      index;
  const _LogRow({required this.entry, required this.index});

  @override
  Widget build(BuildContext context) {
    final (textColor, bgColor) = switch (entry.level) {
      LogLevel.error   =>
        (AppColors.errorLight,   AppColors.error.withValues(alpha: 0.08)),
      LogLevel.warning =>
        (AppColors.warningLight, AppColors.warning.withValues(alpha: 0.06)),
      LogLevel.debug   =>
        (AppColors.textDisabled, Colors.transparent),
      _                =>
        (AppColors.textPrimary,  Colors.transparent),
    };

    final isOdd = index.isOdd;

    return Container(
      height: 28,
      color: isOdd
          ? AppColors.surfaceDark.withValues(alpha: 0.5)
          : bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        // Time
        SizedBox(
          width: 80,
          child: Text(entry.timeStr,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: AppColors.textDisabled)),
        ),
        // Level badge
        Container(
          width: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: _badgeColor(entry.level).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(entry.levelLabel,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _badgeColor(entry.level), fontFamily: 'monospace')),
        ),
        const SizedBox(width: 8),
        // Source
        SizedBox(
          width: 100,
          child: Text(entry.source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: AppColors.primaryLight)),
        ),
        const SizedBox(width: 8),
        // Message
        Expanded(
          child: Text(entry.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: textColor)),
        ),
      ]),
    );
  }

  Color _badgeColor(LogLevel l) => switch (l) {
    LogLevel.error   => AppColors.error,
    LogLevel.warning => AppColors.warning,
    LogLevel.info    => AppColors.info,
    LogLevel.debug   => AppColors.textDisabled,
  };
}

class _LevelCount extends StatelessWidget {
  final List<LogEntry> logs;
  final LogLevel level;
  final Color    color;
  const _LevelCount(this.logs, this.level, this.color);

  @override
  Widget build(BuildContext context) {
    final count = logs.where((e) => e.level == level).length;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 4),
      Text('$count', style: TextStyle(fontSize: 10, color: color)),
    ]);
  }
}
