import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/cycle_prediction.dart';

void main() {
  group('predictCycles', () {
    test('uses the median and calendar-day interval across leap day', () {
      final prediction = predictCycles(
        periods: [
          PeriodRecord(start: DateTime(2024, 1, 1), end: DateTime(2024, 1, 5)),
          PeriodRecord(start: DateTime(2024, 1, 29)),
          PeriodRecord(start: DateTime(2024, 2, 26)),
          PeriodRecord(start: DateTime(2024, 3, 25)),
        ],
        mode: CycleMode.general,
        configuredCycleLength: null,
        configuredPeriodLength: null,
        fertilityEstimatesEnabled: true,
      );

      expect(prediction.medianCycleLength, 28);
      expect(prediction.mad, 0);
      expect(prediction.sampleSize, 3);
      expect(prediction.shortestObservedCycle, 28);
      expect(prediction.longestObservedCycle, 28);
      expect(prediction.explanation, contains('最近 3 個週期間隔'));
      expect(prediction.nextStarts, hasLength(6));
      expect(prediction.nextStarts.first.earliest, DateTime.utc(2024, 4, 22));
      expect(prediction.estimatedPeriodLength, 5);
      expect(prediction.canEstimateFertility, isTrue);
      expect(
        prediction.estimatedOvulationWindows.first.earliest,
        DateTime.utc(2024, 4, 8),
      );
      expect(
        prediction.estimatedFertileWindows.first.earliest,
        DateTime.utc(2024, 4, 3),
      );
      expect(
        prediction.estimatedFertileWindows.first.latest,
        DateTime.utc(2024, 4, 9),
      );
    });

    test('uses a broad historical range for variable cycles', () {
      final prediction = predictCycles(
        periods: [
          PeriodRecord(start: DateTime(2025, 1, 1)),
          PeriodRecord(start: DateTime(2025, 1, 25)),
          PeriodRecord(start: DateTime(2025, 2, 27)),
          PeriodRecord(start: DateTime(2025, 3, 23)),
        ],
        mode: CycleMode.irregular,
        configuredCycleLength: 28,
        configuredPeriodLength: 5,
        fertilityEstimatesEnabled: true,
      );

      expect(prediction.support, PredictionSupport.variable);
      expect(prediction.shortestObservedCycle, 24);
      expect(prediction.longestObservedCycle, 33);
      expect(prediction.explanation, contains('24–33 天'));
      expect(prediction.nextStarts.first.earliest, DateTime.utc(2025, 4, 16));
      expect(prediction.nextStarts.first.latest, DateTime.utc(2025, 4, 25));
      expect(prediction.canEstimateFertility, isFalse);
    });

    test(
      'only offers one provisional estimate with configured cycle length',
      () {
        final prediction = predictCycles(
          periods: [PeriodRecord(start: DateTime(2025, 12, 20))],
          mode: CycleMode.general,
          configuredCycleLength: 30,
          configuredPeriodLength: null,
          fertilityEstimatesEnabled: true,
        );

        expect(prediction.support, PredictionSupport.provisional);
        expect(prediction.usesConfiguredCycleLength, isTrue);
        expect(prediction.explanation, contains('設定的 30 天週期'));
        expect(prediction.nextStarts, hasLength(1));
        expect(
          prediction.nextStarts.single.earliest,
          DateTime.utc(2026, 1, 19),
        );
        expect(prediction.canEstimateFertility, isFalse);
      },
    );

    test('one historical interval supports only a provisional estimate', () {
      final prediction = predictCycles(
        periods: [
          PeriodRecord(start: DateTime(2025, 1, 1)),
          PeriodRecord(start: DateTime(2025, 2, 3)),
        ],
        mode: CycleMode.general,
        configuredCycleLength: null,
        configuredPeriodLength: null,
        fertilityEstimatesEnabled: false,
      );

      expect(prediction.support, PredictionSupport.provisional);
      expect(prediction.medianCycleLength, 33);
      expect(prediction.nextStarts, hasLength(1));
      expect(prediction.nextStarts.single.earliest, DateTime.utc(2025, 3, 8));
    });

    test('does not use a natural cycle model in other tracking modes', () {
      for (final mode in [
        CycleMode.hormonalContraception,
        CycleMode.pregnancy,
        CycleMode.postpartum,
        CycleMode.trackingOnly,
      ]) {
        final prediction = predictCycles(
          periods: [
            PeriodRecord(start: DateTime(2025, 1, 1)),
            PeriodRecord(start: DateTime(2025, 1, 29)),
            PeriodRecord(start: DateTime(2025, 2, 26)),
            PeriodRecord(start: DateTime(2025, 3, 26)),
          ],
          mode: mode,
          configuredCycleLength: 28,
          configuredPeriodLength: 5,
          fertilityEstimatesEnabled: true,
        );

        expect(prediction.canEstimateFertility, isFalse);
        expect(prediction.nextStarts, isEmpty);
        expect(prediction.support, PredictionSupport.notApplicable);
      }
    });

    test('prediction can be explicitly disabled', () {
      final prediction = predictCycles(
        periods: [
          PeriodRecord(start: DateTime(2025, 1, 1)),
          PeriodRecord(start: DateTime(2025, 1, 29)),
          PeriodRecord(start: DateTime(2025, 2, 26)),
          PeriodRecord(start: DateTime(2025, 3, 26)),
        ],
        mode: CycleMode.general,
        configuredCycleLength: 28,
        configuredPeriodLength: 5,
        fertilityEstimatesEnabled: true,
        predictionEnabled: false,
      );

      expect(prediction.support, PredictionSupport.disabled);
      expect(prediction.nextStarts, isEmpty);
      expect(prediction.canEstimateFertility, isFalse);
    });
  });
}
