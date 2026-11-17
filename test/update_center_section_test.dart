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
      releaseNotes: List.filled(
        12,
        '這是一段很長的更新說明，讓下載按鈕位於可捲動頁面的下方。',
      ).join('\n\n'),
    );
    await settings.saveSetting(
      'update_available_json',
      jsonEncode(update.toJson()),
    );
    await settings.saveSetting('update_auto_check_enabled', 'false');
    await settings.saveSetting('update_disclosure_seen', 'true');

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

    final downloadButton = find.text('下載並驗證 APK');
    expect(downloadButton, findsOneWidget);
    await tester.ensureVisible(downloadButton);
    await tester.pumpAndSettle();
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pumpAndSettle();

    final progressMessage = tester.getRect(find.text('正在下載 APK…'));
    expect(progressMessage.top, greaterThanOrEqualTo(0));
    expect(progressMessage.bottom, lessThanOrEqualTo(640));

    manager.completeDownload();
    await tester.pumpAndSettle();
  });
}

class _PendingDownloadManager extends UpdateManager {
  _PendingDownloadManager(CycleRepository settings)
    : super(
        settings: settings,
        repository: GitHubUpdateRepository(),
        installer: AndroidUpdateInstaller(),
      );

  final _downloadFinished = Completer<void>();

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
