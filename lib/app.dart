import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:io';

import 'core/design_system/theme.dart';
import 'core/providers.dart';
import 'package:flutter/services.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/records/records_screen.dart';
import 'features/analysis/analysis_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/settings/app_lock_gate.dart';

GoRouter _createRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const _BootScreen()),
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const OnboardingScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/calendar',
              builder: (_, __) => const CalendarScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/records',
              builder: (_, __) => const RecordsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/analysis',
              builder: (_, __) => const AnalysisScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class LunaCycleApp extends ConsumerStatefulWidget {
  const LunaCycleApp({super.key});

  @override
  ConsumerState<LunaCycleApp> createState() => _LunaCycleAppState();
}

class _LunaCycleAppState extends ConsumerState<LunaCycleApp> {
  late final GoRouter _router = _createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) unawaited(_syncSwitcherPrivacy());
  }

  Future<void> _syncSwitcherPrivacy() async {
    try {
      final enabled =
          await ref
              .read(cycleRepositoryProvider)
              .getSetting('privacy_hide_app_switcher') ==
          'true';
      await const MethodChannel(
        'app.lunacycle/update_installer',
      ).invokeMethod<void>('setSwitcherPrivacyEnabled', {'enabled': enabled});
    } catch (_) {
      // Privacy protection settings are best-effort if the platform channel is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(periodsProvider, (previous, next) {
      if (next.hasValue) {
        unawaited(ref.read(localReminderServiceProvider).rescheduleSafely());
      }
    });
    ref.listen(cycleConfigProvider, (previous, next) {
      if (next.hasValue) {
        unawaited(ref.read(localReminderServiceProvider).rescheduleSafely());
      }
    });
    final storedTheme = ref.watch(themeModeProvider).value ?? 'system';
    final themeMode = switch (storedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'Luna Cycle',
      debugShowCheckedModeBanner: false,
      theme: LunaTheme.light,
      darkTheme: LunaTheme.dark,
      themeMode: themeMode,
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW')],
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}

class _BootScreen extends ConsumerWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complete = ref.watch(onboardingCompleteProvider);
    return complete.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) =>
          Scaffold(body: Center(child: Text('無法讀取本機資料：$error'))),
      data: (done) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.go(done ? '/home' : '/welcome');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class _MainShell extends ConsumerWidget {
  const _MainShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _items = [
    (Icons.home_rounded, '首頁'),
    (Icons.calendar_month_rounded, '日曆'),
    (Icons.edit_note_rounded, '記錄'),
    (Icons.insights_rounded, '分析'),
    (Icons.person_outline_rounded, '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: AppLockGate(child: _UpdateCheckGate(child: navigationShell)),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: [
        for (final item in _items)
          NavigationDestination(icon: Icon(item.$1), label: item.$2),
      ],
    ),
  );
}

class _UpdateCheckGate extends ConsumerStatefulWidget {
  const _UpdateCheckGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends ConsumerState<_UpdateCheckGate>
    with WidgetsBindingObserver {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeUpdateChecks());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) {
      unawaited(_checkIfDue());
    }
  }

  Future<void> _initializeUpdateChecks() async {
    if (_started || !mounted) return;
    _started = true;
    final settings = ref.read(cycleRepositoryProvider);
    final values = await settings.getSettings();
    if (values['update_disclosure_seen'] != 'true') {
      final enabled = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('每日自動檢查更新'),
          content: const Text(
            'Luna Cycle 可每日透過 HTTPS 查詢 GitHub 公開 Release 的版本與 APK 雜湊。查詢不會傳送你的月經日期、症狀、日記或其他健康資料。下載與安裝都需要你手動點選，並由 Android 顯示系統安裝確認。你可隨時在「我的」關閉自動檢查。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('停用自動檢查'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('每日自動檢查'),
            ),
          ],
        ),
      );
      if (!mounted || enabled == null) return;
      await ref
          .read(updateManagerProvider)
          .saveDisclosure(automaticChecksEnabled: enabled);
    }
    await _checkIfDue();
  }

  Future<void> _checkIfDue() async {
    try {
      await ref.read(updateManagerProvider).checkIfDue();
    } catch (_) {
      // The update screen records an in-app status; never interrupt health logging.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
