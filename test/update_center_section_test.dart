import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';
import 'package:luna_cycle/core/providers.dart';
import 'package:luna_cycle/core/updates/android_update_installer.dart';
import 'package:luna_cycle/core/updates/github_update_repository.dart';
import 'package:luna_cycle/core/updates/update_manager.dart';
import 'package:luna_cycle/features/settings/update_center_section.dart';

void main() {
  testWidgets('hides a cached release already installed on the device', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final database = AppDatabase(NativeDatabase.memory());
    final settings = CycleRepository(database);
    final update = AvailableUpdate(
      versionName: '1.1.3',
      versionCode: 6,
      minAndroidApi: 24,
      apkAssetName: 'test.apk',
      apkUri: Uri.https(
        'github.com',
        '/Daniel-LoCY/luna-cycle/releases/download/v1.1.3/test.apk',
      ),
      apkSha256: List.filled(64, 'a').join(),
      apkSize: 4096,
      releaseNotes: '- 這是已安裝版本的更新說明。',
    );
    await settings.saveSetting(
      'update_available_json',
      jsonEncode(update.toJson()),
    );
    await settings.saveSetting('update_auto_check_enabled', 'false');

    final manager = _PendingDownloadManager(settings, currentVersionCode: 6);
    addTearDown(() async {
      manager.completeDownload();
      await manager.repository.close();
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cycleRepositoryProvider.overrideWithValue(settings),
          updateManagerProvider.overrideWithValue(manager),
        ],
        child: const MaterialApp(home: Scaffold(body: UpdateCenterSection())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('版本 1.1.3（6）'), findsNothing);
    expect(find.text('這是已安裝版本的更新說明。'), findsNothing);
    expect(find.text('下載並驗證 APK'), findsNothing);
    expect(find.text('立即檢查更新'), findsOneWidget);
  });

  testWidgets('scrolls to live download progress after starting an update', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(400, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    final settings = CycleRepository(database);
    final update = AvailableUpdate(
      versionName: '9.9.9',
      versionCode: 999,
      minAndroidApi: 24,
      apkAssetName: 'test.apk',
      apkUri: Uri.https(
        'github.com',
        '/Daniel-LoCY/luna-cycle/releases/download/v9.9.9/test.apk',
      ),
      apkSha256: List.filled(64, 'a').join(),
      apkSize: 4096,
      releaseNotes: List.generate(
        12,
        (index) => '第 ${index + 1} 項更新說明，測試進度是否緊鄰目前版本內容。',
      ).join('\n'),
    );
    await settings.saveSetting(
      'update_available_json',
      jsonEncode(update.toJson()),
    );
    await settings.saveSetting('update_auto_check_enabled', 'false');
    await settings.saveSetting('update_disclosure_seen', 'true');
    await settings.saveSetting('update_last_check_status', 'error');
    await settings.saveSetting('update_last_check_at', '2026-11-16T10:00:00Z');
    await settings.saveSetting('update_last_check_error', '這是上一輪檢查留下的錯誤。');

    final manager = _PendingDownloadManager(settings);
    addTearDown(() async {
      manager.completeDownload();
      await manager.repository.close();
      await database.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cycleRepositoryProvider.overrideWithValue(settings),
          updateManagerProvider.overrideWithValue(manager),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [SizedBox(height: 700), UpdateCenterSection()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('上次檢查：'), findsNothing);
    expect(find.text('這是上一輪檢查留下的錯誤。'), findsNothing);

    final downloadButton = find.text('下載並驗證 APK');
    expect(downloadButton, findsOneWidget);
    await tester.ensureVisible(downloadButton);
    await tester.pumpAndSettle();
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pumpAndSettle();

    final lastReleaseNote = find.textContaining('第 12 項');
    final releaseNoteBottom = tester.getBottomLeft(lastReleaseNote).dy;
    final progressTop = tester
        .getTopLeft(find.byType(LinearProgressIndicator))
        .dy;
    expect(progressTop, greaterThanOrEqualTo(releaseNoteBottom));
    expect(progressTop - releaseNoteBottom, lessThan(120));

    final progressMessage = tester.getRect(find.text('正在下載 APK…'));
    expect(progressMessage.top, greaterThanOrEqualTo(0));
    expect(progressMessage.bottom, lessThanOrEqualTo(640));

    manager.completeDownload();
    await tester.pumpAndSettle();
  });
}

class _PendingDownloadManager extends UpdateManager {
  _PendingDownloadManager(
    CycleRepository settings, {
    this.currentVersionCode = 4,
  }) : super(
         settings: settings,
         repository: GitHubUpdateRepository(),
         installer: AndroidUpdateInstaller(),
       );

  final _downloadFinished = Completer<void>();
  final int currentVersionCode;

  @override
  Future<int> getInstalledVersionCode() async => currentVersionCode;

  @override
  Future<DownloadedUpdate> downloadAndVerify({
    AvailableUpdate? update,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    void Function(UpdatePreparationPhase phase)? onPhase,
  }) async {
    onPhase?.call(UpdatePreparationPhase.downloading);
    onProgress?.call(1024, 4096);
    await _downloadFinished.future;
    return DownloadedUpdate(update: update!, file: File('/unused-test.apk'));
  }

  void completeDownload() {
    if (!_downloadFinished.isCompleted) _downloadFinished.complete();
  }
}
