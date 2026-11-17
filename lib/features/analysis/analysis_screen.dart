import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/cycle_prediction.dart';
import '../../core/cycle_insights.dart';
import '../../core/database/app_database.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  int _months = 6;

  @override
  Widget build(BuildContext context) {
    final periodsAsync = ref.watch(periodsProvider);
    final logsAsync = ref.watch(dailyLogsProvider);
    final config = ref.watch(cycleConfigProvider).value ?? const CycleConfig();
    if (periodsAsync.isLoading || logsAsync.isLoading) {
      return const LunaPage(
        title: '週期分析',
        children: [Center(child: CircularProgressIndicator())],
      );
    }
    if (periodsAsync.hasError || logsAsync.hasError) {
      return LunaPage(
        title: '週期分析',
        children: [
          LunaCard(
            child: Text('讀取分析資料失敗：${periodsAsync.error ?? logsAsync.error}'),
          ),
        ],
      );
    }

    final periods = periodsAsync.value ?? const <Period>[];
    final allLogs = logsAsync.value ?? const <DailyLog>[];
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - _months + 1, 1);
    final actualPeriods =
        periods.where((item) => item.deletedAt == null).toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final starts = actualPeriods
        .map((item) => _dateOnly(item.startDate))
        .toList();
    final cycleLengths = <int>[
      for (var i = 1; i < starts.length; i++)
        if (!starts[i].isBefore(_dateOnly(cutoff)) &&
            !starts[i - 1].isBefore(_dateOnly(cutoff)))
          starts[i].difference(starts[i - 1]).inDays,
    ];
    final closedPeriods = actualPeriods
        .where(
          (item) =>
              item.endDate != null &&
              !_dateOnly(item.endDate!).isBefore(_dateOnly(cutoff)),
        )
        .toList();
    final periodLengths = closedPeriods
        .map(
          (item) =>
              _dateOnly(
                item.endDate!,
              ).difference(_dateOnly(item.startDate)).inDays +
              1,
        )
        .where((value) => value > 0)
        .toList();
    final logs =
        allLogs
            .where(
              (item) =>
                  item.deletedAt == null &&
                  !_dateOnly(item.day).isBefore(_dateOnly(cutoff)),
            )
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));

    return LunaPage(
      title: '週期分析',
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 3, label: Text('3 個月')),
            ButtonSegment(value: 6, label: Text('6 個月')),
            ButtonSegment(value: 12, label: Text('12 個月')),
          ],
          selected: {_months},
          onSelectionChanged: (values) =>
              setState(() => _months = values.first),
        ),
        const SizedBox(height: 16),
        if (cycleLengths.isEmpty)
          const LunaCard(
            child: EmptyState(
              icon: Icons.insights_outlined,
              title: '還沒有週期長度資料',
              message: '記錄兩次月經開始日期後，就能分析週期間隔。圖表只呈現實際紀錄。',
            ),
          )
        else ...[
          _summaryCard(cycleLengths),
          const SizedBox(height: 12),
          _chartCard(
            title: '週期長度',
            subtitle: '相鄰月經開始日的實際間隔',
            child: _cycleLineChart(cycleLengths),
          ),
        ],
        const SizedBox(height: 12),
        if (periodLengths.isEmpty)
          const LunaCard(child: Text('目前沒有已結束的經期可計算天數。'))
        else
          _chartCard(
            title: '經期天數',
            subtitle: '已結束經期的實際天數',
            child: _barChart(periodLengths, unit: '天'),
          ),
        const SizedBox(height: 12),
        if (logs.isEmpty)
          const LunaCard(child: Text('這段期間尚無每日健康記錄；症狀、情緒與疼痛分析會在記錄後顯示。'))
        else ...[
          if (logs.any((item) => item.flow != null)) _flowCard(logs),
          if (logs.any(
            (item) => _readStrings(item.symptomsJson).isNotEmpty,
          )) ...[
            const SizedBox(height: 12),
            _chartCard(
              title: '常見症狀',
              subtitle: '依每日記錄次數排序',
              child: _categoryBars(
                _countValues(
                  logs.expand((item) => _readStrings(item.symptomsJson)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _cycleSymptomPatternsCard(actualPeriods, logs, config),
            const SizedBox(height: 12),
            _symptomHeatmap(logs),
          ],
          if (logs.any((item) => _readStrings(item.moodsJson).isNotEmpty)) ...[
            const SizedBox(height: 12),
            _moodCard(logs),
          ],
          if (logs.any((item) => item.painLevel != null)) ...[
            const SizedBox(height: 12),
            _chartCard(
              title: '疼痛趨勢',
              subtitle: '每日自評 0–10 分',
              child: _painLineChart(logs),
            ),
          ],
        ],
        const SizedBox(height: 12),
        _predictionRationaleCard(actualPeriods, config),
        const SizedBox(height: 12),
        _predictionVarianceCard(actualPeriods, config, cutoff),
        const SizedBox(height: 12),
        const Text('以上分析僅摘要你的實際紀錄。預測日期為估算，不提供疾病診斷或避孕保證。'),
      ],
    );
  }

  Widget _summaryCard(List<int> cycleLengths) {
    final sorted = cycleLengths.toList()..sort();
    final average = cycleLengths.reduce((a, b) => a + b) / cycleLengths.length;
    final median = _median(sorted);
    return LunaCard(
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        children: [
          _Metric(label: '平均週期', value: '${average.toStringAsFixed(1)} 天'),
          _Metric(label: '中位數', value: '$median 天'),
          _Metric(label: '最短', value: '${sorted.first} 天'),
          _Metric(label: '最長', value: '${sorted.last} 天'),
          _Metric(label: '樣本數', value: '${cycleLengths.length} 次'),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) => LunaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: LunaColors.muted)),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _cycleLineChart(List<int> values) {
    final points = values.length <= 12
        ? values
        : values.sublist(values.length - 12);
    final minValue = points.reduce(math.min).toDouble();
    final maxValue = points.reduce(math.max).toDouble();
    final minY = math.max(0.0, (minValue - 8).floorToDouble()).toDouble();
    final maxY = math.max(minY + 10, (maxValue + 8).ceilToDouble()).toDouble();
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: LunaColors.muted.withValues(alpha: .15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 10,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: LunaColors.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt() + 1}',
                  style: const TextStyle(fontSize: 10, color: LunaColors.muted),
                ),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].toDouble()),
              ],
              isCurved: false,
              color: LunaColors.lavender,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: LunaColors.lavender.withValues(alpha: .12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barChart(List<int> values, {required String unit}) {
    final points = values.length <= 8
        ? values
        : values.sublist(values.length - 8);
    final maxY = math.max(5, points.reduce(math.max) + 2).toDouble();
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: math.max(1, (maxY / 3).ceil()).toDouble(),
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}$unit',
                  style: const TextStyle(fontSize: 10, color: LunaColors.muted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt() + 1}',
                  style: const TextStyle(fontSize: 10, color: LunaColors.muted),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].toDouble(),
                    width: 20,
                    color: LunaColors.pink,
                    borderRadius: BorderRadius.circular(7),
                    rodStackItems: const [],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _flowCard(List<DailyLog> logs) {
    const choices = ['無', '少', '中', '多'];
    final counts = {for (final value in choices) value: 0};
    for (final log in logs) {
      if (counts.containsKey(log.flow))
        counts[log.flow!] = counts[log.flow!]! + 1;
    }
    return _chartCard(
      title: '每日經血量',
      subtitle: '已記錄日數',
      child: Row(
        children: [
          for (final value in choices)
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${counts[value]}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(value),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoryBars(Map<String, int> counts) {
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final items = top.take(5).toList();
    final maxCount = items.map((item) => item.value).reduce(math.max);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(width: 74, child: Text(item.key)),
                Expanded(
                  child: LinearProgressIndicator(
                    value: item.value / maxCount,
                    minHeight: 9,
                    borderRadius: BorderRadius.circular(8),
                    color: LunaColors.lavender,
                    backgroundColor: LunaColors.lavender.withValues(alpha: .13),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${item.value} 次'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _moodCard(List<DailyLog> logs) {
    final counts = _countValues(
      logs.expand((item) => _readStrings(item.moodsJson)),
    );
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = [
      LunaColors.lavender,
      LunaColors.pink,
      LunaColors.mint,
      const Color(0xFFE9C37B),
      const Color(0xFFA9BBD9),
      const Color(0xFFD9B3A7),
    ];
    return _chartCard(
      title: '情緒分布',
      subtitle: '依每日記錄次數統計',
      child: SizedBox(
        height: 190,
        child: Row(
          children: [
            Expanded(
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 34,
                  sectionsSpace: 3,
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      PieChartSectionData(
                        value: entries[i].value.toDouble(),
                        color: colors[i % colors.length],
                        radius: 44,
                        title: '',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < entries.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(entries[i].key)),
                          Text('${entries[i].value}'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _painLineChart(List<DailyLog> logs) {
    final values = logs.where((item) => item.painLevel != null).toList();
    final points = values.length <= 14
        ? values
        : values.sublist(values.length - 14);
    return SizedBox(
      height: 170,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 10,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: LunaColors.muted.withValues(alpha: .15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 5,
              ),
            ),
            bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].painLevel!.toDouble()),
              ],
              color: LunaColors.pink,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              isCurved: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _symptomHeatmap(List<DailyLog> logs) {
    final countsByDay = <String, int>{};
    for (final log in logs) {
      final count = _readStrings(log.symptomsJson).length;
      if (count > 0) countsByDay[_dayKey(log.day)] = count;
    }
    final today = _dateOnly(DateTime.now());
    final start = today.subtract(const Duration(days: 27));
    return _chartCard(
      title: '近 4 週症狀日曆',
      subtitle: '顏色越深，當日記錄的症狀越多',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 28,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: 37,
          crossAxisSpacing: 5,
          mainAxisSpacing: 5,
        ),
        itemBuilder: (context, index) {
          final day = start.add(Duration(days: index));
          final count = countsByDay[_dayKey(day)] ?? 0;
          final alpha = count == 0 ? .08 : (0.25 + count * .12).clamp(.25, .85);
          return Semantics(
            label: '${day.month}月${day.day}日，有 $count 項症狀記錄',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LunaColors.lavender.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text('${day.day}', style: const TextStyle(fontSize: 11)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cycleSymptomPatternsCard(
    List<Period> periods,
    List<DailyLog> logs,
    CycleConfig config,
  ) {
    final patterns = summarizeCycleSymptoms(
      periods: [
        for (final period in periods)
          PeriodRecord(start: period.startDate, end: period.endDate),
      ],
      logs: [
        for (final log in logs)
          DailySymptomLog(
            day: log.day,
            symptoms: _readStrings(log.symptomsJson),
          ),
      ],
      mode: config.mode,
    );
    final notApplicable =
        config.mode == CycleMode.hormonalContraception ||
        config.mode == CycleMode.pregnancy ||
        config.mode == CycleMode.postpartum ||
        config.mode == CycleMode.trackingOnly;
    return LunaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('個人症狀週期規律', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (notApplicable)
            const Text('目前追蹤模式不使用自然週期日序比較症狀。')
          else if (patterns.isEmpty)
            const Text('目前沒有在至少兩個週期中重複出現的症狀階段。')
          else
            for (final pattern in patterns.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${pattern.symptom}較常記在${pattern.phase.label}，出現在 ${pattern.cycleCount} 個週期（${pattern.recordCount} 天記錄）。',
                ),
              ),
          const SizedBox(height: 4),
          const Text(
            '只整理你記下的症狀與週期位置，不推斷疾病或原因。',
            style: TextStyle(color: LunaColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _predictionVarianceCard(
    List<Period> periods,
    CycleConfig config,
    DateTime cutoff,
  ) {
    final starts = periods.map((item) => item.startDate).toList()
      ..sort((a, b) => a.compareTo(b));
    final deviations = <int>[];
    for (var index = 4; index < starts.length; index++) {
      if (_dateOnly(starts[index]).isBefore(_dateOnly(cutoff))) continue;
      final prediction = predictCycles(
        periods: [
          for (final start in starts.take(index)) PeriodRecord(start: start),
        ],
        mode: config.mode,
        configuredCycleLength: config.averageCycleLength,
        configuredPeriodLength: config.averagePeriodLength,
        fertilityEstimatesEnabled: false,
        predictionEnabled: config.predictionEnabled,
        forecastCount: 1,
      );
      if (prediction.nextStarts.isEmpty) continue;
      final range = prediction.nextStarts.first;
      final actual = _dateOnly(starts[index]);
      deviations.add(
        actual.isBefore(range.earliest)
            ? actual.difference(range.earliest).inDays
            : actual.isAfter(range.latest)
            ? actual.difference(range.latest).inDays
            : 0,
      );
    }
    if (!config.predictionEnabled) {
      return const LunaCard(child: Text('週期預測已關閉，因此沒有預測日期偏差分析。'));
    }
    if (deviations.isEmpty) {
      return const LunaCard(child: Text('累積更多週期後，這裡會比較過去預測區間與實際開始日。'));
    }
    final meanAbsolute =
        deviations.map((value) => value.abs()).reduce((a, b) => a + b) /
        deviations.length;
    return LunaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '預測日期與實際日期偏差',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '平均距離過去預測區間 ${meanAbsolute.toStringAsFixed(1)} 天，${deviations.length} 次比較。',
          ),
          const SizedBox(height: 4),
          const Text(
            '回顧值只代表你的歷史資料，不代表未來準確度。',
            style: TextStyle(color: LunaColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _predictionRationaleCard(List<Period> periods, CycleConfig config) {
    final prediction = predictCycles(
      periods: [
        for (final period in periods)
          PeriodRecord(start: period.startDate, end: period.endDate),
      ],
      mode: config.mode,
      configuredCycleLength: config.averageCycleLength,
      configuredPeriodLength: config.averagePeriodLength,
      fertilityEstimatesEnabled: false,
      predictionEnabled: config.predictionEnabled,
      forecastCount: 6,
    );
    return LunaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('預測依據', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(prediction.explanation),
          const SizedBox(height: 4),
          const Text(
            '週期日期來自實際開始日；估算不保證準確，也不能作為避孕依據。',
            style: TextStyle(color: LunaColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: LunaColors.muted)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
String _dayKey(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

List<String> _readStrings(String encoded) {
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is List) return decoded.whereType<String>().toList();
  } on FormatException {
    return const [];
  }
  return const [];
}

Map<String, int> _countValues(Iterable<String> values) {
  final result = <String, int>{};
  for (final value in values) {
    result.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return result;
}

int _median(List<int> sortedValues) {
  final middle = sortedValues.length ~/ 2;
  if (sortedValues.length.isOdd) return sortedValues[middle];
  return ((sortedValues[middle - 1] + sortedValues[middle]) / 2).round();
}
