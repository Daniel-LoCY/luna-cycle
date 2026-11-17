import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/cycle_prediction.dart';
import '../../core/database/app_database.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';
import '../records/quick_status_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(periodsProvider);
    final config = ref.watch(cycleConfigProvider).value ?? const CycleConfig();
    final today = DateTime.now();
    final todayDate = DateTime.utc(today.year, today.month, today.day);
    return LunaPage(
      title: '今天，照顧好自己',
      children: [
        Text(
          DateFormat('yyyy年M月d日 EEEE', 'zh_TW').format(today),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: LunaColors.muted),
        ),
        const SizedBox(height: 18),
        periods.when(
          loading: () =>
              const LunaCard(child: Center(child: CircularProgressIndicator())),
          error: (error, stack) => LunaCard(child: Text('讀取月經紀錄失敗：$error')),
          data: (items) {
            final validPeriods = items
                .where((period) => period.deletedAt == null)
                .toList();
            final active = validPeriods
                .where((period) => period.endDate == null)
                .firstOrNull;
            final last = validPeriods
                .where((period) => !_date(period.startDate).isAfter(todayDate))
                .firstOrNull;
            final cycleDay = last == null
                ? null
                : todayDate.difference(_date(last.startDate)).inDays + 1;
            final prediction = predictCycles(
              periods: validPeriods
                  .map(
                    (period) => PeriodRecord(
                      start: period.startDate,
                      end: period.endDate,
                    ),
                  )
                  .toList(),
              mode: config.mode,
              configuredCycleLength: config.averageCycleLength,
              configuredPeriodLength: config.averagePeriodLength,
              fertilityEstimatesEnabled: config.fertilityEstimatesEnabled,
              predictionEnabled: config.predictionEnabled,
            );
            final nextStart = prediction.nextStarts.firstOrNull;
            final daysUntilStart = nextStart == null
                ? null
                : nextStart.earliest.difference(todayDate).inDays;
            return LunaCard(
              child: Row(
                children: [
                  SizedBox(
                    width: 124,
                    height: 124,
                    child: CustomPaint(
                      painter: _CycleRingPainter(
                        progress: cycleDay == null
                            ? 0
                            : ((cycleDay - 1) /
                                      (prediction.medianCycleLength ??
                                          config.averageCycleLength ??
                                          28))
                                  .clamp(0.0, 1.0),
                        color: active == null
                            ? LunaColors.lavender
                            : LunaColors.pink,
                        background: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      child: Semantics(
                        label: cycleDay == null ? '尚無週期資料' : '週期第 $cycleDay 天',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cycleDay?.toString() ?? '—',
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text('週期日', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active != null ? '月經紀錄進行中' : '週期狀態',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          last == null
                              ? '先記下最近一次月經，開始追蹤週期。'
                              : active != null
                              ? '請記下這次經期的每日變化。'
                              : prediction.support == PredictionSupport.disabled
                              ? '週期預測已關閉；實際紀錄仍會保留。'
                              : prediction.support ==
                                    PredictionSupport.notApplicable
                              ? '目前追蹤模式不使用一般週期預測。'
                              : daysUntilStart == null
                              ? '還需要更多資料才能估算下次經期。'
                              : daysUntilStart < 0
                              ? '已超過原本估算日；記錄仍以你的實際情況為準。'
                              : '距離估算下次月經約 $daysUntilStart 天。',
                        ),
                        if (nextStart != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '預估開始：${_shortDate(nextStart.earliest)}–${_shortDate(nextStart.latest)}',
                          ),
                          if (prediction.estimatedPeriodLength != null)
                            Text('預估經期約 ${prediction.estimatedPeriodLength} 天'),
                        ],
                        if (prediction.canEstimateFertility &&
                            prediction
                                .estimatedOvulationWindows
                                .isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '粗略排卵日：${_shortDate(prediction.estimatedOvulationWindows.first.earliest)}–${_shortDate(prediction.estimatedOvulationWindows.first.latest)}',
                          ),
                          Text(
                            '易受孕期為估算，不能作為避孕依據。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          prediction.explanation,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    final active = await ref
                        .read(cycleRepositoryProvider)
                        .getPeriods();
                    if (active.any(
                      (period) =>
                          period.endDate == null && period.deletedAt == null,
                    )) {
                      await ref
                          .read(cycleRepositoryProvider)
                          .endActivePeriod(DateTime.now());
                    } else {
                      await ref
                          .read(cycleRepositoryProvider)
                          .startPeriod(DateTime.now());
                    }
                  } catch (error) {
                    if (context.mounted)
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                },
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('開始／結束月經'),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: '記錄今天狀態',
              onPressed: () => showQuickStatusSheet(context, ref, todayDate),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _TodayQuickStatusCard(day: todayDate),
        const SizedBox(height: 12),
        const _TodayMedicationCard(),
        const SizedBox(height: 22),
        const Text(
          '最近紀錄',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 10),
        ref
            .watch(dailyLogsProvider)
            .when(
              loading: () => const LunaCard(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => LunaCard(child: Text('讀取紀錄失敗：$error')),
              data: (logs) => logs.isEmpty
                  ? const EmptyState(
                      icon: Icons.favorite_border,
                      title: '今天先留一筆給自己',
                      message: '症狀、情緒和身體感受都可以只記你想記的。',
                    )
                  : Column(
                      children: logs
                          .take(3)
                          .map(
                            (log) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: LunaCard(
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.notes_rounded,
                                      color: LunaColors.lavender,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        DateFormat('M月d日').format(log.day),
                                      ),
                                    ),
                                    Text(
                                      log.painLevel == null
                                          ? '有健康紀錄'
                                          : '疼痛 ${log.painLevel}/10',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
        const SizedBox(height: 12),
        const LunaCard(
          child: Text('週期日期為估算，可能與實際情況不同。此 App 不提供醫療診斷，也不能作為避孕依據。'),
        ),
      ],
    );
  }
}

class _TodayQuickStatusCard extends ConsumerWidget {
  const _TodayQuickStatusCard({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLog>[];
    final log = logs.where((entry) {
      final date = _date(entry.day);
      return entry.deletedAt == null &&
          date.year == day.year &&
          date.month == day.month &&
          date.day == day.day;
    }).firstOrNull;
    final summary = <String>[
      if (log?.flow != null) '經血量 ${log!.flow}',
      if (log?.painLevel != null) '疼痛 ${log!.painLevel}/10',
      if (log != null) ..._decodeMoodSummary(log.moodsJson),
    ];
    return LunaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: LunaColors.lavender),
              const SizedBox(width: 8),
              Text('今日快速記錄', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            summary.isEmpty ? '快速記下經血量、疼痛與心情。' : summary.join('  ·  '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => showQuickStatusSheet(context, ref, day),
              icon: const Icon(Icons.edit_outlined),
              label: Text(log == null ? '開始記錄' : '編輯快速記錄'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayMedicationCard extends ConsumerWidget {
  const _TodayMedicationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules =
        ref.watch(medicationSchedulesProvider).value ??
        const <MedicationSchedule>[];
    final intakes =
        ref.watch(medicationIntakesProvider).value ??
        const <MedicationIntakeEntry>[];
    final active = schedules.where((item) => item.enabled).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final todayEntries = intakes
        .where(
          (entry) =>
              entry.scheduledDay.year == today.year &&
              entry.scheduledDay.month == today.month &&
              entry.scheduledDay.day == today.day,
        )
        .toList();
    return LunaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日藥物提醒', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '自行標記服用或略過；未標記不代表漏服。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final schedule in active)
            for (final time in _medicationTimes(schedule.timesJson))
              _MedicationDoseRow(
                schedule: schedule,
                time: time,
                day: today,
                entry: todayEntries
                    .where(
                      (entry) =>
                          entry.scheduleId == schedule.id &&
                          entry.scheduledTime == time,
                    )
                    .firstOrNull,
              ),
        ],
      ),
    );
  }
}

class _MedicationDoseRow extends ConsumerWidget {
  const _MedicationDoseRow({
    required this.schedule,
    required this.time,
    required this.day,
    required this.entry,
  });

  final MedicationSchedule schedule;
  final String time;
  final DateTime day;
  final MedicationIntakeEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Semantics(
      label:
          '${schedule.label}，$time，${entry?.status == 'taken'
              ? '已服用'
              : entry?.status == 'skipped'
              ? '已略過'
              : '尚未記錄'}',
      child: Row(
        children: [
          Expanded(child: Text('${schedule.label} · $time')),
          ChoiceChip(
            label: const Text('已服用'),
            selected: entry?.status == 'taken',
            onSelected: (_) => _save(context, ref, 'taken'),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('略過'),
            selected: entry?.status == 'skipped',
            onSelected: (_) => _save(context, ref, 'skipped'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save(BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref
          .read(cycleRepositoryProvider)
          .saveMedicationIntake(
            scheduleId: schedule.id,
            scheduleLabel: schedule.label,
            scheduledDay: day,
            scheduledTime: time,
            status: status,
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('服用記錄無法儲存：$error')));
      }
    }
  }
}

List<String> _medicationTimes(String encoded) {
  try {
    final value = jsonDecode(encoded);
    if (value is List) return value.whereType<String>().toList();
  } on FormatException {
    return const [];
  }
  return const [];
}

List<String> _decodeMoodSummary(String encoded) {
  try {
    final values = jsonDecode(encoded);
    if (values is List) return values.whereType<String>().toList();
  } on FormatException {
    return const [];
  }
  return const [];
}

DateTime _date(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _shortDate(DateTime value) => '${value.month}/${value.day}';

class _CycleRingPainter extends CustomPainter {
  const _CycleRingPainter({
    required this.progress,
    required this.color,
    required this.background,
  });
  final double progress;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(5),
      -1.5708,
      6.2832,
      false,
      paint..color = background,
    );
    if (progress > 0)
      canvas.drawArc(
        rect.deflate(5),
        -1.5708,
        progress * 6.2832,
        false,
        paint..color = color,
      );
  }

  @override
  bool shouldRepaint(covariant _CycleRingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      background != oldDelegate.background;
}
