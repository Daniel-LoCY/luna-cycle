import 'dart:math' as math;

/// Immutable completed period used by the cycle prediction engine.
class PeriodRecord {
  const PeriodRecord({required this.start, this.end});

  final DateTime start;
  final DateTime? end;
}

enum CycleMode {
  general,
  irregular,
  tryingToConceive,
  hormonalContraception,
  pregnancy,
  postpartum,
  trackingOnly,
}

enum PredictionSupport {
  insufficient,
  provisional,
  variable,
  steady,
  disabled,
  notApplicable,
}

class CyclePrediction {
  const CyclePrediction({
    required this.support,
    required this.medianCycleLength,
    required this.mad,
    required this.estimatedPeriodLength,
    required this.sampleSize,
    required this.shortestObservedCycle,
    required this.longestObservedCycle,
    required this.usesConfiguredCycleLength,
    required this.nextStarts,
    required this.estimatedOvulationWindows,
    required this.estimatedFertileWindows,
    required this.canEstimateFertility,
  });

  final PredictionSupport support;
  final int? medianCycleLength;
  final int? mad;
  final List<DateRange> nextStarts;
  final List<DateRange> estimatedOvulationWindows;
  final List<DateRange> estimatedFertileWindows;
  final int? estimatedPeriodLength;
  final int sampleSize;
  final int? shortestObservedCycle;
  final int? longestObservedCycle;
  final bool usesConfiguredCycleLength;
  final bool canEstimateFertility;

  bool get hasEnoughHistory => medianCycleLength != null;

  String get explanation => switch (support) {
    PredictionSupport.disabled => '週期預測已關閉；已記錄資料仍保留。',
    PredictionSupport.notApplicable => '目前的追蹤模式不使用一般自然週期模型。',
    PredictionSupport.insufficient => '目前沒有可用的週期間隔，因此不顯示日期預測。',
    PredictionSupport.provisional when usesConfiguredCycleLength =>
      '目前使用你設定的 ${medianCycleLength ?? '平均'} 天週期作單次初步估算，尚無完整週期間隔可參考。',
    PredictionSupport.provisional =>
      '目前只參考最近 $sampleSize 個完整週期間隔，以其中位數 ${medianCycleLength ?? '—'} 天作單次初步估算。',
    PredictionSupport.variable =>
      '參考最近 $sampleSize 個週期間隔：${shortestObservedCycle ?? '—'}–${longestObservedCycle ?? '—'} 天，中位數 ${medianCycleLength ?? '—'} 天；變化較大，因此顯示較寬的估算範圍。',
    PredictionSupport.steady =>
      '參考最近 $sampleSize 個週期間隔，中位數 ${medianCycleLength ?? '—'} 天；近期變化較小，但日期仍是估算。',
  };
}

class DateRange {
  const DateRange(this.earliest, this.latest);

  final DateTime earliest;
  final DateTime latest;
}

/// Estimates future menstruation from actual start dates only.
///
/// Dates are reduced to local calendar dates before arithmetic. It uses at
/// most six available completed cycle intervals and does not silently remove
/// outliers. The median of one or two intervals supports a clearly provisional
/// single estimate; at least three are needed for multiple forecasts.
CyclePrediction predictCycles({
  required List<PeriodRecord> periods,
  required CycleMode mode,
  required int? configuredCycleLength,
  required int? configuredPeriodLength,
  required bool fertilityEstimatesEnabled,
  bool predictionEnabled = true,
  int forecastCount = 6,
}) {
  if (forecastCount < 0 || forecastCount > 12) {
    throw ArgumentError.value(forecastCount, 'forecastCount', 'must be 0–12');
  }

  final starts = periods.map((period) => _day(period.start)).toList()..sort();
  final uniqueStarts = <DateTime>[];
  for (final start in starts) {
    if (uniqueStarts.isEmpty || !_sameDay(uniqueStarts.last, start)) {
      uniqueStarts.add(start);
    }
  }

  final intervals = <int>[];
  for (var index = 1; index < uniqueStarts.length; index++) {
    final days = uniqueStarts[index].difference(uniqueStarts[index - 1]).inDays;
    if (days > 0) intervals.add(days);
  }
  final recent = intervals.length <= 6
      ? intervals
      : intervals.sublist(intervals.length - 6);
  final median = _median(recent);
  final mad = median == null
      ? null
      : _median(recent.map((value) => (value - median).abs()).toList());
  final spread = recent.isEmpty
      ? null
      : recent.reduce(math.max) - recent.reduce(math.min);

  final effectiveLength = recent.isNotEmpty ? median : configuredCycleLength;
  final reference = uniqueStarts.isEmpty ? null : uniqueStarts.last;
  final forecast = <DateRange>[];
  final modeSupportsCyclePrediction =
      mode == CycleMode.general ||
      mode == CycleMode.irregular ||
      mode == CycleMode.tryingToConceive;
  final forecastLimit = recent.length < 3 && effectiveLength != null
      ? math.min(1, forecastCount)
      : forecastCount;
  if (predictionEnabled &&
      modeSupportsCyclePrediction &&
      effectiveLength != null &&
      reference != null) {
    var center = reference;
    for (var index = 0; index < forecastLimit; index++) {
      final int low;
      final int high;
      if (recent.length >= 3) {
        low = recent.reduce(math.min);
        high = recent.reduce(math.max);
      } else {
        low = effectiveLength;
        high = effectiveLength;
      }
      forecast.add(DateRange(_addDays(center, low), _addDays(center, high)));
      center = _addDays(center, effectiveLength);
    }
  }

  final completedBleeds = periods
      .where((period) => period.end != null)
      .map(
        (period) => _day(period.end!).difference(_day(period.start)).inDays + 1,
      )
      .where((length) => length > 0)
      .toList();
  final periodLength = _median(completedBleeds) ?? configuredPeriodLength;
  final support = !predictionEnabled
      ? PredictionSupport.disabled
      : !modeSupportsCyclePrediction
      ? PredictionSupport.notApplicable
      : switch (recent.length) {
          0 when effectiveLength != null => PredictionSupport.provisional,
          0 => PredictionSupport.insufficient,
          1 || 2 => PredictionSupport.provisional,
          _
              when recent.length >= 6 &&
                  mad != null &&
                  mad <= 2 &&
                  spread! <= 7 =>
            PredictionSupport.steady,
          _ => PredictionSupport.variable,
        };
  final modeSupportsFertility =
      mode == CycleMode.general || mode == CycleMode.tryingToConceive;
  final canEstimateFertility =
      predictionEnabled &&
      fertilityEstimatesEnabled &&
      modeSupportsFertility &&
      recent.length >= 3 &&
      mad != null &&
      mad <= 2 &&
      spread != null &&
      spread <= 7;
  final ovulationWindows = canEstimateFertility
      ? forecast
            .map(
              (range) => DateRange(
                _addDays(range.earliest, -14),
                _addDays(range.latest, -14),
              ),
            )
            .toList()
      : const <DateRange>[];
  final fertileWindows = canEstimateFertility
      ? forecast
            .map(
              (range) => DateRange(
                _addDays(range.earliest, -19),
                _addDays(range.latest, -13),
              ),
            )
            .toList()
      : const <DateRange>[];

  return CyclePrediction(
    support: support,
    medianCycleLength: effectiveLength,
    mad: mad,
    estimatedPeriodLength: periodLength,
    sampleSize: recent.length,
    shortestObservedCycle: recent.isEmpty ? null : recent.reduce(math.min),
    longestObservedCycle: recent.isEmpty ? null : recent.reduce(math.max),
    usesConfiguredCycleLength: recent.isEmpty && configuredCycleLength != null,
    nextStarts: List.unmodifiable(forecast),
    estimatedOvulationWindows: List.unmodifiable(ovulationWindows),
    estimatedFertileWindows: List.unmodifiable(fertileWindows),
    canEstimateFertility: canEstimateFertility,
  );
}

int? _median(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

DateTime _day(DateTime date) => DateTime.utc(date.year, date.month, date.day);
DateTime _addDays(DateTime date, int days) =>
    DateTime.utc(date.year, date.month, date.day + days);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
