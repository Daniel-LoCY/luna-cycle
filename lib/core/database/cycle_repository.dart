import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

class CycleRepository {
  CycleRepository(this.database);

  final AppDatabase database;
  static const _uuid = Uuid();

  Stream<List<Period>> watchPeriods() =>
      (database.select(database.periods)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.desc(row.startDate)]))
          .watch();

  Stream<List<DailyLog>> watchDailyLogs({DateTime? from, DateTime? to}) {
    final query = database.select(database.dailyLogs)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            (from == null
                ? const Constant(true)
                : row.day.isBiggerOrEqualValue(_day(from))) &
            (to == null
                ? const Constant(true)
                : row.day.isSmallerOrEqualValue(_day(to))),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.day)]);
    return query.watch();
  }

  Future<DailyLog?> getDailyLog(DateTime day) =>
      (database.select(
            database.dailyLogs,
          )..where((row) => row.day.equals(_day(day)) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<void> saveSetting(String key, String value) async {
    _validateText(key, 'setting key', maxLength: 100);
    _validateText(value, 'setting value', maxLength: 1000);
    final now = DateTime.now().toUtc();
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(now),
          ),
        );
  }

  Future<String?> getSetting(String key) async => (await (database.select(
    database.appSettings,
  )..where((setting) => setting.key.equals(key))).getSingleOrNull())?.value;

  Future<Map<String, String>> getSettings() async {
    final rows = await database.select(database.appSettings).get();
    return {for (final row in rows) row.key: row.value};
  }

  Stream<List<MedicationSchedule>> watchMedicationSchedules() =>
      (database.select(database.medicationSchedules)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.label)]))
          .watch();

  Future<List<MedicationSchedule>> getMedicationSchedules({
    bool includeDeleted = false,
  }) =>
      (database.select(database.medicationSchedules)
            ..where(
              (row) => includeDeleted
                  ? const Constant(true)
                  : row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.label)]))
          .get();

  Future<String> saveMedicationSchedule({
    String? id,
    required String label,
    String? dosage,
    required List<String> times,
    required bool enabled,
  }) async {
    _validateText(label, 'medication label', maxLength: 100);
    _validateText(dosage, 'medication dosage', maxLength: 100);
    if (times.isEmpty || times.length > 8) {
      throw ArgumentError('藥物提醒每天需設定 1 至 8 個時間。');
    }
    final normalizedTimes = times.toSet().toList()..sort();
    if (normalizedTimes.length != times.length ||
        normalizedTimes.any((time) => !_isTime(time))) {
      throw ArgumentError('提醒時間格式錯誤或重複。');
    }
    final now = DateTime.now().toUtc();
    final scheduleId = id ?? _uuid.v4();
    final existing = await (database.select(
      database.medicationSchedules,
    )..where((row) => row.id.equals(scheduleId))).getSingleOrNull();
    if (id != null && existing == null) throw StateError('找不到要編輯的藥物提醒。');

    if (existing == null) {
      await database
          .into(database.medicationSchedules)
          .insert(
            MedicationSchedulesCompanion.insert(
              id: Value(scheduleId),
              label: label.trim(),
              dosage: Value(_blankToNull(dosage)),
              timesJson: Value(jsonEncode(normalizedTimes)),
              enabled: Value(enabled),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (database.update(
        database.medicationSchedules,
      )..where((row) => row.id.equals(scheduleId))).write(
        MedicationSchedulesCompanion(
          label: Value(label.trim()),
          dosage: Value(_blankToNull(dosage)),
          timesJson: Value(jsonEncode(normalizedTimes)),
          enabled: Value(enabled),
          deletedAt: const Value(null),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
        ),
      );
    }
    await _enqueue('medicationSchedule', scheduleId, 'upsert');
    return scheduleId;
  }

  Future<void> softDeleteMedicationSchedule(String id) async {
    final existing =
        await (database.select(database.medicationSchedules)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (existing == null) throw StateError('找不到要刪除的藥物提醒。');
    final now = DateTime.now().toUtc();
    await (database.update(
      database.medicationSchedules,
    )..where((row) => row.id.equals(id))).write(
      MedicationSchedulesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(existing.version + 1),
      ),
    );
    await _enqueue('medicationSchedule', id, 'delete');
  }

  Stream<List<MedicationIntakeEntry>> watchMedicationIntakes({
    DateTime? from,
    DateTime? to,
  }) =>
      (database.select(database.medicationIntakeEntries)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  (from == null
                      ? const Constant(true)
                      : row.scheduledDay.isBiggerOrEqualValue(_day(from))) &
                  (to == null
                      ? const Constant(true)
                      : row.scheduledDay.isSmallerOrEqualValue(_day(to))),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.scheduledDay),
              (row) => OrderingTerm.asc(row.scheduledTime),
            ]))
          .watch();

  Future<List<MedicationIntakeEntry>> getMedicationIntakes({
    DateTime? from,
    DateTime? to,
  }) =>
      (database.select(database.medicationIntakeEntries)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  (from == null
                      ? const Constant(true)
                      : row.scheduledDay.isBiggerOrEqualValue(_day(from))) &
                  (to == null
                      ? const Constant(true)
                      : row.scheduledDay.isSmallerOrEqualValue(_day(to))),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.scheduledDay),
              (row) => OrderingTerm.asc(row.scheduledTime),
            ]))
          .get();

  Future<MedicationIntakeEntry?> getMedicationIntake({
    required String scheduleId,
    required DateTime scheduledDay,
    required String scheduledTime,
  }) =>
      (database.select(database.medicationIntakeEntries)..where(
            (row) =>
                row.scheduleId.equals(scheduleId) &
                row.scheduledDay.equals(_day(scheduledDay)) &
                row.scheduledTime.equals(scheduledTime) &
                row.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<String> saveMedicationIntake({
    required String scheduleId,
    required String scheduleLabel,
    required DateTime scheduledDay,
    required String scheduledTime,
    required String status,
    DateTime? takenAt,
  }) async {
    if (!_isUuid(scheduleId)) throw ArgumentError('藥物提醒識別碼不正確。');
    if (!_isTime(scheduledTime)) throw ArgumentError('服用時間格式不正確。');
    if (status != 'taken' && status != 'skipped') {
      throw ArgumentError('服用狀態不正確。');
    }
    _validateText(scheduleLabel, 'medication label', maxLength: 100);
    final schedule = await (database.select(
      database.medicationSchedules,
    )..where((row) => row.id.equals(scheduleId))).getSingleOrNull();
    if (schedule == null) throw StateError('找不到藥物提醒。');
    final date = _day(scheduledDay);
    final now = DateTime.now().toUtc();
    final taken = status == 'taken' ? (takenAt ?? now).toUtc() : null;
    final existing =
        await (database.select(database.medicationIntakeEntries)..where(
              (row) =>
                  row.scheduleId.equals(scheduleId) &
                  row.scheduledDay.equals(date) &
                  row.scheduledTime.equals(scheduledTime),
            ))
            .getSingleOrNull();
    final entryId = existing?.id ?? _uuid.v4();
    if (existing == null) {
      await database
          .into(database.medicationIntakeEntries)
          .insert(
            MedicationIntakeEntriesCompanion.insert(
              id: Value(entryId),
              scheduleId: scheduleId,
              scheduleLabel: scheduleLabel.trim(),
              scheduledDay: date,
              scheduledTime: scheduledTime,
              status: status,
              takenAt: Value(taken),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (database.update(
        database.medicationIntakeEntries,
      )..where((row) => row.id.equals(entryId))).write(
        MedicationIntakeEntriesCompanion(
          scheduleLabel: Value(scheduleLabel.trim()),
          status: Value(status),
          takenAt: Value(taken),
          deletedAt: const Value(null),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
        ),
      );
    }
    await _enqueue('medicationIntake', entryId, 'upsert');
    return entryId;
  }

  Future<void> softDeleteMedicationIntake(String id) async {
    final existing =
        await (database.select(database.medicationIntakeEntries)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (existing == null) throw StateError('找不到要刪除的服用紀錄。');
    final now = DateTime.now().toUtc();
    await (database.update(
      database.medicationIntakeEntries,
    )..where((row) => row.id.equals(id))).write(
      MedicationIntakeEntriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(existing.version + 1),
      ),
    );
    await _enqueue('medicationIntake', id, 'delete');
  }

  Future<void> clearAllUserData() async {
    await database.transaction(() async {
      await database.delete(database.syncOutbox).go();
      await database.delete(database.medicationIntakeEntries).go();
      await database.delete(database.medicationSchedules).go();
      await database.delete(database.predictionSnapshots).go();
      await database.delete(database.dailyLogs).go();
      await database.delete(database.periods).go();
      await database.delete(database.appSettings).go();
    });
  }

  Future<List<Period>> getPeriods() =>
      (database.select(database.periods)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.startDate)]))
          .get();

  Future<Period> startPeriod(DateTime date, {String? note}) async {
    final start = _day(date);
    final active =
        await (database.select(database.periods)
              ..where((row) => row.deletedAt.isNull() & row.endDate.isNull()))
            .getSingleOrNull();
    if (active != null) throw StateError('已有尚未結束的月經紀錄');

    return savePeriod(startDate: start, note: note);
  }

  /// Creates a historical period. Existing entries can be changed with
  /// [updatePeriod], which preserves their stable identifier.
  Future<Period> savePeriod({
    required DateTime startDate,
    DateTime? endDate,
    String? flow,
    bool spotting = false,
    bool clots = false,
    String? note,
  }) async {
    final start = _day(startDate);
    final end = endDate == null ? null : _day(endDate);
    _validatePeriodDates(start, end);
    _validateText(note, 'note', maxLength: 10000);
    _validateFlow(flow);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    return database.transaction(() async {
      await _ensureNoOverlap(start, end);
      await database
          .into(database.periods)
          .insert(
            PeriodsCompanion.insert(
              id: Value(id),
              startDate: start,
              endDate: Value(end),
              flow: Value(flow),
              spotting: Value(spotting),
              clots: Value(clots),
              note: Value(note),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await _enqueue('period', id, 'upsert');
      return (database.select(
        database.periods,
      )..where((row) => row.id.equals(id))).getSingle();
    });
  }

  Future<Period> updatePeriod({
    required String id,
    required DateTime startDate,
    DateTime? endDate,
    String? flow,
    bool spotting = false,
    bool clots = false,
    String? note,
  }) async {
    final start = _day(startDate);
    final end = endDate == null ? null : _day(endDate);
    _validatePeriodDates(start, end);
    _validateText(note, 'note', maxLength: 10000);
    _validateFlow(flow);
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final existing =
          await (database.select(database.periods)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull();
      if (existing == null) throw StateError('找不到要編輯的月經紀錄');
      await _ensureNoOverlap(start, end, exceptId: id);
      await (database.update(
        database.periods,
      )..where((row) => row.id.equals(id))).write(
        PeriodsCompanion(
          startDate: Value(start),
          endDate: Value(end),
          flow: Value(flow),
          spotting: Value(spotting),
          clots: Value(clots),
          note: Value(note),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
        ),
      );
      await _enqueue('period', id, 'upsert');
    });
    return (database.select(
      database.periods,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<void> endActivePeriod(DateTime date) async {
    final end = _day(date);
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final active =
          await (database.select(database.periods)
                ..where((row) => row.deletedAt.isNull() & row.endDate.isNull()))
              .getSingleOrNull();
      if (active == null) throw StateError('目前沒有進行中的月經紀錄');
      if (end.isBefore(active.startDate)) {
        throw ArgumentError('結束日期不可早於開始日期');
      }
      await (database.update(
        database.periods,
      )..where((row) => row.id.equals(active.id))).write(
        PeriodsCompanion(
          endDate: Value(end),
          updatedAt: Value(now),
          version: Value(active.version + 1),
        ),
      );
      await _enqueue('period', active.id, 'upsert');
    });
  }

  Future<void> saveDailyLog({
    required DateTime day,
    int? painLevel,
    String? flow,
    bool spotting = false,
    bool clots = false,
    List<String> symptoms = const [],
    List<String> moods = const [],
    Map<String, Object?> body = const {},
    Map<String, Object?> reproductive = const {},
    List<String> medications = const [],
    List<String> tags = const [],
    String? note,
  }) async {
    if (painLevel != null && (painLevel < 0 || painLevel > 10)) {
      throw RangeError.range(painLevel, 0, 10, 'painLevel');
    }
    _validateFlow(flow);
    _validateText(note, 'note', maxLength: 10000);
    for (final values in [symptoms, moods, medications, tags]) {
      if (values.length > 100) {
        throw ArgumentError('Each record list can contain at most 100 items');
      }
      for (final value in values) {
        _validateText(value, 'record item', maxLength: 100);
      }
    }
    final encodedBody = jsonEncode(body);
    final encodedReproductive = jsonEncode(reproductive);
    if (encodedBody.length > 20000 || encodedReproductive.length > 20000) {
      throw ArgumentError('單筆健康欄位不可超過 20,000 個字元');
    }
    final date = _day(day);
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final current = await (database.select(
        database.dailyLogs,
      )..where((row) => row.day.equals(date))).getSingleOrNull();
      final id = current?.id ?? _uuid.v4();
      if (current == null) {
        await database
            .into(database.dailyLogs)
            .insert(
              DailyLogsCompanion.insert(
                id: Value(id),
                day: date,
                painLevel: Value(painLevel),
                flow: Value(flow),
                spotting: Value(spotting),
                clots: Value(clots),
                symptomsJson: Value(jsonEncode(symptoms)),
                moodsJson: Value(jsonEncode(moods)),
                bodyJson: Value(encodedBody),
                reproductiveJson: Value(encodedReproductive),
                medicationJson: Value(jsonEncode(medications)),
                tagsJson: Value(jsonEncode(tags)),
                note: Value(note),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (database.update(
          database.dailyLogs,
        )..where((row) => row.id.equals(id))).write(
          DailyLogsCompanion(
            painLevel: Value(painLevel),
            flow: Value(flow),
            spotting: Value(spotting),
            clots: Value(clots),
            symptomsJson: Value(jsonEncode(symptoms)),
            moodsJson: Value(jsonEncode(moods)),
            bodyJson: Value(encodedBody),
            reproductiveJson: Value(encodedReproductive),
            medicationJson: Value(jsonEncode(medications)),
            tagsJson: Value(jsonEncode(tags)),
            note: Value(note),
            deletedAt: const Value(null),
            updatedAt: Value(now),
            version: Value((current.version + 1)),
          ),
        );
      }
      await _enqueue('dailyLog', id, 'upsert');
    });
  }

  Future<void> softDeletePeriod(String id) async {
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final existing =
          await (database.select(database.periods)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull();
      if (existing == null) throw StateError('找不到要刪除的月經紀錄');
      await (database.update(
        database.periods,
      )..where((row) => row.id.equals(id))).write(
        PeriodsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
        ),
      );
      await _enqueue('period', id, 'delete');
    });
  }

  /// Saves the compact home-screen fields without touching the rest of a log.
  Future<DailyLog> saveQuickLog({
    required DateTime day,
    required int? painLevel,
    required String? flow,
    required List<String> moods,
  }) async {
    if (painLevel != null && (painLevel < 0 || painLevel > 10)) {
      throw RangeError.range(painLevel, 0, 10, 'painLevel');
    }
    _validateFlow(flow);
    if (moods.length > 100) throw ArgumentError('情緒項目不可超過 100 個');
    for (final mood in moods) {
      _validateText(mood, 'mood', maxLength: 100);
    }
    final date = _day(day);
    final now = DateTime.now().toUtc();
    return database.transaction(() async {
      final current = await (database.select(
        database.dailyLogs,
      )..where((row) => row.day.equals(date))).getSingleOrNull();
      final id = current?.id ?? _uuid.v4();
      if (current == null) {
        await database
            .into(database.dailyLogs)
            .insert(
              DailyLogsCompanion.insert(
                id: Value(id),
                day: date,
                painLevel: Value(painLevel),
                flow: Value(flow),
                moodsJson: Value(jsonEncode(moods)),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (database.update(
          database.dailyLogs,
        )..where((row) => row.id.equals(id))).write(
          DailyLogsCompanion(
            painLevel: Value(painLevel),
            flow: Value(flow),
            moodsJson: Value(jsonEncode(moods)),
            deletedAt: const Value(null),
            updatedAt: Value(now),
            version: Value(current.version + 1),
          ),
        );
      }
      await _enqueue('dailyLog', id, 'upsert');
      return (database.select(
        database.dailyLogs,
      )..where((row) => row.id.equals(id))).getSingle();
    });
  }

  /// Reverts a quick entry only while it is still the latest edit to that day.
  Future<void> restoreQuickLog({
    required DateTime day,
    required DailyLog? previous,
    required int expectedVersion,
  }) async {
    final date = _day(day);
    await database.transaction(() async {
      final current = await (database.select(
        database.dailyLogs,
      )..where((row) => row.day.equals(date))).getSingleOrNull();
      if (current == null ||
          current.deletedAt != null ||
          current.version != expectedVersion ||
          (previous != null && previous.id != current.id)) {
        throw StateError('這筆紀錄已有更新，無法撤銷。');
      }
      final now = DateTime.now().toUtc();
      if (previous == null) {
        await (database.update(
          database.dailyLogs,
        )..where((row) => row.id.equals(current.id))).write(
          DailyLogsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            version: Value(current.version + 1),
          ),
        );
        await _enqueue('dailyLog', current.id, 'delete');
        return;
      }
      await (database.update(
        database.dailyLogs,
      )..where((row) => row.id.equals(current.id))).write(
        DailyLogsCompanion(
          painLevel: Value(previous.painLevel),
          flow: Value(previous.flow),
          spotting: Value(previous.spotting),
          clots: Value(previous.clots),
          symptomsJson: Value(previous.symptomsJson),
          moodsJson: Value(previous.moodsJson),
          bodyJson: Value(previous.bodyJson),
          reproductiveJson: Value(previous.reproductiveJson),
          medicationJson: Value(previous.medicationJson),
          tagsJson: Value(previous.tagsJson),
          note: Value(previous.note),
          deletedAt: const Value(null),
          updatedAt: Value(now),
          version: Value(current.version + 1),
        ),
      );
      await _enqueue('dailyLog', current.id, 'upsert');
    });
  }

  Future<void> softDeleteDailyLog(String id) async {
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      final existing =
          await (database.select(database.dailyLogs)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull();
      if (existing == null) throw StateError('找不到要刪除的健康紀錄');
      await (database.update(
        database.dailyLogs,
      )..where((row) => row.id.equals(id))).write(
        DailyLogsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          version: Value(existing.version + 1),
        ),
      );
      await _enqueue('dailyLog', id, 'delete');
    });
  }

  Future<void> _ensureNoOverlap(
    DateTime start,
    DateTime? end, {
    String? exceptId,
  }) async {
    final periods = await getPeriods();
    final overlaps = periods.any((period) {
      if (period.id == exceptId) return false;
      final existingEnd = period.endDate;
      return (existingEnd == null || !start.isAfter(existingEnd)) &&
          (end == null || !end.isBefore(period.startDate));
    });
    if (overlaps) throw StateError('日期與既有月經紀錄重疊');
  }

  void _validatePeriodDates(DateTime start, DateTime? end) {
    if (end != null && end.isBefore(start)) {
      throw ArgumentError('結束日期不可早於開始日期');
    }
  }

  void _validateFlow(String? flow) {
    if (flow != null && !const {'無', '少', '中', '多'}.contains(flow)) {
      throw ArgumentError.value(flow, 'flow', '使用無、少、中或多');
    }
  }

  void _validateText(String? value, String field, {required int maxLength}) {
    if (value != null && value.length > maxLength) {
      throw ArgumentError('$field 不可超過 $maxLength 個字元');
    }
  }

  static bool _isTime(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour <= 23 && minute <= 59;
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  Future<void> _enqueue(String type, String id, String operation) => database
      .into(database.syncOutbox)
      .insert(
        SyncOutboxCompanion.insert(
          entityType: type,
          entityId: id,
          operation: operation,
        ),
      );
}

DateTime _day(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
