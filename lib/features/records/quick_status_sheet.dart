import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers.dart';

Future<void> showQuickStatusSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) async {
  DailyLog? previous;
  try {
    previous = await ref.read(cycleRepositoryProvider).getDailyLog(day);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('讀取今天的快速紀錄失敗，尚未變更資料。')));
    }
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _QuickStatusSheet(
      day: day,
      previous: previous,
      ref: ref,
      messenger: ScaffoldMessenger.of(context),
    ),
  );
}

class _QuickStatusSheet extends StatefulWidget {
  const _QuickStatusSheet({
    required this.day,
    required this.previous,
    required this.ref,
    required this.messenger,
  });

  final DateTime day;
  final DailyLog? previous;
  final WidgetRef ref;
  final ScaffoldMessengerState messenger;

  @override
  State<_QuickStatusSheet> createState() => _QuickStatusSheetState();
}

class _QuickStatusSheetState extends State<_QuickStatusSheet> {
  static const _commonMoods = ['開心', '平靜', '焦慮', '煩躁', '難過', '敏感', '壓力'];
  static const _flows = ['無', '少', '中', '多'];

  late int? _pain = widget.previous?.painLevel;
  late String? _flow = widget.previous?.flow;
  late final Set<String> _moods = _decodeMoods(widget.previous?.moodsJson);
  bool _saving = false;

  List<String> get _moodChoices => {
    ..._commonMoods,
    ..._moods.where((mood) => !_commonMoods.contains(mood)),
  }.toList();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今天的快速記錄', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.day.year}年${widget.day.month}月${widget.day.day}日・其他健康紀錄不會更動',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('經血量', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final flow in _flows)
                  ChoiceChip(
                    label: Text(flow),
                    selected: _flow == flow,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _flow = flow),
                  ),
                if (_flow != null)
                  ActionChip(
                    label: const Text('清除'),
                    onPressed: _saving
                        ? null
                        : () => setState(() => _flow = null),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '疼痛程度',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(_pain == null ? '未記錄' : '$_pain / 10'),
                if (_pain != null)
                  IconButton(
                    tooltip: '清除疼痛程度',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _pain = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            Slider(
              value: (_pain ?? 0).toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              label: _pain?.toString() ?? '未記錄',
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _pain = value.round()),
            ),
            const SizedBox(height: 12),
            Text('心情', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final mood in _moodChoices)
                  FilterChip(
                    label: Text(mood),
                    selected: _moods.contains(mood),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _moods.add(mood);
                            } else {
                              _moods.remove(mood);
                            }
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '儲存中…' : '儲存快速紀錄'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.ref
          .read(cycleRepositoryProvider)
          .saveQuickLog(
            day: widget.day,
            painLevel: _pain,
            flow: _flow,
            moods: _moods.toList(),
          );
      widget.ref.invalidate(dailyLogsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.messenger.showSnackBar(
        SnackBar(
          content: const Text('快速紀錄已儲存'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: '撤銷',
            onPressed: () => _undo(saved.version),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        widget.messenger.showSnackBar(SnackBar(content: Text('儲存失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _undo(int expectedVersion) async {
    try {
      await widget.ref
          .read(cycleRepositoryProvider)
          .restoreQuickLog(
            day: widget.day,
            previous: widget.previous,
            expectedVersion: expectedVersion,
          );
      widget.ref.invalidate(dailyLogsProvider);
      widget.messenger.showSnackBar(const SnackBar(content: Text('已撤銷快速紀錄')));
    } catch (_) {
      widget.messenger.showSnackBar(
        const SnackBar(content: Text('這筆紀錄已有更新，無法撤銷。')),
      );
    }
  }
}

Set<String> _decodeMoods(String? encoded) {
  if (encoded == null) return {};
  try {
    final values = jsonDecode(encoded);
    if (values is List) return values.whereType<String>().toSet();
  } on FormatException {
    return {};
  }
  return {};
}
