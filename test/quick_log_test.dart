import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/records/quick_log_sheet.dart';
import 'package:luna_cycle/features/records/quick_status_sheet.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => database.close());

  testWidgets('quick log saves symptoms and daily menstrual details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showQuickLogSheet(context, ref, DateTime(2025, 4, 11)),
                child: const Text('新增記錄'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增記錄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('經痛'));
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '自訂症狀，以頓號分隔',
      ),
      '皮膚乾燥',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('經血與出血'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('儲存紀錄'));
    await tester.tap(find.text('儲存紀錄'));
    await tester.pumpAndSettle();

    final log = await database.select(database.dailyLogs).getSingle();
    expect(log.day.year, 2025);
    expect(log.day.month, 4);
    expect(log.day.day, 11);
    expect(log.symptomsJson, '["經痛","皮膚乾燥"]');
    expect(log.flow, '中');
  });

  testWidgets(
    'home quick status edits only selected fields and can be undone',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final day = DateTime.utc(2025, 4, 11);
      await CycleRepository(database).saveDailyLog(
        day: day,
        symptoms: ['頭痛'],
        moods: ['平靜'],
        body: {'sleepHours': 8},
        note: '完整日記保留',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) => Scaffold(
                body: TextButton(
                  onPressed: () => showQuickStatusSheet(context, ref, day),
                  child: const Text('快速記錄'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('快速記錄'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '多'));
      await tester.tap(find.widgetWithText(FilterChip, '焦慮'));
      await tester.tap(find.text('儲存快速紀錄'));
      await tester.pumpAndSettle();

      var log = (await database.select(database.dailyLogs).getSingle());
      expect(log.flow, '多');
      expect(log.moodsJson, '["平靜","焦慮"]');
      expect(log.symptomsJson, '["頭痛"]');
      expect(log.bodyJson, '{"sleepHours":8}');
      expect(log.note, '完整日記保留');
      expect(find.text('撤銷'), findsOneWidget);

      await tester.tap(find.text('撤銷'));
      await tester.pumpAndSettle();
      log = (await database.select(database.dailyLogs).getSingle());
      expect(log.flow, isNull);
      expect(log.moodsJson, '["平靜"]');
      expect(log.note, '完整日記保留');
    },
  );
}
