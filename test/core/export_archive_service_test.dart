import 'dart:convert';

import 'package:drift/native.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/data_management/export_archive_service.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';

void main() {
  test(
    'exports records and restores only authenticated encrypted backups',
    () async {
      final source = AppDatabase(NativeDatabase.memory());
      final sourceRepository = CycleRepository(source);
      final sourceDay = DateTime(2026, 3, 12);
      final period = await sourceRepository.savePeriod(
        startDate: DateTime(2026, 2, 12),
        endDate: DateTime(2026, 2, 16),
        flow: '中',
      );
      final scheduleId = await sourceRepository.saveMedicationSchedule(
        label: '鐵劑',
        dosage: '1 顆',
        times: ['08:00'],
        enabled: true,
      );
      final intakeId = await sourceRepository.saveMedicationIntake(
        scheduleId: scheduleId,
        scheduleLabel: '鐵劑',
        scheduledDay: DateTime(2026, 3, 12),
        scheduledTime: '08:00',
        status: 'taken',
      );
      await sourceRepository.saveDailyLog(
        day: sourceDay,
        symptoms: ['經痛'],
        note: '=formula-like text',
      );
      await sourceRepository.saveSetting('tracking_mode', '只記錄');

      final service = ExportArchiveService(source);
      final jsonExport = await service.exportJson(
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 3, 31),
      );
      final decoded = jsonDecode(jsonExport) as Map<String, dynamic>;
      expect(decoded['format'], 'luna-cycle-export');
      expect((decoded['data']['periods'] as List), hasLength(1));
      expect((decoded['data']['dailyLogs'] as List), hasLength(1));
      expect((decoded['data']['medicationSchedules'] as List), hasLength(1));
      expect((decoded['data']['medicationIntakes'] as List), hasLength(1));

      final csv = await service.exportCsv(
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 3, 31),
      );
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('daily_log'));
      expect(csv, contains("'=formula-like text"));

      final backup = await service.createEncryptedBackup(
        'secure-backup-passphrase',
      );
      expect(utf8.decode(backup), isNot(contains('formula-like text')));
      final inspection = await service.inspectEncryptedBackup(
        backup,
        'secure-backup-passphrase',
      );
      expect(inspection.periodCount, 1);
      expect(inspection.dailyLogCount, 1);
      expect(inspection.medicationScheduleCount, 1);
      expect(inspection.medicationIntakeCount, 1);
      expect(inspection.earliestDate, DateTime.utc(2026, 2, 12));
      expect(inspection.latestDate, DateTime.utc(2026, 3, 12));
      expect((await sourceRepository.getPeriods()).single.id, period.id);
      await expectLater(
        service.inspectEncryptedBackup(backup, 'wrong-backup-passphrase'),
        throwsA(isA<FormatException>()),
      );

      await source.close();
      final restored = AppDatabase(NativeDatabase.memory());
      final restoredRepository = CycleRepository(restored);
      await restoredRepository.saveDailyLog(
        day: DateTime(2026, 4, 1),
        note: 'replace me',
      );
      final restoreService = ExportArchiveService(restored);
      await restoreService.restoreEncryptedBackup(
        backup,
        'secure-backup-passphrase',
      );
      final restoredPeriod = await restoredRepository.getPeriods();
      final restoredLog = await restoredRepository.getDailyLog(sourceDay);
      expect(restoredPeriod.single.id, period.id);
      expect(restoredLog?.symptomsJson, '["經痛"]');
      expect(restoredLog?.note, '=formula-like text');
      expect(
        (await restoredRepository.getMedicationSchedules()).single.id,
        scheduleId,
      );
      expect(
        (await restoredRepository.getMedicationIntakes()).single.id,
        intakeId,
      );
      expect(
        await restoredRepository.getDailyLog(DateTime(2026, 4, 1)),
        isNull,
      );

      await expectLater(
        restoreService.restoreEncryptedBackup(
          backup,
          'wrong-backup-passphrase',
        ),
        throwsA(isA<FormatException>()),
      );
      expect((await restoredRepository.getPeriods()).single.id, period.id);
      await expectLater(
        restoreService.restoreEncryptedBackup([
          1,
          2,
          3,
        ], 'secure-backup-passphrase'),
        throwsA(isA<FormatException>()),
      );
      expect((await restoredRepository.getPeriods()).single.id, period.id);

      await restored.close();
    },
  );

  test(
    'restores schema v2 encrypted backups with empty v3 medication tables',
    () async {
      const password = 'secure-backup-passphrase';
      const associatedData = 'luna-cycle-encrypted-backup:v1';
      final clearText = utf8.encode(
        jsonEncode({
          'format': 'luna-cycle-encrypted-backup',
          'formatVersion': 1,
          'databaseSchemaVersion': 2,
          'data': {
            'periods': [],
            'dailyLogs': [],
            'settings': [],
            'predictionSnapshots': [],
            'syncOutbox': [],
          },
        }),
      );
      final salt = List<int>.generate(16, (index) => index);
      final nonce = List<int>.generate(
        AesGcm.defaultNonceLength,
        (index) => index + 1,
      );
      final key = await Pbkdf2.hmacSha256(
        iterations: 310000,
        bits: 256,
      ).deriveKeyFromPassword(password: password, nonce: salt);
      final box = await AesGcm.with256bits().encrypt(
        clearText,
        secretKey: key,
        nonce: nonce,
        aad: utf8.encode(associatedData),
      );
      final backup = utf8.encode(
        jsonEncode({
          'format': 'luna-cycle-encrypted-backup',
          'formatVersion': 1,
          'kdf': {
            'name': 'PBKDF2-HMAC-SHA256',
            'iterations': 310000,
            'salt': base64Encode(salt),
          },
          'cipher': {
            'name': 'AES-256-GCM',
            'nonce': base64Encode(nonce),
            'cipherText': base64Encode(box.cipherText),
            'tag': base64Encode(box.mac.bytes),
          },
        }),
      );
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await ExportArchiveService(
          database,
        ).restoreEncryptedBackup(backup, password);
        expect(await database.select(database.periods).get(), isEmpty);
        expect(await database.select(database.dailyLogs).get(), isEmpty);
        expect(
          await database.select(database.medicationSchedules).get(),
          isEmpty,
        );
        expect(
          await database.select(database.medicationIntakeEntries).get(),
          isEmpty,
        );
      } finally {
        await database.close();
      }
    },
  );
}
