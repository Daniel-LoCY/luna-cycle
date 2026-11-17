import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/cycle_repository.dart';
import 'android_update_installer.dart';
import 'github_update_repository.dart';

enum UpdateInstallResult { permissionRequired, installerStarted }

enum UpdatePreparationPhase { downloading, verifying, checkingCompatibility }

enum UpdateInstallPhase {
  verifying,
  checkingCompatibility,
  requestingPermission,
  handingOff,
}

class DownloadedUpdate {
  const DownloadedUpdate({required this.update, required this.file});

  final AvailableUpdate update;
  final File file;
}

class UpdateManager {
  UpdateManager({
    required this.settings,
    required this.repository,
    required this.installer,
    Future<Directory> Function()? temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final CycleRepository settings;
  final GitHubUpdateRepository repository;
  final AndroidUpdateInstaller installer;
  final Future<Directory> Function() _temporaryDirectory;

  Future<AvailableUpdate?> checkNow() async {
    final now = DateTime.now().toUtc();
    await settings.saveSetting('update_last_check_at', now.toIso8601String());
    try {
      final device = await installer.getDeviceInfo();
      _validateReleaseInstallation(device);
      final update = await repository.checkForUpdate(
        installedVersionCode: device.versionCode,
        androidApiLevel: device.androidApiLevel,
      );
      await _saveCheckResult(update);
      return update;
    } catch (error) {
      await settings.saveSetting('update_last_check_status', 'error');
      final errorText = error.toString();
      await settings.saveSetting(
        'update_last_check_error',
        errorText.substring(0, errorText.length > 900 ? 900 : errorText.length),
      );
      rethrow;
    }
  }

  Future<AvailableUpdate?> checkIfDue() async {
    final values = await settings.getSettings();
    if (values['update_disclosure_seen'] != 'true' ||
        values['update_auto_check_enabled'] != 'true') {
      return null;
    }
    final last = DateTime.tryParse(values['update_last_check_at'] ?? '');
    if (last != null &&
        DateTime.now().toUtc().difference(last) < const Duration(hours: 24)) {
      return null;
    }
    return checkNow();
  }

  Future<AvailableUpdate?> storedUpdate() async {
    final encoded = await settings.getSetting('update_available_json');
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      return AvailableUpdate.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<int> getInstalledVersionCode() async =>
      (await installer.getDeviceInfo()).versionCode;

  Future<DateTime?> lastCheckedAt() async => DateTime.tryParse(
    await settings.getSetting('update_last_check_at') ?? '',
  );

  Future<DownloadedUpdate> downloadAndVerify({
    AvailableUpdate? update,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    void Function(UpdatePreparationPhase phase)? onPhase,
  }) async {
    final available = update ?? await storedUpdate();
    if (available == null) throw StateError('目前沒有可下載的更新。');
    final temp = await _temporaryDirectory();
    final updateDirectory = Directory(p.join(temp.path, 'updates'));
    await updateDirectory.create(recursive: true);
    final file = File(
      p.join(updateDirectory.path, 'luna_cycle_${available.versionCode}.apk'),
    );
    try {
      onPhase?.call(UpdatePreparationPhase.downloading);
      await repository.downloadApkToFile(
        available,
        file,
        onProgress: (receivedBytes, totalBytes) =>
            onProgress?.call(receivedBytes, totalBytes),
        onVerificationStarted: () =>
            onPhase?.call(UpdatePreparationPhase.verifying),
      );
      onPhase?.call(UpdatePreparationPhase.checkingCompatibility);
      final device = await installer.getDeviceInfo();
      final apk = await installer.inspectApk(file.path);
      validateAndroidUpdateApk(device: device, apk: apk, update: available);
      await settings.saveSetting('update_downloaded_path', file.path);
      await settings.saveSetting(
        'update_downloaded_version_code',
        '${available.versionCode}',
      );
      return DownloadedUpdate(update: available, file: file);
    } catch (_) {
      await file.delete().catchError((_) => file);
      rethrow;
    }
  }

  Future<UpdateInstallResult> installDownloaded({
    void Function(UpdateInstallPhase phase)? onPhase,
  }) async {
    onPhase?.call(UpdateInstallPhase.verifying);
    final update = await storedUpdate();
    final path = await settings.getSetting('update_downloaded_path');
    if (update == null || path == null || path.isEmpty) {
      throw StateError('請先下載並驗證更新檔。');
    }
    final file = File(path);
    if (!await file.exists()) throw StateError('更新檔已不在裝置暫存區，請重新下載。');
    final cachedFile = await _resolveCachedUpdate(path);
    if (cachedFile == null) {
      throw const FormatException('更新檔不在 Luna Cycle 暫存位置。');
    }
    if (await cachedFile.length() > maxUpdateApkBytes) {
      await cachedFile.delete();
      await settings.saveSetting('update_downloaded_path', '');
      throw const FormatException('暫存 APK 超過允許大小，請重新下載。');
    }
    final length = await cachedFile.length();
    if (length != update.apkSize ||
        await sha256FileHex(cachedFile) != update.apkSha256) {
      await cachedFile.delete();
      await settings.saveSetting('update_downloaded_path', '');
      throw const FormatException('暫存 APK 驗證失敗，請重新下載。');
    }
    onPhase?.call(UpdateInstallPhase.checkingCompatibility);
    final device = await installer.getDeviceInfo();
    final apk = await installer.inspectApk(cachedFile.path);
    validateAndroidUpdateApk(device: device, apk: apk, update: update);
    onPhase?.call(UpdateInstallPhase.requestingPermission);
    if (!await installer.requestInstallPermission()) {
      return UpdateInstallResult.permissionRequired;
    }
    onPhase?.call(UpdateInstallPhase.handingOff);
    await installer.installApk(cachedFile.path);
    return UpdateInstallResult.installerStarted;
  }

  Future<void> saveDisclosure({required bool automaticChecksEnabled}) async {
    await settings.saveSetting('update_disclosure_seen', 'true');
    await settings.saveSetting(
      'update_auto_check_enabled',
      '$automaticChecksEnabled',
    );
  }

  Future<void> setAutomaticChecksEnabled(bool enabled) =>
      settings.saveSetting('update_auto_check_enabled', '$enabled');

  Future<void> close() => repository.close();

  Future<void> _saveCheckResult(AvailableUpdate? update) async {
    await settings.saveSetting(
      'update_last_check_status',
      update == null ? 'current' : 'available',
    );
    await settings.saveSetting('update_last_check_error', '');
    final oldPath = await settings.getSetting('update_downloaded_path');
    if (oldPath != null && oldPath.isNotEmpty) {
      await _deleteCachedUpdate(oldPath);
    }
    await settings.saveSetting(
      'update_available_json',
      update == null ? '' : jsonEncode(update.toJson()),
    );
    await settings.saveSetting('update_downloaded_path', '');
    await settings.saveSetting('update_downloaded_version_code', '');
  }

  Future<File?> _resolveCachedUpdate(String path) async {
    try {
      final temp = await _temporaryDirectory();
      final base = Directory(p.join(temp.path, 'updates'));
      if (!await base.exists()) return null;
      final canonicalBase = await base.resolveSymbolicLinks();
      final file = File(path);
      if (!await file.exists()) return null;
      final canonicalFile = await file.resolveSymbolicLinks();
      if (!p.isWithin(canonicalBase, canonicalFile)) return null;
      return File(canonicalFile);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteCachedUpdate(String path) async {
    final file = await _resolveCachedUpdate(path);
    if (file == null) return;
    try {
      await file.delete();
    } catch (_) {
      // Cache cleanup should not block checking for another release.
    }
  }

  void _validateReleaseInstallation(AndroidUpdateDeviceInfo device) {
    if (device.applicationId != lunaApplicationId ||
        device.signingCertificateSha256.toLowerCase() !=
            lunaReleaseCertificateSha256) {
      throw const FormatException('目前安裝版本不是 Luna Cycle 正式簽章版本，無法使用 App 內更新。');
    }
  }
}
