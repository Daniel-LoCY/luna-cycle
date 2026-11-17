import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../async_serial_queue.dart';
import '../cycle_prediction.dart';
import '../database/app_database.dart';

class CustomLocalReminder {
  const CustomLocalReminder({
    required this.id,
    required this.label,
    required this.at,
  });

  final int id;
  final String label;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'at': at.toIso8601String(),
  };

  static CustomLocalReminder? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final label = value['label'];
    final at = value['at'];
    if (id is! int ||
        id < 0 ||
        label is! String ||
        label.length > 100 ||
        at is! String) {
      return null;
    }
    final date = DateTime.tryParse(at);
    return date == null
        ? null
        : CustomLocalReminder(id: id, label: label, at: date);
  }
}

class LocalReminderService {
  LocalReminderService(this.database, {FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final AppDatabase database;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  Future<void>? _initialization;
  tz.Location? _location;
  final _rescheduleQueue = AsyncSerialQueue();

  Future<bool> requestPermission() async {
    await _ensureInitialized();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<void> reschedule() => _rescheduleQueue.run(_rescheduleNow);

  Future<void> _rescheduleNow() async {
    final settingsRows = await database.select(database.appSettings).get();
    final settings = {for (final row in settingsRows) row.key: row.value};
    final custom = _readCustom(settings['custom_reminders_json']);
    final medicationSchedules =
        (await (database.select(database.medicationSchedules)..where(
                  (schedule) =>
                      schedule.deletedAt.isNull() &
                      schedule.enabled.equals(true),
                ))
                .get())
            .where(
              (schedule) => _readMedicationTimes(schedule.timesJson).isNotEmpty,
            );
    final periodEnabled = settings['period_reminder_enabled'] == 'true';
    final dailyEnabled = settings['daily_reminder_enabled'] == 'true';
    if (!periodEnabled &&
        !dailyEnabled &&
        custom.isEmpty &&
        medicationSchedules.isEmpty) {
      await _ensureInitialized();
      await _plugin.cancelAll();
      return;
    }
    await _ensureInitialized();
    await _refreshTimeZone();
    await _plugin.cancelAll();

    final dndStart = _parseMinute(settings['dnd_start']) ?? 22 * 60;
    final dndEnd = _parseMinute(settings['dnd_end']) ?? 7 * 60;
    final notificationDetails = _notificationDetails();

    if (periodEnabled) {
      final periods = await (database.select(
        database.periods,
      )..where((period) => period.deletedAt.isNull())).get();
      final mode = _parseMode(settings['tracking_mode']);
      final prediction = predictCycles(
        periods: [
          for (final period in periods)
            PeriodRecord(start: period.startDate, end: period.endDate),
        ],
        mode: mode,
        configuredCycleLength: int.tryParse(
          settings['average_cycle_length'] ?? '',
        ),
        configuredPeriodLength: int.tryParse(
          settings['average_period_length'] ?? '',
        ),
        fertilityEstimatesEnabled: false,
        predictionEnabled: settings['prediction_enabled'] != 'false',
        forecastCount: 6,
      );
      final daysBefore =
          int.tryParse(settings['period_reminder_days'] ?? '')?.clamp(1, 14) ??
          2;
      final minute = _parseMinute(settings['period_reminder_time']) ?? 9 * 60;
      for (var index = 0; index < prediction.nextStarts.length; index++) {
        final range = prediction.nextStarts[index];
        final middle = range.earliest.add(
          Duration(days: range.latest.difference(range.earliest).inDays ~/ 2),
        );
        final dayBefore = DateTime(
          middle.year,
          middle.month,
          middle.day - daysBefore,
        );
        final beforeAt = DateTime(
          dayBefore.year,
          dayBefore.month,
          dayBefore.day,
          minute ~/ 60,
          minute % 60,
        );
        final startAt = DateTime(
          middle.year,
          middle.month,
          middle.day,
          minute ~/ 60,
          minute % 60,
        );
        await _scheduleAt(
          id: 2000 + index * 2,
          date: beforeAt,
          details: notificationDetails,
          dndStart: dndStart,
          dndEnd: dndEnd,
        );
        await _scheduleAt(
          id: 2001 + index * 2,
          date: startAt,
          details: notificationDetails,
          dndStart: dndStart,
          dndEnd: dndEnd,
        );
      }
    }

    if (dailyEnabled) {
      final minute = _parseMinute(settings['daily_reminder_time']) ?? 20 * 60;
      final next = _nextDailyDate(minute, dndStart, dndEnd);
      await _plugin.zonedSchedule(
        id: 3000,
        title: 'Luna Cycle',
        body: '今天有一則個人提醒。',
        scheduledDate: _asTz(next),
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    for (final reminder in custom) {
      await _scheduleAt(
        id: 4000 + _stableId(reminder.id),
        date: reminder.at,
        details: notificationDetails,
        dndStart: dndStart,
        dndEnd: dndEnd,
      );
    }

    for (final schedule in medicationSchedules) {
      final times = _readMedicationTimes(schedule.timesJson);
      for (var index = 0; index < times.length; index++) {
        await _scheduleMedicationDaily(
          id: 0x40000000 + _stableTextId('${schedule.id}:$index'),
          time: times[index],
          details: notificationDetails,
          dndStart: dndStart,
          dndEnd: dndEnd,
        );
      }
    }
  }

  Future<void> rescheduleSafely() async {
    try {
      await reschedule();
      await _saveScheduleStatus('ready');
    } catch (_) {
      await _saveScheduleStatus('needs_attention');
    }
  }

  Future<void> _saveScheduleStatus(String status) => database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'reminder_schedule_status',
          value: status,
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> _ensureInitialized() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    await _refreshTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<void> _refreshTimeZone() async {
    final zone = await FlutterTimezone.getLocalTimezone();
    _location = tz.getLocation(zone.identifier);
  }

  Future<void> _scheduleAt({
    required int id,
    required DateTime date,
    required NotificationDetails details,
    required int dndStart,
    required int dndEnd,
  }) async {
    var adjusted = adjustForDoNotDisturb(date, dndStart, dndEnd);
    if (!adjusted.isAfter(DateTime.now())) return;
    adjusted = DateTime(
      adjusted.year,
      adjusted.month,
      adjusted.day,
      adjusted.hour,
      adjusted.minute,
    );
    await _plugin.zonedSchedule(
      id: id,
      title: 'Luna Cycle',
      body: '你設定的提醒時間到了。',
      scheduledDate: _asTz(adjusted),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> _scheduleMedicationDaily({
    required int id,
    required String time,
    required NotificationDetails details,
    required int dndStart,
    required int dndEnd,
  }) async {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time);
    if (match == null) return;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return;
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    next = adjustForDoNotDisturb(next, dndStart, dndEnd);
    if (!next.isAfter(now)) {
      next = adjustForDoNotDisturb(
        next.add(const Duration(days: 1)),
        dndStart,
        dndEnd,
      );
    }
    await _plugin.zonedSchedule(
      id: id,
      title: 'Luna Cycle',
      body: '你設定的提醒時間到了。',
      scheduledDate: _asTz(next),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  DateTime _nextDailyDate(int minute, int dndStart, int dndEnd) {
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      minute ~/ 60,
      minute % 60,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    next = adjustForDoNotDisturb(next, dndStart, dndEnd);
    if (!next.isAfter(now)) {
      next = adjustForDoNotDisturb(
        next.add(const Duration(days: 1)),
        dndStart,
        dndEnd,
      );
    }
    return next;
  }

  tz.TZDateTime _asTz(DateTime value) {
    final location = _location;
    if (location == null) throw StateError('通知時區尚未初始化');
    return tz.TZDateTime(
      location,
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  static NotificationDetails _notificationDetails() =>
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'luna_cycle_reminders',
          '個人提醒',
          channelDescription: 'Luna Cycle 的週期與記錄提醒。通知內容不包含健康紀錄。',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      );

  static int _stableId(int value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value.toString())) {
      hash = ((hash ^ byte) * 16777619) & 0x3fffffff;
    }
    return hash;
  }

  static int _stableTextId(String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ byte) * 16777619) & 0x3fffffff;
    }
    return hash;
  }

  static List<String> _readMedicationTimes(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List || decoded.length > 8) return const [];
      return decoded.whereType<String>().where((time) {
        final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time);
        if (match == null) return false;
        return int.parse(match.group(1)!) <= 23 &&
            int.parse(match.group(2)!) <= 59;
      }).toList();
    } on FormatException {
      return const [];
    }
  }

  static List<CustomLocalReminder> _readCustom(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded
          .map(CustomLocalReminder.fromJson)
          .whereType<CustomLocalReminder>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  static int? _parseMinute(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static CycleMode _parseMode(String? value) => switch (value) {
    '不規律週期' => CycleMode.irregular,
    '備孕' => CycleMode.tryingToConceive,
    '荷爾蒙避孕紀錄' => CycleMode.hormonalContraception,
    '懷孕' => CycleMode.pregnancy,
    '產後' => CycleMode.postpartum,
    '只記錄' => CycleMode.trackingOnly,
    _ => CycleMode.general,
  };
}

/// Moves a local reminder out of the configured quiet-time interval.
/// Minutes are from midnight; equal start/end values disable the interval.
DateTime adjustForDoNotDisturb(DateTime value, int startMinute, int endMinute) {
  if (startMinute == endMinute) return value;
  final minute = value.hour * 60 + value.minute;
  final crossesMidnight = startMinute > endMinute;
  final inside = crossesMidnight
      ? minute >= startMinute || minute < endMinute
      : minute >= startMinute && minute < endMinute;
  if (!inside) return value;
  final endHour = endMinute ~/ 60;
  final endMin = endMinute % 60;
  final nextDay = crossesMidnight && minute >= startMinute;
  return DateTime(
    value.year,
    value.month,
    value.day + (nextDay ? 1 : 0),
    endHour,
    endMin,
  );
}
