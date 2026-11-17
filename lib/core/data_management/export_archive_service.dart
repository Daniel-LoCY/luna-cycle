import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';

const _maxArchiveBytes = 100 * 1024 * 1024;
final _secureRandom = Random.secure();

class BackupInspection {
  const BackupInspection({
    required this.periodCount,
    required this.dailyLogCount,
    required this.medicationScheduleCount,
    required this.medicationIntakeCount,
    required this.earliestDate,
    required this.latestDate,
  });

  final int periodCount;
  final int dailyLogCount;
  final int medicationScheduleCount;
  final int medicationIntakeCount;
  final DateTime? earliestDate;
  final DateTime? latestDate;
}

/// Serializes user data and creates portable, password-encrypted backups.
/// Plain exports are intended for an explicit user-initiated share or save.
class ExportArchiveService {
  ExportArchiveService(this.database);

  final AppDatabase database;

  static const _exportFormat = 'luna-cycle-export';
  static const _backupFormat = 'luna-cycle-encrypted-backup';
  static const _formatVersion = 1;
  static const _pbkdf2Iterations = 310000;
  static const _associatedData = 'luna-cycle-encrypted-backup:v1';

  Future<String> exportJson({DateTime? from, DateTime? to}) async {
    final range = _dateRange(from, to);
    final data = await _readData(
      includeDeleted: false,
      from: range.$1,
      to: range.$2,
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': _exportFormat,
      'formatVersion': _formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    });
  }

  Future<String> exportCsv({DateTime? from, DateTime? to}) async {
    final range = _dateRange(from, to);
    final data = await _readData(
      includeDeleted: false,
      from: range.$1,
      to: range.$2,
    );
    const columns = [
      'record_type',
      'id',
      'date',
      'start_date',
      'end_date',
      'flow',
      'pain_level',
      'spotting',
      'clots',
      'symptoms_json',
      'moods_json',
      'body_json',
      'reproductive_json',
      'medications_json',
      'tags_json',
      'note',
      'created_at',
      'updated_at',
      'version',
    ];
    final rows = <List<Object?>>[columns];
    for (final period in data['periods']!) {
      rows.add([
        'period',
        period['id'],
        null,
        period['startDate'],
        period['endDate'],
        period['flow'],
        null,
        period['spotting'],
        period['clots'],
        null,
        null,
        null,
        null,
        null,
        null,
        period['note'],
        period['createdAt'],
        period['updatedAt'],
        period['version'],
      ]);
    }
    for (final log in data['dailyLogs']!) {
      rows.add([
        'daily_log',
        log['id'],
        log['day'],
        null,
        null,
        log['flow'],
        log['painLevel'],
        log['spotting'],
        log['clots'],
        log['symptomsJson'],
        log['moodsJson'],
        log['bodyJson'],
        log['reproductiveJson'],
        log['medicationJson'],
        log['tagsJson'],
        log['note'],
        log['createdAt'],
        log['updatedAt'],
        log['version'],
      ]);
    }
    for (final schedule in data['medicationSchedules']!) {
      rows.add([
        'medication_schedule',
        schedule['id'],
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        schedule['timesJson'],
        null,
        '${schedule['label']}${schedule['dosage'] == null ? '' : ' · ${schedule['dosage']}'}',
        schedule['createdAt'],
        schedule['updatedAt'],
        schedule['version'],
      ]);
    }
    for (final intake in data['medicationIntakes']!) {
      rows.add([
        'medication_intake',
        intake['id'],
        intake['scheduledDay'],
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        intake['scheduleLabel'],
        null,
        '${intake['scheduledTime']} · ${intake['status']}',
        intake['createdAt'],
        intake['updatedAt'],
        intake['version'],
      ]);
    }
    return '\uFEFF${rows.map((row) => row.map(_csvCell).join(',')).join('\r\n')}\r\n';
  }

  Future<Uint8List> createEncryptedBackup(String password) async {
    _validatePassword(password);
    final data = await _readData(includeDeleted: true);
    final payload = utf8.encode(
      jsonEncode({
        'format': _backupFormat,
        'formatVersion': _formatVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'databaseSchemaVersion': AppDatabase.schemaVersionNumber,
        'data': data,
      }),
    );
    final salt = _secureBytes(16);
    final nonce = _secureBytes(AesGcm.defaultNonceLength);
    final secretKey = await Pbkdf2.hmacSha256(
      iterations: _pbkdf2Iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final box = await AesGcm.with256bits().encrypt(
      payload,
      secretKey: secretKey,
      nonce: nonce,
      aad: utf8.encode(_associatedData),
    );
    final envelope = {
      'format': _backupFormat,
      'formatVersion': _formatVersion,
      'kdf': {
        'name': 'PBKDF2-HMAC-SHA256',
        'iterations': _pbkdf2Iterations,
        'salt': base64Encode(salt),
      },
      'cipher': {
        'name': 'AES-256-GCM',
        'nonce': base64Encode(nonce),
        'cipherText': base64Encode(box.cipherText),
        'tag': base64Encode(box.mac.bytes),
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Authenticates a backup and returns a summary without changing local data.
  Future<BackupInspection> inspectEncryptedBackup(
    List<int> archiveBytes,
    String password,
  ) async {
    final backup = await _decodeEncryptedBackup(archiveBytes, password);
    final activePeriods = backup.periods
        .where((row) => row.deletedAt.value == null)
        .toList();
    final activeLogs = backup.dailyLogs
        .where((row) => row.deletedAt.value == null)
        .toList();
    final activeMedicationSchedules = backup.medicationSchedules
        .where((row) => row.deletedAt.value == null)
        .toList();
    final activeMedicationIntakes = backup.medicationIntakes
        .where((row) => row.deletedAt.value == null)
        .toList();
    final dates = <DateTime>[
      for (final row in activePeriods) row.startDate.value,
      for (final row in activeLogs) row.day.value,
      for (final row in activeMedicationIntakes) row.scheduledDay.value,
    ]..sort();
    return BackupInspection(
      periodCount: activePeriods.length,
      dailyLogCount: activeLogs.length,
      medicationScheduleCount: activeMedicationSchedules.length,
      medicationIntakeCount: activeMedicationIntakes.length,
      earliestDate: dates.isEmpty ? null : dates.first,
      latestDate: dates.isEmpty ? null : dates.last,
    );
  }

  /// Authenticates and validates before replacing data. A malformed archive
  /// or failed insert leaves the existing database intact.
  Future<void> restoreEncryptedBackup(
    List<int> archiveBytes,
    String password,
  ) async {
    await _replaceDatabase(
      await _decodeEncryptedBackup(archiveBytes, password),
    );
  }

  Future<_ValidatedBackup> _decodeEncryptedBackup(
    List<int> archiveBytes,
    String password,
  ) async {
    if (archiveBytes.isEmpty || archiveBytes.length > _maxArchiveBytes) {
      throw const FormatException('備份檔案大小不正確。');
    }
    _validatePassword(password);
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(utf8.decode(archiveBytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _backupFormat ||
          decoded['formatVersion'] != _formatVersion) {
        throw const FormatException('不支援的備份檔案格式。');
      }
      envelope = decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('備份檔案無法讀取。');
    }
    final kdf = _map(envelope['kdf'], 'kdf');
    final cipher = _map(envelope['cipher'], 'cipher');
    if (kdf['name'] != 'PBKDF2-HMAC-SHA256' ||
        cipher['name'] != 'AES-256-GCM') {
      throw const FormatException('不支援的加密格式。');
    }
    final iterations = _int(kdf['iterations'], 'iterations');
    if (iterations < 100000 || iterations > 1000000) {
      throw const FormatException('備份檔案的金鑰參數不安全或不正確。');
    }
    final salt = _base64(kdf['salt'], 'salt', expectedLength: 16);
    final nonce = _base64(
      cipher['nonce'],
      'nonce',
      expectedLength: AesGcm.defaultNonceLength,
    );
    final cipherText = _base64(cipher['cipherText'], 'cipherText');
    final tag = _base64(cipher['tag'], 'tag', expectedLength: 16);

    final secretKey = await Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final List<int> clearText;
    try {
      clearText = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: secretKey,
        aad: utf8.encode(_associatedData),
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException('密碼錯誤或備份檔案已損壞。');
    }
    if (clearText.length > _maxArchiveBytes) {
      throw const FormatException('解密後的備份資料過大。');
    }
    return _decodeBackup(clearText);
  }

  Future<Map<String, List<Map<String, Object?>>>> _readData({
    required bool includeDeleted,
    DateTime? from,
    DateTime? to,
  }) async {
    final periodRows = await database.select(database.periods).get();
    final logRows = await database.select(database.dailyLogs).get();
    final settings = await database.select(database.appSettings).get();
    final snapshots = await database.select(database.predictionSnapshots).get();
    final outbox = await database.select(database.syncOutbox).get();
    final medicationSchedules = await database
        .select(database.medicationSchedules)
        .get();
    final medicationIntakes = await database
        .select(database.medicationIntakeEntries)
        .get();

    bool isInRange(DateTime day) =>
        (from == null || !day.isBefore(from)) &&
        (to == null || !day.isAfter(to));
    final periods = periodRows
        .where((row) {
          if (!includeDeleted && row.deletedAt != null) return false;
          if (from == null && to == null) return true;
          final end = row.endDate ?? row.startDate;
          return (to == null || !row.startDate.isAfter(to)) &&
              (from == null || !end.isBefore(from));
        })
        .map(_periodToJson)
        .toList();
    final logs = logRows
        .where(
          (row) =>
              (includeDeleted || row.deletedAt == null) && isInRange(row.day),
        )
        .map(_dailyLogToJson)
        .toList();
    final filteredMedicationSchedules = medicationSchedules
        .where((row) => includeDeleted || row.deletedAt == null)
        .map(_medicationScheduleToJson)
        .toList();
    final filteredMedicationIntakes = medicationIntakes
        .where((row) {
          if (!includeDeleted && row.deletedAt != null) return false;
          return isInRange(row.scheduledDay);
        })
        .map(_medicationIntakeToJson)
        .toList();
    return {
      'periods': periods,
      'dailyLogs': logs,
      'medicationSchedules': filteredMedicationSchedules,
      'medicationIntakes': filteredMedicationIntakes,
      'settings': [for (final row in settings) _settingToJson(row)],
      'predictionSnapshots': [
        for (final row in snapshots) _snapshotToJson(row),
      ],
      'syncOutbox': [for (final row in outbox) _outboxToJson(row)],
    };
  }

  _ValidatedBackup _decodeBackup(List<int> clearText) {
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _backupFormat ||
          decoded['formatVersion'] != _formatVersion) {
        throw const FormatException('備份內容格式不正確。');
      }
      root = decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('備份內容無法讀取。');
    }
    final data = _map(root['data'], 'data');
    final backupSchema = _int(
      root['databaseSchemaVersion'],
      'databaseSchemaVersion',
    );
    if (backupSchema < 2 || backupSchema > AppDatabase.schemaVersionNumber) {
      throw const FormatException('這份備份使用不相容的資料庫版本。');
    }
    final compatibleData = {
      ...data,
      if (backupSchema < 3) 'medicationSchedules': <dynamic>[],
      if (backupSchema < 3) 'medicationIntakes': <dynamic>[],
    };
    final medicationSchedules = _decodeRows(
      compatibleData,
      'medicationSchedules',
      _medicationScheduleFromJson,
    );
    final medicationIntakes = _decodeRows(
      compatibleData,
      'medicationIntakes',
      _medicationIntakeFromJson,
    );
    final scheduleIds = medicationSchedules.map((row) => row.id.value).toSet();
    if (medicationIntakes.any(
      (row) => !scheduleIds.contains(row.scheduleId.value),
    )) {
      throw const FormatException('藥物服用紀錄沒有對應的藥物提醒。');
    }
    return _ValidatedBackup(
      periods: _decodeRows(data, 'periods', _periodFromJson),
      dailyLogs: _decodeRows(data, 'dailyLogs', _dailyLogFromJson),
      medicationSchedules: medicationSchedules,
      medicationIntakes: medicationIntakes,
      settings: _decodeRows(data, 'settings', _settingFromJson),
      snapshots: _decodeRows(data, 'predictionSnapshots', _snapshotFromJson),
      outbox: _decodeRows(data, 'syncOutbox', _outboxFromJson),
    );
  }

  Future<void> _replaceDatabase(_ValidatedBackup backup) async {
    await database.transaction(() async {
      await database.delete(database.syncOutbox).go();
      await database.delete(database.medicationIntakeEntries).go();
      await database.delete(database.medicationSchedules).go();
      await database.delete(database.predictionSnapshots).go();
      await database.delete(database.appSettings).go();
      await database.delete(database.dailyLogs).go();
      await database.delete(database.periods).go();
      for (final row in backup.periods) {
        await database.into(database.periods).insert(row);
      }
      for (final row in backup.dailyLogs) {
        await database.into(database.dailyLogs).insert(row);
      }
      for (final row in backup.medicationSchedules) {
        await database.into(database.medicationSchedules).insert(row);
      }
      for (final row in backup.medicationIntakes) {
        await database.into(database.medicationIntakeEntries).insert(row);
      }
      for (final row in backup.settings) {
        await database.into(database.appSettings).insert(row);
      }
      for (final row in backup.snapshots) {
        await database.into(database.predictionSnapshots).insert(row);
      }
      for (final row in backup.outbox) {
        await database.into(database.syncOutbox).insert(row);
      }
    });
  }
}

class _ValidatedBackup {
  const _ValidatedBackup({
    required this.periods,
    required this.dailyLogs,
    required this.medicationSchedules,
    required this.medicationIntakes,
    required this.settings,
    required this.snapshots,
    required this.outbox,
  });

  final List<PeriodsCompanion> periods;
  final List<DailyLogsCompanion> dailyLogs;
  final List<MedicationSchedulesCompanion> medicationSchedules;
  final List<MedicationIntakeEntriesCompanion> medicationIntakes;
  final List<AppSettingsCompanion> settings;
  final List<PredictionSnapshotsCompanion> snapshots;
  final List<SyncOutboxCompanion> outbox;
}

(DateTime?, DateTime?) _dateRange(DateTime? from, DateTime? to) {
  final start = from == null ? null : _day(from);
  final end = to == null ? null : _day(to);
  if (start != null && end != null && start.isAfter(end)) {
    throw ArgumentError('開始日期不可晚於結束日期。');
  }
  return (start, end);
}

String _csvCell(Object? input) {
  var value = input?.toString() ?? '';
  if (RegExp(r'^\s*[=+\-@]').hasMatch(value)) value = "'$value";
  return '"${value.replaceAll('"', '""')}"';
}

void _validatePassword(String password) {
  if (password.runes.length < 12 || password.runes.length > 128) {
    throw ArgumentError('備份密碼請使用 12 至 128 個字元。');
  }
}

List<int> _secureBytes(int length) =>
    List<int>.generate(length, (_) => _secureRandom.nextInt(256));

DateTime _day(DateTime date) => DateTime.utc(date.year, date.month, date.day);
String _date(DateTime? date) => date?.toUtc().toIso8601String() ?? '';

Map<String, Object?> _periodToJson(Period row) => {
  'id': row.id,
  'startDate': _date(row.startDate),
  'endDate': _date(row.endDate),
  'flow': row.flow,
  'spotting': row.spotting,
  'clots': row.clots,
  'note': row.note,
  'createdAt': _date(row.createdAt),
  'updatedAt': _date(row.updatedAt),
  'deletedAt': _date(row.deletedAt),
  'version': row.version,
  'syncState': row.syncState,
};

Map<String, Object?> _dailyLogToJson(DailyLog row) => {
  'id': row.id,
  'day': _date(row.day),
  'painLevel': row.painLevel,
  'flow': row.flow,
  'spotting': row.spotting,
  'clots': row.clots,
  'symptomsJson': row.symptomsJson,
  'moodsJson': row.moodsJson,
  'bodyJson': row.bodyJson,
  'reproductiveJson': row.reproductiveJson,
  'medicationJson': row.medicationJson,
  'tagsJson': row.tagsJson,
  'note': row.note,
  'createdAt': _date(row.createdAt),
  'updatedAt': _date(row.updatedAt),
  'deletedAt': _date(row.deletedAt),
  'version': row.version,
  'syncState': row.syncState,
};

Map<String, Object?> _medicationScheduleToJson(MedicationSchedule row) => {
  'id': row.id,
  'label': row.label,
  'dosage': row.dosage,
  'timesJson': row.timesJson,
  'enabled': row.enabled,
  'createdAt': _date(row.createdAt),
  'updatedAt': _date(row.updatedAt),
  'deletedAt': _date(row.deletedAt),
  'version': row.version,
  'syncState': row.syncState,
};

Map<String, Object?> _medicationIntakeToJson(MedicationIntakeEntry row) => {
  'id': row.id,
  'scheduleId': row.scheduleId,
  'scheduleLabel': row.scheduleLabel,
  'scheduledDay': _date(row.scheduledDay),
  'scheduledTime': row.scheduledTime,
  'status': row.status,
  'takenAt': _date(row.takenAt),
  'note': row.note,
  'createdAt': _date(row.createdAt),
  'updatedAt': _date(row.updatedAt),
  'deletedAt': _date(row.deletedAt),
  'version': row.version,
  'syncState': row.syncState,
};

Map<String, Object?> _settingToJson(AppSetting row) => {
  'key': row.key,
  'value': row.value,
  'updatedAt': _date(row.updatedAt),
};

Map<String, Object?> _snapshotToJson(PredictionSnapshot row) => {
  'id': row.id,
  'referenceDate': _date(row.referenceDate),
  'resultJson': row.resultJson,
  'createdAt': _date(row.createdAt),
  'version': row.version,
};

Map<String, Object?> _outboxToJson(SyncOutboxData row) => {
  'id': row.id,
  'entityType': row.entityType,
  'entityId': row.entityId,
  'operation': row.operation,
  'createdAt': _date(row.createdAt),
  'attempts': row.attempts,
  'lastError': row.lastError,
};

List<T> _decodeRows<T>(
  Map<String, dynamic> data,
  String key,
  T Function(Map<String, dynamic>) decode,
) {
  final value = data[key];
  if (value is! List || value.length > 100000) {
    throw FormatException('備份資料的 $key 欄位不正確。');
  }
  final result = <T>[];
  final ids = <String>{};
  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      throw FormatException('備份資料的 $key 項目不正確。');
    }
    final row = decode(item);
    if (item['id'] case final String id) {
      if (!ids.add(id)) throw FormatException('$key 含有重複識別碼。');
    }
    result.add(row);
  }
  if (key == 'dailyLogs') {
    final days = <String>{};
    for (final item in value.cast<Map<String, dynamic>>()) {
      if (!days.add(item['day'] as String)) {
        throw const FormatException('每日紀錄含有重複日期。');
      }
    }
  }
  if (key == 'settings') {
    final keys = <String>{};
    for (final item in value.cast<Map<String, dynamic>>()) {
      if (!keys.add(item['key'] as String)) {
        throw const FormatException('設定資料含有重複項目。');
      }
    }
  }
  if (key == 'medicationIntakes') {
    final doses = <String>{};
    for (final item in value.cast<Map<String, dynamic>>()) {
      final composite =
          '${item['scheduleId']}|${item['scheduledDay']}|${item['scheduledTime']}';
      if (!doses.add(composite)) {
        throw const FormatException('藥物服用紀錄含有重複時間。');
      }
    }
  }
  return result;
}

PeriodsCompanion _periodFromJson(Map<String, dynamic> row) {
  final start = _dateField(row, 'startDate');
  final end = _nullableDateField(row, 'endDate');
  if (end != null && end.isBefore(start)) {
    throw const FormatException('月經紀錄結束日期早於開始日期。');
  }
  final flow = _nullableStringField(row, 'flow', maxLength: 20);
  if (flow != null && !const {'無', '少', '中', '多'}.contains(flow)) {
    throw const FormatException('月經紀錄含有無效經血量。');
  }
  return PeriodsCompanion.insert(
    id: Value(_uuidField(row)),
    startDate: start,
    endDate: Value(end),
    flow: Value(flow),
    spotting: Value(_boolField(row, 'spotting')),
    clots: Value(_boolField(row, 'clots')),
    note: Value(_nullableStringField(row, 'note', maxLength: 10000)),
    createdAt: Value(_dateField(row, 'createdAt')),
    updatedAt: Value(_dateField(row, 'updatedAt')),
    deletedAt: Value(_nullableDateField(row, 'deletedAt')),
    version: Value(_positiveInt(row, 'version')),
    syncState: Value(_stringField(row, 'syncState', maxLength: 40)),
  );
}

DailyLogsCompanion _dailyLogFromJson(Map<String, dynamic> row) {
  final pain = row['painLevel'];
  if (pain != null && (pain is! int || pain < 0 || pain > 10)) {
    throw const FormatException('每日紀錄含有無效疼痛程度。');
  }
  final flow = _nullableStringField(row, 'flow', maxLength: 20);
  if (flow != null && !const {'無', '少', '中', '多'}.contains(flow)) {
    throw const FormatException('每日紀錄含有無效經血量。');
  }
  final symptoms = _jsonListField(row, 'symptomsJson');
  final moods = _jsonListField(row, 'moodsJson');
  final medications = _jsonListField(row, 'medicationJson');
  final tags = _jsonListField(row, 'tagsJson');
  final body = _jsonObjectField(row, 'bodyJson');
  final reproductive = _jsonObjectField(row, 'reproductiveJson');
  return DailyLogsCompanion.insert(
    id: Value(_uuidField(row)),
    day: _dateField(row, 'day'),
    painLevel: Value(pain as int?),
    flow: Value(flow),
    spotting: Value(_boolField(row, 'spotting')),
    clots: Value(_boolField(row, 'clots')),
    symptomsJson: Value(symptoms),
    moodsJson: Value(moods),
    bodyJson: Value(body),
    reproductiveJson: Value(reproductive),
    medicationJson: Value(medications),
    tagsJson: Value(tags),
    note: Value(_nullableStringField(row, 'note', maxLength: 10000)),
    createdAt: Value(_dateField(row, 'createdAt')),
    updatedAt: Value(_dateField(row, 'updatedAt')),
    deletedAt: Value(_nullableDateField(row, 'deletedAt')),
    version: Value(_positiveInt(row, 'version')),
    syncState: Value(_stringField(row, 'syncState', maxLength: 40)),
  );
}

MedicationSchedulesCompanion _medicationScheduleFromJson(
  Map<String, dynamic> row,
) {
  final timesJson = _stringField(row, 'timesJson', maxLength: 1000);
  final decodedTimes = jsonDecode(timesJson);
  if (decodedTimes is! List ||
      decodedTimes.isEmpty ||
      decodedTimes.length > 8 ||
      decodedTimes.toSet().length != decodedTimes.length ||
      decodedTimes.any((value) => value is! String || !_validTime(value))) {
    throw const FormatException('備份中的藥物提醒時間不正確。');
  }
  return MedicationSchedulesCompanion.insert(
    id: Value(_uuidField(row)),
    label: _stringField(row, 'label', maxLength: 100),
    dosage: Value(_nullableStringField(row, 'dosage', maxLength: 100)),
    timesJson: Value(timesJson),
    enabled: Value(_boolField(row, 'enabled')),
    createdAt: Value(_dateField(row, 'createdAt')),
    updatedAt: Value(_dateField(row, 'updatedAt')),
    deletedAt: Value(_nullableDateField(row, 'deletedAt')),
    version: Value(_positiveInt(row, 'version')),
    syncState: Value(_stringField(row, 'syncState', maxLength: 40)),
  );
}

MedicationIntakeEntriesCompanion _medicationIntakeFromJson(
  Map<String, dynamic> row,
) {
  final status = _stringField(row, 'status', maxLength: 20);
  if (status != 'taken' && status != 'skipped') {
    throw const FormatException('備份中的藥物服用狀態不正確。');
  }
  final scheduledTime = _stringField(row, 'scheduledTime', maxLength: 5);
  if (!_validTime(scheduledTime)) {
    throw const FormatException('備份中的藥物服用時間不正確。');
  }
  final takenAt = _nullableDateField(row, 'takenAt');
  if ((status == 'taken' && takenAt == null) ||
      (status == 'skipped' && takenAt != null)) {
    throw const FormatException('備份中的服用時間與服用狀態不一致。');
  }
  final scheduledDay = _dateField(row, 'scheduledDay');
  if (scheduledDay.hour != 0 ||
      scheduledDay.minute != 0 ||
      scheduledDay.second != 0) {
    throw const FormatException('備份中的藥物服用日期不正確。');
  }
  return MedicationIntakeEntriesCompanion.insert(
    id: Value(_uuidField(row)),
    scheduleId: _uuidField(row, field: 'scheduleId'),
    scheduleLabel: _stringField(row, 'scheduleLabel', maxLength: 100),
    scheduledDay: scheduledDay,
    scheduledTime: scheduledTime,
    status: status,
    takenAt: Value(takenAt),
    note: Value(_nullableStringField(row, 'note', maxLength: 1000)),
    createdAt: Value(_dateField(row, 'createdAt')),
    updatedAt: Value(_dateField(row, 'updatedAt')),
    deletedAt: Value(_nullableDateField(row, 'deletedAt')),
    version: Value(_positiveInt(row, 'version')),
    syncState: Value(_stringField(row, 'syncState', maxLength: 40)),
  );
}

AppSettingsCompanion _settingFromJson(Map<String, dynamic> row) =>
    AppSettingsCompanion.insert(
      key: _stringField(row, 'key', maxLength: 100),
      value: _stringField(row, 'value', maxLength: 1000),
      updatedAt: Value(_dateField(row, 'updatedAt')),
    );

PredictionSnapshotsCompanion _snapshotFromJson(Map<String, dynamic> row) =>
    PredictionSnapshotsCompanion.insert(
      id: Value(_uuidField(row)),
      referenceDate: _dateField(row, 'referenceDate'),
      resultJson: _stringField(row, 'resultJson', maxLength: 100000),
      createdAt: Value(_dateField(row, 'createdAt')),
      version: Value(_positiveInt(row, 'version')),
    );

SyncOutboxCompanion _outboxFromJson(Map<String, dynamic> row) =>
    SyncOutboxCompanion.insert(
      id: Value(_uuidField(row)),
      entityType: _stringField(row, 'entityType', maxLength: 80),
      entityId: _uuidField(row, field: 'entityId'),
      operation: _stringField(row, 'operation', maxLength: 40),
      createdAt: Value(_dateField(row, 'createdAt')),
      attempts: Value(_nonNegativeInt(row, 'attempts')),
      lastError: Value(_nullableStringField(row, 'lastError', maxLength: 2000)),
    );

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('備份資料的 $field 欄位不正確。');
}

String _uuidField(Map<String, dynamic> row, {String field = 'id'}) {
  final value = _stringField(row, field, maxLength: 36);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw FormatException('備份資料的 $field 識別碼不正確。');
  }
  return value;
}

String _stringField(
  Map<String, dynamic> row,
  String field, {
  required int maxLength,
}) {
  final value = row[field];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('備份資料的 $field 欄位不正確。');
  }
  return value;
}

String? _nullableStringField(
  Map<String, dynamic> row,
  String field, {
  required int maxLength,
}) {
  final value = row[field];
  if (value == null || value == '') return null;
  if (value is! String || value.length > maxLength) {
    throw FormatException('備份資料的 $field 欄位不正確。');
  }
  return value;
}

DateTime _dateField(Map<String, dynamic> row, String field) {
  final value = row[field];
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw FormatException('備份資料的 $field 日期不正確。');
  return date.toUtc();
}

DateTime? _nullableDateField(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value == null || value == '') return null;
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw FormatException('備份資料的 $field 日期不正確。');
  return date.toUtc();
}

bool _boolField(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! bool) throw FormatException('備份資料的 $field 欄位不正確。');
  return value;
}

int _positiveInt(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! int || value < 1) {
    throw FormatException('備份資料的 $field 欄位不正確。');
  }
  return value;
}

int _nonNegativeInt(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! int || value < 0) {
    throw FormatException('備份資料的 $field 欄位不正確。');
  }
  return value;
}

int _int(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('備份資料的 $field 欄位不正確。');
}

bool _validTime(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return false;
  return int.parse(match.group(1)!) <= 23 && int.parse(match.group(2)!) <= 59;
}

String _jsonListField(Map<String, dynamic> row, String field) {
  final value = _stringField(row, field, maxLength: 30000);
  final decoded = jsonDecode(value);
  if (decoded is! List || decoded.length > 100) {
    throw FormatException('備份資料的 $field 欄位不正確。');
  }
  for (final item in decoded) {
    if (item is! String || item.length > 100) {
      throw FormatException('備份資料的 $field 項目不正確。');
    }
  }
  return value;
}

String _jsonObjectField(Map<String, dynamic> row, String field) {
  final value = _stringField(row, field, maxLength: 20000);
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('備份資料的 $field 欄位不正確。');
  }
  return value;
}

List<int> _base64(Object? value, String field, {int? expectedLength}) {
  if (value is! String || value.length > _maxArchiveBytes * 2) {
    throw FormatException('備份檔案的 $field 欄位不正確。');
  }
  try {
    final decoded = base64Decode(value);
    if (expectedLength != null && decoded.length != expectedLength) {
      throw FormatException('備份檔案的 $field 長度不正確。');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw FormatException('備份檔案的 $field 編碼不正確。');
  }
}
