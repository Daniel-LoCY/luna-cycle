import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/dashboard/dashboard_screen.dart';

void main() {
  testWidgets('empty dashboard explains how to begin and offers real actions', (
    tester,
  ) async {
    await initializeDateFormatting('zh_TW');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          periodsProvider.overrideWith((ref) => Stream.value(<Period>[])),
          dailyLogsProvider.overrideWith((ref) => Stream.value(<DailyLog>[])),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('今天，照顧好自己'), findsOneWidget);
    expect(find.text('今天先留一筆給自己'), findsOneWidget);
    expect(find.text('開始／結束月經'), findsOneWidget);
    expect(find.byTooltip('記錄今天狀態'), findsOneWidget);
  });
}
