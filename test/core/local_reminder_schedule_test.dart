import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/notifications/local_reminder_service.dart';

void main() {
  group('adjustForDoNotDisturb', () {
    test('moves a late-night reminder to next morning', () {
      expect(
        adjustForDoNotDisturb(DateTime(2026, 11, 13, 23, 15), 22 * 60, 7 * 60),
        DateTime(2026, 11, 14, 7),
      );
    });

    test('moves an early-morning reminder to same-day end time', () {
      expect(
        adjustForDoNotDisturb(DateTime(2026, 11, 14, 5, 30), 22 * 60, 7 * 60),
        DateTime(2026, 11, 14, 7),
      );
    });

    test('leaves reminders outside quiet hours unchanged', () {
      final reminder = DateTime(2026, 11, 14, 9, 30);
      expect(adjustForDoNotDisturb(reminder, 22 * 60, 7 * 60), reminder);
    });

    test('equal bounds disable the quiet period', () {
      final reminder = DateTime(2026, 11, 14, 23, 30);
      expect(adjustForDoNotDisturb(reminder, 22 * 60, 22 * 60), reminder);
    });
  });

  test('invalid custom reminders are ignored during settings recovery', () {
    expect(CustomLocalReminder.fromJson({'id': 'bad'}), isNull);
    final reminder = CustomLocalReminder.fromJson({
      'id': 17,
      'label': '服用補充品',
      'at': '2026-11-14T20:30:00',
    });
    expect(reminder?.id, 17);
    expect(reminder?.label, '服用補充品');
  });
}
