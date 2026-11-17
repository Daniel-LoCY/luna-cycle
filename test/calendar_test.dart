import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/calendar/calendar_screen.dart';

void main() {
  testWidgets('calendar switches between month and week views', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          periodsProvider.overrideWith((ref) => Stream.value(<Period>[])),
          dailyLogsProvider.overrideWith((ref) => Stream.value(<DailyLog>[])),
          cycleConfigProvider.overrideWith((ref) async => const CycleConfig()),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final dateCells = find.descendant(
      of: find.byType(GridView),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    );
    expect(dateCells, findsNWidgets(42));
    expect(find.byTooltip('上一個月'), findsOneWidget);

    await tester.tap(find.text('週'));
    await tester.pumpAndSettle();

    expect(dateCells, findsNWidgets(7));
    expect(find.byTooltip('上一週'), findsOneWidget);
  });

  testWidgets('calendar opens a date range selector on long press', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          periodsProvider.overrideWith((ref) => Stream.value(<Period>[])),
          dailyLogsProvider.overrideWith((ref) => Stream.value(<DailyLog>[])),
          cycleConfigProvider.overrideWith((ref) async => const CycleConfig()),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final dateCells = find.descendant(
      of: find.byType(GridView),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    );
    await tester.longPress(dateCells.first);
    await tester.pumpAndSettle();

    expect(find.text('選擇要查看的日期範圍'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已選 '), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.contains('位於所選日期範圍') == true,
      ),
      findsOneWidget,
    );
  });
}
