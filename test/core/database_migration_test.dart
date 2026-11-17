import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:luna_cycle/core/database/app_database.dart';

void main() {
  test(
    'schema v1 upgrades with data preserved and new fields defaulted',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'luna-cycle-migration-',
      );
      final file = File(path.join(directory.path, 'legacy.sqlite'));
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE daily_logs (
        id TEXT NOT NULL PRIMARY KEY,
        day INTEGER NOT NULL UNIQUE,
        pain_level INTEGER,
        symptoms_json TEXT NOT NULL DEFAULT '[]',
        moods_json TEXT NOT NULL DEFAULT '[]',
        body_json TEXT NOT NULL DEFAULT '{}',
        reproductive_json TEXT NOT NULL DEFAULT '{}',
        medication_json TEXT NOT NULL DEFAULT '[]',
        tags_json TEXT NOT NULL DEFAULT '[]',
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'local'
      )
    ''');
      legacy.execute('''
      INSERT INTO daily_logs (id, day, symptoms_json, moods_json, body_json,
        reproductive_json, medication_json, tags_json, created_at, updated_at)
      VALUES ('legacy-log', 0, '["頭痛"]', '["平靜"]', '{}', '{}', '[]', '[]', 0, 0)
    ''');
      legacy.execute('PRAGMA user_version = 1');
      legacy.close();
      final database = AppDatabase(NativeDatabase(file));

      try {
        final log = await database.select(database.dailyLogs).getSingle();
        expect(log.id, 'legacy-log');
        expect(log.symptomsJson, '["頭痛"]');
        expect(log.flow, isNull);
        expect(log.spotting, isFalse);
        expect(log.clots, isFalse);
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'schema v2 creates medication tables without touching health records',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'luna-cycle-migration-v2-',
      );
      final file = File(path.join(directory.path, 'legacy-v2.sqlite'));
      final legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE daily_logs (
        id TEXT NOT NULL PRIMARY KEY,
        day INTEGER NOT NULL UNIQUE,
        pain_level INTEGER,
        flow TEXT,
        spotting INTEGER NOT NULL DEFAULT 0,
        clots INTEGER NOT NULL DEFAULT 0,
        symptoms_json TEXT NOT NULL DEFAULT '[]',
        moods_json TEXT NOT NULL DEFAULT '[]',
        body_json TEXT NOT NULL DEFAULT '{}',
        reproductive_json TEXT NOT NULL DEFAULT '{}',
        medication_json TEXT NOT NULL DEFAULT '[]',
        tags_json TEXT NOT NULL DEFAULT '[]',
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        sync_state TEXT NOT NULL DEFAULT 'local'
      )
    ''');
      legacy.execute('''
      INSERT INTO daily_logs (id, day, symptoms_json, created_at, updated_at)
      VALUES ('v2-kept', 0, '["頭痛"]', 0, 0)
    ''');
      legacy.execute('PRAGMA user_version = 2');
      legacy.close();

      final database = AppDatabase(NativeDatabase(file));
      try {
        final log = await database.select(database.dailyLogs).getSingle();
        expect(log.id, 'v2-kept');
        expect(log.symptomsJson, '["頭痛"]');
        final tables = await database
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((row) => row.read<String>('name'))
            .get();
        expect(tables, contains('medication_schedules'));
        expect(tables, contains('medication_intake_entries'));
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
