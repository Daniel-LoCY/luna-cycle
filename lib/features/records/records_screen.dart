import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';
import 'period_editor_sheet.dart';
import 'quick_log_sheet.dart';

class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LunaPage(
    title: '健康記錄',
    action: IconButton(
      tooltip: '新增今天的紀錄',
      icon: const Icon(Icons.add),
      onPressed: () => showQuickLogSheet(context, ref, DateTime.now()),
    ),
    children: [
      const Text('只記錄你願意分享給自己的部分。留白代表尚未記錄。'),
      const SizedBox(height: 14),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          labelText: '搜尋日期、症狀、標籤或備註',
          border: const OutlineInputBorder(),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜尋',
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: Text('月經紀錄', style: Theme.of(context).textTheme.titleLarge),
          ),
          FilledButton.tonalIcon(
            onPressed: () => showPeriodEditorSheet(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('補登'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ref
          .watch(periodsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => LunaCard(child: Text('讀取月經紀錄失敗：$error')),
            data: (periods) {
              final visible = periods
                  .where((period) => _matchesPeriod(period, _search.text))
                  .toList();
              if (visible.isEmpty) {
                return _search.text.trim().isEmpty
                    ? const EmptyState(
                        icon: Icons.water_drop_outlined,
                        title: '還沒有月經紀錄',
                        message: '可從首頁開始記錄，或補登過去的經期。',
                      )
                    : const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: '找不到月經紀錄',
                        message: '調整搜尋文字，或補登一筆過去的經期。',
                      );
              }
              return Column(
                children: [
                  for (final period in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LunaCard(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.water_drop_outlined,
                              color: Color(0xFFF2B7C6),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${DateFormat('yyyy年M月d日').format(period.startDate)}–${period.endDate == null ? '進行中' : DateFormat('M月d日').format(period.endDate!)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  if (period.flow != null ||
                                      period.spotting ||
                                      period.clots)
                                    Text(
                                      [
                                        if (period.flow != null)
                                          '經血${period.flow}',
                                        if (period.spotting) '點狀出血',
                                        if (period.clots) '血塊',
                                      ].join('・'),
                                    ),
                                  if (period.note?.isNotEmpty == true)
                                    Text(period.note!),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '月經紀錄選項',
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  await showPeriodEditorSheet(
                                    context,
                                    ref,
                                    period: period,
                                  );
                                } else {
                                  await _deletePeriod(context, ref, period.id);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'edit', child: Text('編輯')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('刪除'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: Text(
              '每日健康記錄',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ref
          .watch(dailyLogsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => LunaCard(child: Text('讀取紀錄失敗：$error')),
            data: (logs) {
              final visible = logs
                  .where((log) => _matchesLog(log, _search.text))
                  .toList();
              if (visible.isEmpty) {
                return _search.text.trim().isEmpty
                    ? const EmptyState(
                        icon: Icons.edit_note_rounded,
                        title: '還沒有健康紀錄',
                        message: '新增症狀、情緒、疼痛或日記。',
                      )
                    : const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: '找不到健康紀錄',
                        message: '調整搜尋文字，或新增症狀、情緒、疼痛或日記。',
                      );
              }
              return Column(
                children: [
                  for (final log in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LunaCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('yyyy年M月d日').format(log.day),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (log.painLevel != null)
                              Text('疼痛 ${log.painLevel}/10'),
                            if (log.flow != null || log.spotting || log.clots)
                              Text(
                                [
                                  if (log.flow != null) '經血${log.flow}',
                                  if (log.spotting) '點狀出血',
                                  if (log.clots) '血塊',
                                ].join('・'),
                              ),
                            if (log.symptomsJson != '[]')
                              Text('症狀：${_formatList(log.symptomsJson)}'),
                            if (log.moodsJson != '[]')
                              Text('情緒：${_formatList(log.moodsJson)}'),
                            if (log.medicationJson != '[]')
                              Text('藥物：${_formatList(log.medicationJson)}'),
                            if (log.tagsJson != '[]')
                              Text('標籤：${_formatList(log.tagsJson)}'),
                            if (log.bodyJson != '{}')
                              Text('身體：${_formatMap(log.bodyJson)}'),
                            if (log.reproductiveJson != '{}')
                              Text('生殖健康：${_formatMap(log.reproductiveJson)}'),
                            if (log.note?.isNotEmpty == true) Text(log.note!),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    showQuickLogSheet(context, ref, log.day),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('編輯'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    ],
  );
}

bool _matchesPeriod(Period period, String input) {
  final query = input.trim().toLowerCase();
  if (query.isEmpty) return true;
  final content = [
    DateFormat('yyyy年M月d日').format(period.startDate),
    period.startDate.toIso8601String(),
    if (period.endDate != null) DateFormat('yyyy年M月d日').format(period.endDate!),
    period.flow ?? '',
    period.note ?? '',
    if (period.spotting) '點狀出血',
    if (period.clots) '血塊',
  ].join(' ').toLowerCase();
  return content.contains(query);
}

bool _matchesLog(DailyLog log, String input) {
  final query = input.trim().toLowerCase();
  if (query.isEmpty) return true;
  final content = [
    DateFormat('yyyy年M月d日').format(log.day),
    log.day.toIso8601String(),
    log.painLevel?.toString() ?? '',
    log.flow ?? '',
    log.symptomsJson,
    log.moodsJson,
    log.bodyJson,
    log.reproductiveJson,
    log.medicationJson,
    log.tagsJson,
    log.note ?? '',
    if (log.spotting) '點狀出血',
    if (log.clots) '血塊',
  ].join(' ').toLowerCase();
  return content.contains(query);
}

String _formatList(String encoded) {
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is List) return decoded.whereType<String>().join('、');
  } on FormatException {
    return '記錄已儲存';
  }
  return '記錄已儲存';
}

String _formatMap(String encoded) {
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, dynamic>) {
      return decoded.entries
          .map((entry) => '${_fieldName(entry.key)} ${entry.value}')
          .join('、');
    }
  } on FormatException {
    return '記錄已儲存';
  }
  return '記錄已儲存';
}

String _fieldName(String key) => switch (key) {
  'sleepHours' => '睡眠',
  'energy' => '精力',
  'appetite' => '食慾',
  'exercise' => '運動強度',
  'exerciseNote' => '運動',
  'weightKg' => '體重(kg)',
  'temperatureC' => '體溫(°C)',
  'discharge' => '分泌物',
  'ovulationTest' => '排卵試紙',
  'pregnancyTest' => '驗孕',
  'sexualActivity' => '性行為',
  'contraception' => '避孕方式',
  _ => key,
};

Future<void> _deletePeriod(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('刪除這筆月經紀錄？'),
      content: const Text('週期預測會依剩餘的實際紀錄重新計算。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  try {
    await ref.read(cycleRepositoryProvider).softDeletePeriod(id);
    ref.invalidate(dailyLogsProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刪除失敗：$error')));
    }
  }
}
