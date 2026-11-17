import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/records/records_screen.dart';

void main() {
  testWidgets('records search filters actual notes and explains no matches', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = CycleRepository(database);
    await repository.saveDailyLog(
      day: DateTime(2026, 3, 12),
      symptoms: ['經痛'],
      moods: ['平靜'],
      note: '熱敷後舒服一些',
    );
    await repository.saveDailyLog(
      day: DateTime(2026, 3, 13),
      symptoms: ['頭痛'],
      note: '休息',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: Scaffold(body: RecordsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '經痛');
    await tester.pumpAndSettle();
    expect(find.text('症狀：經痛'), findsOneWidget);
    expect(find.text('症狀：頭痛'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '沒有這個詞');
    await tester.pumpAndSettle();
    expect(find.text('找不到健康紀錄'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
  });
}
