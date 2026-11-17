import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/features/onboarding/onboarding_screen.dart';

void main() {
  late AppDatabase database;
  late GoRouter router;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('已完成引導', key: Key('home_destination'))),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    await database.close();
  });

  testWidgets('skip saves onboarding completion and enters the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('略過設定'));
    await tester.tap(find.text('略過設定'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_destination')), findsOneWidget);
    final settings = await database.select(database.appSettings).get();
    expect(
      settings
          .singleWhere((setting) => setting.key == 'onboarding_complete')
          .value,
      'true',
    );
    expect(
      settings
          .singleWhere((setting) => setting.key == 'prediction_enabled')
          .value,
      'true',
    );
  });
}
