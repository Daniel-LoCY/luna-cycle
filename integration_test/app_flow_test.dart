import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:luna_cycle/main.dart' as luna;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the offline app and visits all five main tabs', (
    tester,
  ) async {
    await luna.main();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    for (
      var attempt = 0;
      attempt < 8 &&
          find.text('略過設定').evaluate().isEmpty &&
          find.byType(NavigationBar).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }

    final skipOnboarding = find.text('略過設定');
    if (find.byType(NavigationBar).evaluate().isEmpty &&
        skipOnboarding.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        skipOnboarding,
        400,
        scrollable: find.byType(Scrollable).first,
      );
    }
    if (skipOnboarding.evaluate().isNotEmpty) {
      await tester.tap(skipOnboarding);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    for (
      var attempt = 0;
      attempt < 8 && find.byType(NavigationBar).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }

    if (find.byType(NavigationBar).evaluate().isEmpty) {
      final visibleText = find
          .byType(Text)
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .whereType<String>()
          .toList();
      // Integration diagnostics contain static interface copy only.
      // ignore: avoid_print
      print('Visible screen text: $visibleText');
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    final updateDisclosure = find.byType(AlertDialog);
    if (updateDisclosure.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: updateDisclosure, matching: find.text('每日自動檢查')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    for (final tab in ['首頁', '日曆', '記錄', '分析', '我的']) {
      final destination = find.text(tab).last;
      await tester.tap(destination);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text(tab).last, findsOneWidget);
    }
    expect(find.text('資料與備份'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('每日記錄提醒'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('本機提醒'), findsOneWidget);
    await tester.tap(find.text('每日記錄提醒'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final pending = await FlutterLocalNotificationsPlugin()
        .pendingNotificationRequests();
    expect(pending.any((item) => item.id == 3000), isTrue);
  });
}
