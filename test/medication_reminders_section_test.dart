import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/notifications/local_reminder_service.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/settings/medication_reminders_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async => database.close());

  testWidgets('creates a repeat schedule and records an intake', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          localReminderServiceProvider.overrideWithValue(
            _FakeReminderService(database),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MedicationRemindersSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增每日藥物提醒'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '鐵劑');
    await tester.enterText(find.byType(TextFormField).last, '1 顆');
    await tester.tap(find.text('儲存提醒'));
    await tester.pumpAndSettle();

    final schedules = await database.select(database.medicationSchedules).get();
    expect(schedules, hasLength(1));
    expect(schedules.single.label, '鐵劑');
    expect(schedules.single.enabled, isTrue);
    expect(find.text('鐵劑'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, '已服用').first);
    await tester.pumpAndSettle();
    final intakes = await database
        .select(database.medicationIntakeEntries)
        .get();
    expect(intakes, hasLength(1));
    expect(intakes.single.status, 'taken');
    expect(intakes.single.takenAt, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _FakeReminderService extends LocalReminderService {
  _FakeReminderService(super.database);

  @override
  Future<void> rescheduleSafely() async {}
}
