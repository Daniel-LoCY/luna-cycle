import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/analysis/analysis_screen.dart';

void main() {
  late AppDatabase database;
  late CycleRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CycleRepository(database);
  });
  tearDown(() async => database.close());

  testWidgets('analysis charts are built from saved user records', (
    tester,
  ) async {
    final secondStart = DateTime.now().subtract(const Duration(days: 28));
    final firstStart = secondStart.subtract(const Duration(days: 28));
    await repository.startPeriod(firstStart);
    await repository.endActivePeriod(firstStart.add(const Duration(days: 4)));
    await repository.startPeriod(secondStart);
    await repository.endActivePeriod(secondStart.add(const Duration(days: 4)));
    await repository.saveDailyLog(
      day: DateTime.now(),
      painLevel: 4,
      flow: '中',
      symptoms: ['痘痘', '經痛'],
      moods: ['平靜'],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: AnalysisScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('平均週期'), findsOneWidget);
    expect(find.text('週期長度'), findsOneWidget);
    expect(find.text('經期天數'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('常見症狀'),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('常見症狀'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('情緒分布'),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('情緒分布'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('疼痛趨勢'),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
