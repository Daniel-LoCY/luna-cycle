import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/cycle_prediction.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';
import '../records/quick_log_sheet.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  var _month = DateTime(DateTime.now().year, DateTime.now().month);
  var _focusedDay = _calendarDay(DateTime.now());
  var _weekView = false;
  DateTimeRange? _selectedRange;

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(periodsProvider).value ?? const [];
    final logs = ref.watch(dailyLogsProvider).value ?? const [];
    final config = ref.watch(cycleConfigProvider).value ?? const CycleConfig();
    final prediction = predictCycles(
      periods: periods
          .where((period) => period.deletedAt == null)
          .map(
            (period) =>
                PeriodRecord(start: period.startDate, end: period.endDate),
          )
          .toList(),
      mode: config.mode,
      configuredCycleLength: config.averageCycleLength,
      configuredPeriodLength: config.averagePeriodLength,
      fertilityEstimatesEnabled: config.fertilityEstimatesEnabled,
      predictionEnabled: config.predictionEnabled,
    );
    final first = DateTime(_month.year, _month.month);
    final anchor = _weekView ? _focusedDay : first;
    final gridStart = anchor.subtract(Duration(days: (anchor.weekday + 6) % 7));
    final days = List.generate(
      _weekView ? 7 : 42,
      (index) => gridStart.add(Duration(days: index)),
    );
    return LunaPage(
      title: '生理日曆',
      children: [
        LunaCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: _weekView ? '上一週' : '上一個月',
                    onPressed: () => _move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: TextButton(
                        onPressed: _pickMonth,
                        child: Text(
                          DateFormat('yyyy年M月').format(_month),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _weekView ? '下一週' : '下一個月',
                    onPressed: () => _move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _focusedDay = _calendarDay(DateTime.now());
                      _month = DateTime(_focusedDay.year, _focusedDay.month);
                    }),
                    child: const Text('今天'),
                  ),
                ],
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('月')),
                  ButtonSegment(value: true, label: Text('週')),
                ],
                selected: {_weekView},
                onSelectionChanged: (values) =>
                    setState(() => _weekView = values.first),
              ),
              const SizedBox(height: 8),
              if (_selectedRange case final range?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '已選 ${DateFormat('M月d日').format(range.start)}–${DateFormat('M月d日').format(range.end)}',
                        ),
                      ),
                      IconButton(
                        tooltip: '清除日期範圍',
                        onPressed: () => setState(() => _selectedRange = null),
                        icon: const Icon(Icons.close_rounded),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(color: LunaColors.muted),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: days.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 46,
                ),
                itemBuilder: (context, index) {
                  final localDay = days[index];
                  final day = DateTime.utc(
                    localDay.year,
                    localDay.month,
                    localDay.day,
                  );
                  final inMonth = _weekView || day.month == _month.month;
                  final actual = periods.any(
                    (period) =>
                        !day.isBefore(_calendarDay(period.startDate)) &&
                        (period.endDate == null
                            ? !day.isAfter(_calendarDay(DateTime.now()))
                            : !day.isAfter(_calendarDay(period.endDate!))),
                  );
                  final periodLength = prediction.estimatedPeriodLength;
                  final predicted =
                      !actual &&
                      periodLength != null &&
                      prediction.nextStarts.any(
                        (range) =>
                            !day.isBefore(range.earliest) &&
                            !day.isAfter(
                              range.latest.add(
                                Duration(days: periodLength - 1),
                              ),
                            ),
                      );
                  final fertile = prediction.estimatedFertileWindows.any(
                    (range) =>
                        !day.isBefore(range.earliest) &&
                        !day.isAfter(range.latest),
                  );
                  final ovulation = prediction.estimatedOvulationWindows.any(
                    (range) =>
                        !day.isBefore(range.earliest) &&
                        !day.isAfter(range.latest),
                  );
                  final hasLog = logs.any(
                    (log) =>
                        log.day.year == day.year &&
                        log.day.month == day.month &&
                        log.day.day == day.day,
                  );
                  final today =
                      day.year == DateTime.now().year &&
                      day.month == DateTime.now().month &&
                      day.day == DateTime.now().day;
                  final selectedRange =
                      _selectedRange != null &&
                      !day.isBefore(_calendarDay(_selectedRange!.start)) &&
                      !day.isAfter(_calendarDay(_selectedRange!.end));
                  return Semantics(
                    button: true,
                    label:
                        '${DateFormat('M月d日').format(day)}${actual
                            ? '，實際經期'
                            : predicted
                            ? '，預測經期'
                            : ''}${ovulation ? '，預估排卵日' : ''}${fertile ? '，預估易受孕期' : ''}${hasLog ? '，有健康紀錄' : ''}${selectedRange ? '，位於所選日期範圍' : ''}',
                    hint: '點一下記錄當日；長按選擇日期範圍',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onLongPress: () => _pickRange(day),
                      onTap: () {
                        setState(() {
                          _focusedDay = day;
                          _month = DateTime(day.year, day.month);
                        });
                        showQuickLogSheet(context, ref, day);
                      },
                      child: CustomPaint(
                        foregroundPainter: predicted
                            ? _DashedCirclePainter(
                                Theme.of(context).colorScheme.secondary,
                              )
                            : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: actual
                                    ? LunaColors.pink
                                    : ovulation
                                    ? LunaColors.lavender.withValues(alpha: .75)
                                    : fertile
                                    ? LunaColors.mint.withValues(alpha: .75)
                                    : selectedRange
                                    ? LunaColors.lavender.withValues(alpha: .16)
                                    : Colors.transparent,
                                border:
                                    today ||
                                        _sameCalendarDay(day, _focusedDay) ||
                                        selectedRange
                                    ? Border.all(
                                        color: today
                                            ? LunaColors.lavender
                                            : _sameCalendarDay(day, _focusedDay)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.secondary
                                            : LunaColors.lavender,
                                        width: 1.5,
                                      )
                                    : null,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontWeight: today
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: inMonth
                                      ? null
                                      : LunaColors.muted.withValues(alpha: .45),
                                ),
                              ),
                            ),
                            if (hasLog)
                              Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: LunaColors.ink,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _Legend(color: LunaColors.pink, label: '實際經期'),
            _Legend(color: LunaColors.ink, label: '健康紀錄'),
            _Legend(color: Colors.transparent, label: '預測經期（虛線）'),
            _Legend(color: LunaColors.mint, label: '預估易受孕期'),
            _Legend(color: LunaColors.lavender, label: '預估排卵日'),
          ],
        ),
        const SizedBox(height: 12),
        Text(switch (prediction.support) {
          PredictionSupport.disabled => '週期預測已關閉，日曆只顯示實際紀錄。',
          PredictionSupport.notApplicable => '目前追蹤模式不使用一般週期預測。',
          _ when prediction.nextStarts.isEmpty =>
            '資料尚不足以產生預測。新增月經紀錄後，這裡會顯示估算日期。',
          _ =>
            prediction.canEstimateFertility
                ? '週期與排卵日期皆為粗略估算，不能作為避孕依據。'
                : '預測日期為粗略估算，可能受週期變化影響，不可作為避孕依據。',
        }),
      ],
    );
  }

  void _move(int offset) => setState(() {
    if (_weekView) {
      _focusedDay = _focusedDay.add(Duration(days: offset * 7));
      _month = DateTime(_focusedDay.year, _focusedDay.month);
    } else {
      _month = DateTime(_month.year, _month.month + offset);
      if (_focusedDay.year != _month.year ||
          _focusedDay.month != _month.month) {
        _focusedDay = DateTime(_month.year, _month.month, 1);
      }
    }
  });

  Future<void> _pickMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _focusedDay,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: '選擇要查看的月份',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _focusedDay = _calendarDay(selected);
      _month = DateTime(selected.year, selected.month);
    });
  }

  Future<void> _pickRange(DateTime anchor) async {
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: anchor, end: anchor),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: '選擇要查看的日期範圍',
      saveText: '完成',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedRange = DateTimeRange(
        start: _calendarDay(selected.start),
        end: _calendarDay(selected.end),
      );
      _focusedDay = _calendarDay(selected.start);
      _month = DateTime(selected.start.year, selected.start.month);
    });
  }
}

DateTime _calendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    for (var segment = 0; segment < 12; segment++) {
      canvas.drawArc(rect.deflate(1), segment * 0.5236, 0.28, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      color != oldDelegate.color;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: color == Colors.transparent
              ? Border.all(color: LunaColors.muted)
              : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
