import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/database/app_database.dart';
import 'package:luna_cycle/core/database/cycle_repository.dart';
import 'package:luna_cycle/core/updates/android_update_installer.dart';
import 'package:luna_cycle/core/updates/github_update_repository.dart';
import 'package:luna_cycle/core/updates/update_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'foreground update flow verifies APK and waits for install permission',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final settings = CycleRepository(database);
      final temp = await Directory.systemTemp.createTemp('luna-update-test-');
      final channel = const MethodChannel('app.lunacycle/update_installer');
      var installAllowed = false;
      var installStarted = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'getDeviceInfo':
                return {
                  'applicationId': lunaApplicationId,
                  'versionName': '1.0.0',
                  'versionCode': 2,
                  'androidApiLevel': 35,
                  'signingCertificateSha256': lunaReleaseCertificateSha256,
                };
              case 'inspectApk':
                return {
                  'applicationId': lunaApplicationId,
                  'versionName': '1.1.0',
                  'versionCode': 3,
                  'minAndroidApi': 24,
                  'signingCertificateSha256': lunaReleaseCertificateSha256,
                };
              case 'requestInstallPermission':
                return installAllowed;
              case 'installApk':
                installStarted = true;
                return null;
              default:
                throw PlatformException(code: 'not_implemented');
            }
          });

      final apk = Uint8List.fromList(utf8.encode('release apk test payload'));
      final apkDigest = await _sha256(apk);
      final manifest = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'formatVersion': 1,
            'applicationId': lunaApplicationId,
            'versionName': '1.1.0',
            'versionCode': 3,
            'minAndroidApi': 24,
            'apkAssetName': 'luna-cycle.apk',
            'apkSha256': apkDigest,
            'releaseNotes': '更新說明',
          }),
        ),
      );
      final manifestDigest = await _sha256(manifest);
      final manifestUri = Uri.https(
        'github.com',
        '/Daniel-LoCY/luna-cycle/releases/download/v1.1.0/update.json',
      );
      final apkUri = Uri.https(
        'github.com',
        '/Daniel-LoCY/luna-cycle/releases/download/v1.1.0/luna-cycle.apk',
      );
      final responses = <String, UpdateHttpResponse>{
        'https://api.github.com/repos/Daniel-LoCY/luna-cycle/releases/latest':
            UpdateHttpResponse(
              statusCode: 200,
              body: Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    'draft': false,
                    'prerelease': false,
                    'assets': [
                      {
                        'name': 'update.json',
                        'state': 'uploaded',
                        'browser_download_url': manifestUri.toString(),
                        'size': manifest.length,
                        'digest': 'sha256:$manifestDigest',
                      },
                      {
                        'name': 'luna-cycle.apk',
                        'state': 'uploaded',
                        'browser_download_url': apkUri.toString(),
                        'size': apk.length,
                        'digest': 'sha256:$apkDigest',
                      },
                    ],
                  }),
                ),
              ),
            ),
        manifestUri.toString(): UpdateHttpResponse(
          statusCode: 200,
          body: manifest,
        ),
        apkUri.toString(): UpdateHttpResponse(statusCode: 200, body: apk),
      };
      final updates = GitHubUpdateRepository(
        fetcher: (uri, headers, maxBytes) async => responses[uri.toString()]!,
      );
      final manager = UpdateManager(
        settings: settings,
        repository: updates,
        installer: AndroidUpdateInstaller(channel: channel),
        temporaryDirectory: () async => temp,
      );

      await manager.saveDisclosure(automaticChecksEnabled: true);
      final update = await manager.checkIfDue();
      expect(update?.versionCode, 3);
      final preparationPhases = <UpdatePreparationPhase>[];
      final downloadProgress = <(int, int)>[];
      final downloaded = await manager.downloadAndVerify(
        onPhase: preparationPhases.add,
        onProgress: (received, total) =>
            downloadProgress.add((received, total)),
      );
      expect(preparationPhases, [
        UpdatePreparationPhase.downloading,
        UpdatePreparationPhase.verifying,
        UpdatePreparationPhase.checkingCompatibility,
      ]);
      expect(downloadProgress, [(apk.length, apk.length)]);
      expect(await downloaded.file.exists(), isTrue);
      final permissionPhases = <UpdateInstallPhase>[];
      expect(
        await manager.installDownloaded(onPhase: permissionPhases.add),
        UpdateInstallResult.permissionRequired,
      );
      expect(permissionPhases, [
        UpdateInstallPhase.verifying,
        UpdateInstallPhase.checkingCompatibility,
        UpdateInstallPhase.requestingPermission,
      ]);
      expect(installStarted, isFalse);
      installAllowed = true;
      final installPhases = <UpdateInstallPhase>[];
      expect(
        await manager.installDownloaded(onPhase: installPhases.add),
        UpdateInstallResult.installerStarted,
      );
      expect(installPhases, [
        UpdateInstallPhase.verifying,
        UpdateInstallPhase.checkingCompatibility,
        UpdateInstallPhase.requestingPermission,
        UpdateInstallPhase.handingOff,
      ]);
      expect(installStarted, isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await temp.delete(recursive: true);
      await database.close();
    },
  );
}

Future<String> _sha256(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
