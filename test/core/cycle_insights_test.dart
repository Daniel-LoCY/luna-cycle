import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/cycle_insights.dart';
import 'package:luna_cycle/core/cycle_prediction.dart';

void main() {
  test('shows repeat symptoms by cycle phase only across multiple cycles', () {
    final patterns = summarizeCycleSymptoms(
      periods: [
        PeriodRecord(start: DateTime(2026, 1, 1)),
        PeriodRecord(start: DateTime(2026, 2, 1)),
        PeriodRecord(start: DateTime(2026, 3, 1)),
      ],
      logs: [
        DailySymptomLog(day: DateTime(2026, 1, 9), symptoms: ['頭痛']),
        DailySymptomLog(day: DateTime(2026, 1, 26), symptoms: ['經痛']),
        DailySymptomLog(day: DateTime(2026, 2, 9), symptoms: ['頭痛']),
        DailySymptomLog(day: DateTime(2026, 2, 25), symptoms: ['經痛']),
        DailySymptomLog(day: DateTime(2026, 3, 9), symptoms: ['偶發']),
      ],
      mode: CycleMode.general,
    );

    expect(patterns, hasLength(2));
    expect(
      patterns.singleWhere((pattern) => pattern.symptom == '頭痛').phase,
      CycleSymptomPhase.early,
    );
    expect(
      patterns.singleWhere((pattern) => pattern.symptom == '經痛').phase,
      CycleSymptomPhase.late,
    );
    expect(patterns.every((pattern) => pattern.cycleCount == 2), isTrue);
  });

  test(
    'does not infer patterns for incompatible tracking modes or tied phases',
    () {
      final periods = [
        PeriodRecord(start: DateTime(2026, 1, 1)),
        PeriodRecord(start: DateTime(2026, 2, 1)),
        PeriodRecord(start: DateTime(2026, 3, 1)),
      ];
      final tied = [
        DailySymptomLog(day: DateTime(2026, 1, 3), symptoms: ['不舒服']),
        DailySymptomLog(day: DateTime(2026, 2, 20), symptoms: ['不舒服']),
      ];
      expect(
        summarizeCycleSymptoms(
          periods: periods,
          logs: tied,
          mode: CycleMode.general,
        ),
        isEmpty,
      );
      expect(
        summarizeCycleSymptoms(
          periods: periods,
          logs: [
            DailySymptomLog(day: DateTime(2026, 1, 5), symptoms: ['經痛']),
            DailySymptomLog(day: DateTime(2026, 2, 5), symptoms: ['經痛']),
          ],
          mode: CycleMode.hormonalContraception,
        ),
        isEmpty,
      );
    },
  );
}
