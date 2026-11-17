import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/cycle_prediction.dart';
import 'package:luna_cycle/core/data_management/health_report_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'builds a Traditional Chinese report with actual and estimated data',
    () async {
      final fontData = await rootBundle.load('assets/fonts/NotoSansTC-VF.ttf');
      final prediction = predictCycles(
        periods: [
          PeriodRecord(start: DateTime(2026, 4, 1), end: DateTime(2026, 4, 5)),
          PeriodRecord(start: DateTime(2026, 4, 29), end: DateTime(2026, 5, 3)),
          PeriodRecord(
            start: DateTime(2026, 5, 27),
            end: DateTime(2026, 5, 31),
          ),
          PeriodRecord(
            start: DateTime(2026, 6, 24),
            end: DateTime(2026, 6, 28),
          ),
        ],
        mode: CycleMode.general,
        configuredCycleLength: 28,
        configuredPeriodLength: 5,
        fertilityEstimatesEnabled: false,
      );
      final report = await HealthReportPdfService().generate(
        fontBytes: Uint8List.sublistView(fontData),
        export: {
          'data': {
            'periods': [
              {
                'startDate': '2026-04-01T00:00:00.000Z',
                'endDate': '2026-04-05T00:00:00.000Z',
                'flow': 'medium',
              },
            ],
            'dailyLogs': [
              {
                'day': '2026-04-02T00:00:00.000Z',
                'painLevel': 4,
                'symptomsJson': jsonEncode(['經痛']),
                'moodsJson': jsonEncode(['平靜']),
              },
            ],
          },
        },
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 6, 30),
        prediction: prediction,
      );

      expect(utf8.decode(report.sublist(0, 4)), '%PDF');
      expect(report.length, greaterThan(10 * 1024));

      final clinicianReport = await HealthReportPdfService().generate(
        fontBytes: Uint8List.sublistView(fontData),
        export: {
          'data': {
            'periods': [
              {
                'startDate': '2026-04-01T00:00:00.000Z',
                'endDate': '2026-04-05T00:00:00.000Z',
                'flow': 'medium',
              },
            ],
            'dailyLogs': [
              {
                'day': '2026-04-02T00:00:00.000Z',
                'painLevel': 4,
                'symptomsJson': jsonEncode(['經痛']),
                'moodsJson': jsonEncode(['平靜']),
                'medicationJson': jsonEncode(['止痛藥']),
                'note': '晚間較明顯',
              },
            ],
            'medicationIntakes': [
              {
                'scheduledDay': '2026-04-02T00:00:00.000Z',
                'scheduleLabel': '鐵劑',
                'scheduledTime': '08:00',
                'status': 'taken',
              },
              {
                'scheduledDay': '2026-04-02T00:00:00.000Z',
                'scheduleLabel': '維他命',
                'scheduledTime': '20:00',
                'status': 'skipped',
              },
            ],
          },
        },
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 6, 30),
        prediction: prediction,
        clinicianSummary: true,
      );
      expect(utf8.decode(clinicianReport.sublist(0, 4)), '%PDF');
      expect(clinicianReport.length, greaterThan(report.length));
    },
  );
}
