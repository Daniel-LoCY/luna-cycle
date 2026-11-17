import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'cycle_prediction.dart';
import 'data_management/export_archive_service.dart';
import 'database/app_database.dart';
import 'database/cycle_repository.dart';
import 'notifications/local_reminder_service.dart';
import 'updates/android_update_installer.dart';
import 'updates/github_update_repository.dart';
import 'updates/update_manager.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) =>
      throw UnimplementedError('AppDatabase must be overridden at bootstrap'),
);

final cycleRepositoryProvider = Provider<CycleRepository>(
  (ref) => CycleRepository(ref.watch(databaseProvider)),
);

final exportArchiveServiceProvider = Provider<ExportArchiveService>(
  (ref) => ExportArchiveService(ref.watch(databaseProvider)),
);

final localReminderServiceProvider = Provider<LocalReminderService>(
  (ref) => LocalReminderService(ref.watch(databaseProvider)),
);

final githubUpdateRepositoryProvider = Provider<GitHubUpdateRepository>((ref) {
  final repository = GitHubUpdateRepository();
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});

final androidUpdateInstallerProvider = Provider<AndroidUpdateInstaller>(
  (ref) => AndroidUpdateInstaller(),
);

final updateManagerProvider = Provider<UpdateManager>(
  (ref) => UpdateManager(
    settings: ref.watch(cycleRepositoryProvider),
    repository: ref.watch(githubUpdateRepositoryProvider),
    installer: ref.watch(androidUpdateInstallerProvider),
  ),
);

final periodsProvider = StreamProvider(
  (ref) => ref.watch(cycleRepositoryProvider).watchPeriods(),
);

final dailyLogsProvider = StreamProvider(
  (ref) => ref.watch(cycleRepositoryProvider).watchDailyLogs(),
);

final medicationSchedulesProvider = StreamProvider(
  (ref) => ref.watch(cycleRepositoryProvider).watchMedicationSchedules(),
);

final medicationIntakesProvider = StreamProvider(
  (ref) => ref.watch(cycleRepositoryProvider).watchMedicationIntakes(),
);

final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final rows =
      await (ref
              .watch(databaseProvider)
              .select(ref.watch(databaseProvider).appSettings)
            ..where((setting) => setting.key.equals('onboarding_complete')))
          .get();
  return rows.isNotEmpty && rows.first.value == 'true';
});

class CycleConfig {
  const CycleConfig({
    this.mode = CycleMode.general,
    this.averageCycleLength,
    this.averagePeriodLength,
    this.fertilityEstimatesEnabled = false,
    this.predictionEnabled = true,
  });

  final CycleMode mode;
  final int? averageCycleLength;
  final int? averagePeriodLength;
  final bool fertilityEstimatesEnabled;
  final bool predictionEnabled;
}

final cycleConfigProvider = FutureProvider<CycleConfig>((ref) async {
  final database = ref.watch(databaseProvider);
  final settings = await database.select(database.appSettings).get();
  final byKey = {for (final row in settings) row.key: row.value};
  final mode = switch (byKey['tracking_mode']) {
    '不規律週期' => CycleMode.irregular,
    '備孕' => CycleMode.tryingToConceive,
    '荷爾蒙避孕紀錄' => CycleMode.hormonalContraception,
    '懷孕' => CycleMode.pregnancy,
    '產後' => CycleMode.postpartum,
    '只記錄' => CycleMode.trackingOnly,
    _ => CycleMode.general,
  };
  return CycleConfig(
    mode: mode,
    averageCycleLength: int.tryParse(byKey['average_cycle_length'] ?? ''),
    averagePeriodLength: int.tryParse(byKey['average_period_length'] ?? ''),
    fertilityEstimatesEnabled: byKey['fertility_estimates_enabled'] == 'true',
    predictionEnabled: byKey['prediction_enabled'] != 'false',
  );
});

final themeModeProvider = FutureProvider<String>((ref) async {
  final database = ref.watch(databaseProvider);
  final row = await (database.select(
    database.appSettings,
  )..where((setting) => setting.key.equals('theme_mode'))).getSingleOrNull();
  return switch (row?.value) {
    'light' => 'light',
    'dark' => 'dark',
    _ => 'system',
  };
});

final appLockEnabledProvider = FutureProvider<bool>((ref) async {
  final database = ref.watch(databaseProvider);
  final row =
      await (database.select(database.appSettings)
            ..where((setting) => setting.key.equals('app_lock_enabled')))
          .getSingleOrNull();
  return row?.value == 'true';
});

final appSwitcherPrivacyProvider = FutureProvider<bool>((ref) async {
  final repository = ref.watch(cycleRepositoryProvider);
  return await repository.getSetting('privacy_hide_app_switcher') == 'true';
});
