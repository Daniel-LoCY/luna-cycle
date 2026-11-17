import 'package:flutter/services.dart';

class AndroidUpdateDeviceInfo {
  const AndroidUpdateDeviceInfo({
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    required this.androidApiLevel,
    required this.signingCertificateSha256,
  });

  final String applicationId;
  final String versionName;
  final int versionCode;
  final int androidApiLevel;
  final String signingCertificateSha256;

  factory AndroidUpdateDeviceInfo.fromMap(Map<String, Object?> value) =>
      AndroidUpdateDeviceInfo(
        applicationId: value['applicationId'] as String? ?? '',
        versionName: value['versionName'] as String? ?? '',
        versionCode: _integer(value['versionCode']),
        androidApiLevel: _integer(value['androidApiLevel']),
        signingCertificateSha256:
            value['signingCertificateSha256'] as String? ?? '',
      );
}

class AndroidApkInfo {
  const AndroidApkInfo({
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    required this.minAndroidApi,
    required this.signingCertificateSha256,
  });

  final String applicationId;
  final String versionName;
  final int versionCode;
  final int minAndroidApi;
  final String signingCertificateSha256;

  factory AndroidApkInfo.fromMap(Map<String, Object?> value) => AndroidApkInfo(
    applicationId: value['applicationId'] as String? ?? '',
    versionName: value['versionName'] as String? ?? '',
    versionCode: _integer(value['versionCode']),
    minAndroidApi: _integer(value['minAndroidApi']),
    signingCertificateSha256:
        value['signingCertificateSha256'] as String? ?? '',
  );
}

class AndroidUpdateInstaller {
  AndroidUpdateInstaller({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('app.lunacycle/update_installer');

  final MethodChannel _channel;

  Future<AndroidUpdateDeviceInfo> getDeviceInfo() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'getDeviceInfo',
    );
    if (value == null) throw StateError('無法讀取 Android 版本資訊。');
    return AndroidUpdateDeviceInfo.fromMap(value);
  }

  Future<AndroidApkInfo> inspectApk(String path) async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'inspectApk',
      {'path': path},
    );
    if (value == null) throw StateError('無法讀取更新 APK。');
    return AndroidApkInfo.fromMap(value);
  }

  Future<bool> requestInstallPermission() async =>
      await _channel.invokeMethod<bool>('requestInstallPermission') ?? false;

  Future<void> installApk(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});
}

int _integer(Object? value) =>
    value is int ? value : int.tryParse('$value') ?? 0;
