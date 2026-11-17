import 'cycle_prediction.dart';

class DailySymptomLog {
  const DailySymptomLog({required this.day, required this.symptoms});

  final DateTime day;
  final List<String> symptoms;
}

enum CycleSymptomPhase { menstruation, early, middle, late }

extension CycleSymptomPhaseLabel on CycleSymptomPhase {
  String get label => switch (this) {
    CycleSymptomPhase.menstruation => '月經期（第 1–5 天）',
    CycleSymptomPhase.early => '週期前段（第 6–12 天）',
    CycleSymptomPhase.middle => '週期中段（第 13–16 天）',
    CycleSymptomPhase.late => '週期後段（第 17 天起）',
  };
}

class CycleSymptomPattern {
  const CycleSymptomPattern({
    required this.symptom,
    required this.phase,
    required this.cycleCount,
    required this.recordCount,
  });

  final String symptom;
  final CycleSymptomPhase phase;
  final int cycleCount;
  final int recordCount;
}

/// Summarizes only recurring symptom entries in natural cycle tracking modes.
/// A pattern is surfaced when the same symptom appears in the same phase in at
/// least two distinct recorded cycles and that phase is the unique leader.
List<CycleSymptomPattern> summarizeCycleSymptoms({
  required List<PeriodRecord> periods,
  required List<DailySymptomLog> logs,
  required CycleMode mode,
}) {
  if (mode != CycleMode.general &&
      mode != CycleMode.irregular &&
      mode != CycleMode.tryingToConceive) {
    return const [];
  }
  final starts = periods.map((period) => _day(period.start)).toList()..sort();
  final uniqueStarts = <DateTime>[];
  for (final start in starts) {
    if (uniqueStarts.isEmpty || !_sameDay(uniqueStarts.last, start)) {
      uniqueStarts.add(start);
    }
  }
  if (uniqueStarts.isEmpty) return const [];

  final cyclesByPhase = <String, Map<CycleSymptomPhase, Set<int>>>{};
  final recordsByPhase = <String, Map<CycleSymptomPhase, int>>{};
  for (final log in logs) {
    final day = _day(log.day);
    var cycleIndex = -1;
    for (var index = 0; index < uniqueStarts.length; index++) {
      if (uniqueStarts[index].isAfter(day)) break;
      cycleIndex = index;
    }
    if (cycleIndex < 0) continue;
    final cycleDay = day.difference(uniqueStarts[cycleIndex]).inDays + 1;
    final phase = _phaseFor(cycleDay);
    for (final symptom in log.symptoms.toSet()) {
      final phaseCycles = cyclesByPhase.putIfAbsent(
        symptom,
        () => <CycleSymptomPhase, Set<int>>{},
      );
      phaseCycles.putIfAbsent(phase, () => <int>{}).add(cycleIndex);
      final phaseRecords = recordsByPhase.putIfAbsent(
        symptom,
        () => <CycleSymptomPhase, int>{},
      );
      phaseRecords.update(phase, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  final result = <CycleSymptomPattern>[];
  for (final entry in cyclesByPhase.entries) {
    final phases = entry.value.entries.toList()
      ..sort((left, right) => right.value.length.compareTo(left.value.length));
    if (phases.isEmpty || phases.first.value.length < 2) continue;
    if (phases.length > 1 &&
        phases.first.value.length == phases[1].value.length) {
      continue;
    }
    final phase = phases.first.key;
    result.add(
      CycleSymptomPattern(
        symptom: entry.key,
        phase: phase,
        cycleCount: phases.first.value.length,
        recordCount: recordsByPhase[entry.key]?[phase] ?? 0,
      ),
    );
  }
  result.sort((left, right) {
    final count = right.recordCount.compareTo(left.recordCount);
    return count != 0 ? count : left.symptom.compareTo(right.symptom);
  });
  return List.unmodifiable(result);
}

CycleSymptomPhase _phaseFor(int cycleDay) => switch (cycleDay) {
  <= 5 => CycleSymptomPhase.menstruation,
  <= 12 => CycleSymptomPhase.early,
  <= 16 => CycleSymptomPhase.middle,
  _ => CycleSymptomPhase.late,
};

DateTime _day(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
