import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';

void main() {
  late AppDatabase database;
  late CycleRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CycleRepository(database);
  });

  tearDown(() async => database.close());

  test(
    'records a period, rejects a second active period, and closes the first',
    () async {
      final started = await repository.startPeriod(DateTime.utc(2025, 3, 1));
      expect(
        [
          started.startDate.year,
          started.startDate.month,
          started.startDate.day,
        ],
        [2025, 3, 1],
      );
      await expectLater(
        repository.startPeriod(DateTime.utc(2025, 3, 2)),
        throwsA(isA<StateError>()),
      );

      await repository.endActivePeriod(DateTime.utc(2025, 3, 5));
      final periods = await repository.getPeriods();
      expect(periods, hasLength(1));
      expect(
        [
          periods.single.endDate!.year,
          periods.single.endDate!.month,
          periods.single.endDate!.day,
        ],
        [2025, 3, 5],
      );
    },
  );

  test('daily edits preserve the stable id and increase the version', () async {
    final day = DateTime.utc(2025, 4, 11);
    await repository.saveDailyLog(day: day, symptoms: ['頭痛']);
    final first = await database.select(database.dailyLogs).getSingle();

    await repository.saveDailyLog(day: day, symptoms: ['經痛'], painLevel: 4);
    final edited = await database.select(database.dailyLogs).getSingle();

    expect(edited.id, first.id);
    expect(edited.version, first.version + 1);
    expect(edited.symptomsJson, '["經痛"]');
    expect(edited.painLevel, 4);
  });

  test('quick edits preserve journal fields and can be undone', () async {
    final day = DateTime.utc(2025, 4, 12);
    await repository.saveDailyLog(
      day: day,
      symptoms: ['頭痛'],
      moods: ['平靜'],
      body: {'sleepHours': 8},
      medications: ['鐵劑'],
      note: '原本日記',
    );
    final previous = await repository.getDailyLog(day);

    final saved = await repository.saveQuickLog(
      day: day,
      painLevel: 5,
      flow: '中',
      moods: ['焦慮'],
    );

    expect(saved.id, previous!.id);
    expect(saved.version, previous.version + 1);
    expect(saved.painLevel, 5);
    expect(saved.flow, '中');
    expect(saved.moodsJson, '["焦慮"]');
    expect(saved.symptomsJson, previous.symptomsJson);
    expect(saved.bodyJson, previous.bodyJson);
    expect(saved.medicationJson, previous.medicationJson);
    expect(saved.note, previous.note);

    await repository.restoreQuickLog(
      day: day,
      previous: previous,
      expectedVersion: saved.version,
    );
    final restored = await repository.getDailyLog(day);
    expect(restored!.id, previous.id);
    expect(restored.version, saved.version + 1);
    expect(restored.painLevel, isNull);
    expect(restored.flow, isNull);
    expect(restored.moodsJson, '["平靜"]');
    expect(restored.note, '原本日記');
  });

  test('quick log undo tombstones a new row and rejects stale undo', () async {
    final day = DateTime.utc(2025, 4, 13);
    final saved = await repository.saveQuickLog(
      day: day,
      painLevel: 2,
      flow: '少',
      moods: ['平靜'],
    );
    await repository.restoreQuickLog(
      day: day,
      previous: null,
      expectedVersion: saved.version,
    );
    expect(await repository.getDailyLog(day), isNull);
    final tombstone = await database.select(database.dailyLogs).getSingle();
    expect(tombstone.id, saved.id);
    expect(tombstone.deletedAt, isNotNull);

    final restored = await repository.saveQuickLog(
      day: day,
      painLevel: 3,
      flow: '中',
      moods: ['開心'],
    );
    await repository.saveDailyLog(day: day, note: '較新的編輯');
    await expectLater(
      repository.restoreQuickLog(
        day: day,
        previous: null,
        expectedVersion: restored.version,
      ),
      throwsA(isA<StateError>()),
    );
    expect((await repository.getDailyLog(day))!.note, '較新的編輯');
  });

  test(
    'daily flow, spotting, and clots are stored as actual record fields',
    () async {
      await repository.saveDailyLog(
        day: DateTime.utc(2025, 4, 11),
        flow: '中',
        spotting: true,
        clots: true,
      );
      final log = await database.select(database.dailyLogs).getSingle();

      expect(log.flow, '中');
      expect(log.spotting, isTrue);
      expect(log.clots, isTrue);
    },
  );

  test('invalid pain score is rejected before writing', () async {
    await expectLater(
      repository.saveDailyLog(day: DateTime.utc(2025, 4, 11), painLevel: 11),
      throwsRangeError,
    );
    expect(await database.select(database.dailyLogs).get(), isEmpty);
  });

  test('period updates preserve id and reject overlaps', () async {
    final original = await repository.savePeriod(
      startDate: DateTime.utc(2025, 5, 1),
      endDate: DateTime.utc(2025, 5, 5),
      flow: '中',
    );
    final edited = await repository.updatePeriod(
      id: original.id,
      startDate: DateTime.utc(2025, 5, 2),
      endDate: DateTime.utc(2025, 5, 6),
      flow: '多',
    );

    expect(edited.id, original.id);
    expect(edited.version, original.version + 1);
    expect(edited.flow, '多');
    await expectLater(
      repository.savePeriod(
        startDate: DateTime.utc(2025, 5, 6),
        endDate: DateTime.utc(2025, 5, 8),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('deleting a daily log leaves a versioned tombstone', () async {
    await repository.saveDailyLog(day: DateTime.utc(2025, 4, 11));
    final log = await database.select(database.dailyLogs).getSingle();
    await repository.softDeleteDailyLog(log.id);

    final tombstone = await (database.select(
      database.dailyLogs,
    )..where((row) => row.id.equals(log.id))).getSingle();
    expect(tombstone.deletedAt, isNotNull);
    expect(tombstone.version, log.version + 1);
    expect(await repository.watchDailyLogs().first, isEmpty);
  });

  test(
    'medication schedules and intake entries use versioned local CRUD',
    () async {
      final scheduleId = await repository.saveMedicationSchedule(
        label: '鐵劑',
        dosage: '1 顆',
        times: ['20:00', '08:00'],
        enabled: true,
      );
      final schedule = (await repository.getMedicationSchedules()).single;
      expect(schedule.id, scheduleId);
      expect(schedule.timesJson, '["08:00","20:00"]');

      final day = DateTime.utc(2026, 5, 7);
      final firstId = await repository.saveMedicationIntake(
        scheduleId: scheduleId,
        scheduleLabel: '鐵劑',
        scheduledDay: day,
        scheduledTime: '08:00',
        status: 'taken',
      );
      final first = (await repository.getMedicationIntakes()).single;
      expect(first.id, firstId);
      expect(first.status, 'taken');
      expect(first.takenAt, isNotNull);

      final editedId = await repository.saveMedicationIntake(
        scheduleId: scheduleId,
        scheduleLabel: '鐵劑',
        scheduledDay: day,
        scheduledTime: '08:00',
        status: 'skipped',
      );
      final edited = (await repository.getMedicationIntakes()).single;
      expect(editedId, firstId);
      expect(edited.version, first.version + 1);
      expect(edited.status, 'skipped');
      expect(edited.takenAt, isNull);

      await repository.softDeleteMedicationIntake(firstId);
      expect(await repository.getMedicationIntakes(), isEmpty);
      await repository.softDeleteMedicationSchedule(scheduleId);
      expect(await repository.getMedicationSchedules(), isEmpty);
      expect(
        (await repository.getMedicationSchedules(
          includeDeleted: true,
        )).single.deletedAt,
        isNotNull,
      );
      final outbox = await database.select(database.syncOutbox).get();
      expect(
        outbox.where((row) => row.entityType == 'medicationSchedule'),
        isNotEmpty,
      );
      expect(
        outbox.where((row) => row.entityType == 'medicationIntake'),
        isNotEmpty,
      );
    },
  );

  test(
    'medication schedule rejects invalid or duplicate reminder times',
    () async {
      await expectLater(
        repository.saveMedicationSchedule(
          label: '藥物',
          times: ['25:00'],
          enabled: true,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveMedicationSchedule(
          label: '藥物',
          times: ['08:00', '08:00'],
          enabled: true,
        ),
        throwsArgumentError,
      );
    },
  );

  test('recording again on a deleted day restores its stable row', () async {
    final day = DateTime.utc(2025, 4, 11);
    await repository.saveDailyLog(day: day, symptoms: ['頭痛']);
    final original = await database.select(database.dailyLogs).getSingle();
    await repository.softDeleteDailyLog(original.id);
    await repository.saveDailyLog(day: day, symptoms: ['經痛']);

    final restored = await database.select(database.dailyLogs).getSingle();
    expect(restored.id, original.id);
    expect(restored.deletedAt, isNull);
    expect(restored.version, original.version + 2);
    expect(restored.symptomsJson, '["經痛"]');
  });

  test(
    'clearing user data removes records, settings, and sync queue atomically',
    () async {
      await repository.savePeriod(startDate: DateTime.utc(2025, 4, 1));
      await repository.saveDailyLog(day: DateTime.utc(2025, 4, 2));
      await repository.saveSetting('tracking_mode', '只記錄');
      final scheduleId = await repository.saveMedicationSchedule(
        label: '補充品',
        times: ['08:00'],
        enabled: true,
      );
      await repository.saveMedicationIntake(
        scheduleId: scheduleId,
        scheduleLabel: '補充品',
        scheduledDay: DateTime.utc(2025, 4, 2),
        scheduledTime: '08:00',
        status: 'taken',
      );

      await repository.clearAllUserData();

      expect(await database.select(database.periods).get(), isEmpty);
      expect(await database.select(database.dailyLogs).get(), isEmpty);
      expect(await database.select(database.appSettings).get(), isEmpty);
      expect(await database.select(database.syncOutbox).get(), isEmpty);
      expect(
        await database.select(database.medicationSchedules).get(),
        isEmpty,
      );
      expect(
        await database.select(database.medicationIntakeEntries).get(),
        isEmpty,
      );
    },
  );
}
