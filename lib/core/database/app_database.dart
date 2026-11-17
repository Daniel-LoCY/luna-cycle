import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

const _uuid = Uuid();
final _secureRandom = Random.secure();

class Periods extends Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  TextColumn get flow => text().nullable()();
  BoolColumn get spotting => boolean().withDefault(const Constant(false))();
  BoolColumn get clots => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class DailyLogs extends Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  DateTimeColumn get day => dateTime()();
  IntColumn get painLevel => integer().nullable()();
  TextColumn get flow => text().nullable()();
  BoolColumn get spotting => boolean().withDefault(const Constant(false))();
  BoolColumn get clots => boolean().withDefault(const Constant(false))();
  TextColumn get symptomsJson => text().withDefault(const Constant('[]'))();
  TextColumn get moodsJson => text().withDefault(const Constant('[]'))();
  TextColumn get bodyJson => text().withDefault(const Constant('{}'))();
  TextColumn get reproductiveJson => text().withDefault(const Constant('{}'))();
  TextColumn get medicationJson => text().withDefault(const Constant('[]'))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {day},
  ];
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class PredictionSnapshots extends Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  DateTimeColumn get referenceDate => dateTime()();
  TextColumn get resultJson => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncOutbox extends Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MedicationSchedules extends Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  TextColumn get label => text()();
  TextColumn get dosage => text().nullable()();
  TextColumn get timesJson => text().withDefault(const Constant('[]'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class MedicationIntakeEntries extends Table {
  TextColumn get id => text().clientDefault(() => _uuid.v4())();
  TextColumn get scheduleId => text()();
  TextColumn get scheduleLabel => text()();
  DateTimeColumn get scheduledDay => dateTime()();
  TextColumn get scheduledTime => text()();
  TextColumn get status => text()();
  DateTimeColumn get takenAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncState => text().withDefault(const Constant('local'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {scheduleId, scheduledDay, scheduledTime},
  ];
}

@DriftDatabase(
  tables: [
    Periods,
    DailyLogs,
    AppSettings,
    PredictionSnapshots,
    SyncOutbox,
    MedicationSchedules,
    MedicationIntakeEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  static const schemaVersionNumber = 3;

  @override
  int get schemaVersion => AppDatabase.schemaVersionNumber;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 1 || to > schemaVersionNumber) {
        throw StateError('Unsupported database migration $from → $to');
      }
      if (from < 2) {
        await migrator.addColumn(dailyLogs, dailyLogs.flow);
        await migrator.addColumn(dailyLogs, dailyLogs.spotting);
        await migrator.addColumn(dailyLogs, dailyLogs.clots);
      }
      if (from < 3) {
        await migrator.createTable(medicationSchedules);
        await migrator.createTable(medicationIntakeEntries);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (!details.wasCreated && details.versionBefore! > schemaVersionNumber) {
        throw StateError('Database is newer than this app version');
      }
    },
  );

  static Future<AppDatabase> openEncrypted({
    FlutterSecureStorage? secureStorage,
    Directory? documentsDirectory,
  }) async {
    const storage = FlutterSecureStorage();
    final keyStore = secureStorage ?? storage;
    final directory =
        documentsDirectory ?? await getApplicationDocumentsDirectory();
    final file = File(path.join(directory.path, 'luna_cycle.sqlite'));
    final keyName = 'luna_cycle_database_key_v1';
    var encodedKey = await keyStore.read(key: keyName);
    if (encodedKey == null) {
      if (await file.exists()) {
        throw StateError(
          'Database encryption key is missing; existing health data was left untouched.',
        );
      }
      final bytes = List<int>.generate(32, (_) => _secureRandomByte());
      encodedKey = base64Encode(bytes);
      await keyStore.write(key: keyName, value: encodedKey);
    }
    final key = base64Decode(encodedKey);
    if (key.length != 32) throw StateError('Stored database key is invalid');
    final sqlKey = _hex(key);

    return AppDatabase(
      NativeDatabase.createInBackground(
        file,
        setup: (sqlite.Database db) {
          db.execute("PRAGMA key = \"x'$sqlKey'\"");
          final cipher = db.select('PRAGMA cipher;');
          if (cipher.isEmpty) {
            throw StateError('Encrypted SQLite support is unavailable');
          }
          db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }
}

int _secureRandomByte() {
  return _secureRandom.nextInt(256);
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
