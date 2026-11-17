import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'android_update_installer.dart';

const lunaApplicationId = 'app.lunacycle.personal';
const lunaReleaseCertificateSha256 =
    '909ab7d2ac94094284335763e26246acf716376b1b2844867dbcf1b0cfb0b1d5';

const _maxManifestBytes = 64 * 1024;
const maxUpdateApkBytes = 250 * 1024 * 1024;
const _allowedDownloadHosts = {
  'github.com',
  'release-assets.githubusercontent.com',
  'objects.githubusercontent.com',
};

typedef UpdateFetcher =
    Future<UpdateHttpResponse> Function(
      Uri uri,
      Map<String, String> headers,
      int maxBytes,
    );

class UpdateHttpResponse {
  const UpdateHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Uint8List body;
}

class AvailableUpdate {
  const AvailableUpdate({
    required this.versionName,
    required this.versionCode,
    required this.minAndroidApi,
    required this.apkAssetName,
    required this.apkUri,
    required this.apkSha256,
    required this.apkSize,
    required this.releaseNotes,
  });

  final String versionName;
  final int versionCode;
  final int minAndroidApi;
  final String apkAssetName;
  final Uri apkUri;
  final String apkSha256;
  final int apkSize;
  final String releaseNotes;

  Map<String, Object?> toJson() => {
    'versionName': versionName,
    'versionCode': versionCode,
    'minAndroidApi': minAndroidApi,
    'apkAssetName': apkAssetName,
    'apkUri': apkUri.toString(),
    'apkSha256': apkSha256,
    'apkSize': apkSize,
    'releaseNotes': releaseNotes.length <= 500
        ? releaseNotes
        : releaseNotes.substring(0, 500),
  };

  static AvailableUpdate fromJson(Map<String, dynamic> json) {
    final uri = Uri.tryParse(json['apkUri'] as String? ?? '');
    if (uri == null || !_isSafeDownloadUri(uri)) {
      throw const FormatException('更新下載網址不安全。');
    }
    return AvailableUpdate(
      versionName: _requiredString(json['versionName'], 'versionName', 80),
      versionCode: _requiredInt(
        json['versionCode'],
        'versionCode',
        1,
        0x7fffffff,
      ),
      minAndroidApi: _requiredInt(
        json['minAndroidApi'],
        'minAndroidApi',
        24,
        200,
      ),
      apkAssetName: _requiredString(json['apkAssetName'], 'apkAssetName', 160),
      apkUri: uri,
      apkSha256: _requiredSha256(json['apkSha256'], 'apkSha256'),
      apkSize: _requiredInt(json['apkSize'], 'apkSize', 1, maxUpdateApkBytes),
      releaseNotes: _optionalString(json['releaseNotes'], 20000),
    );
  }
}

class GitHubUpdateRepository {
  GitHubUpdateRepository({
    String owner = const String.fromEnvironment(
      'LUNA_GITHUB_OWNER',
      defaultValue: 'Daniel-LoCY',
    ),
    String repository = const String.fromEnvironment(
      'LUNA_GITHUB_REPOSITORY',
      defaultValue: 'luna-cycle',
    ),
    UpdateFetcher? fetcher,
    HttpClient? httpClient,
  }) : owner = _validateRepositoryPart(owner, 'owner'),
       repository = _validateRepositoryPart(repository, 'repository'),
       _fetcher = fetcher,
       _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 15);
    _httpClient.autoUncompress = false;
  }

  final String owner;
  final String repository;
  final UpdateFetcher? _fetcher;
  final HttpClient _httpClient;

  Future<AvailableUpdate?> checkForUpdate({
    required int installedVersionCode,
    required int androidApiLevel,
  }) async {
    final endpoint = Uri.https(
      'api.github.com',
      '/repos/$owner/$repository/releases/latest',
    );
    final releaseResponse = await _get(endpoint, const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Luna-Cycle-Android',
    }, _maxManifestBytes);
    if (releaseResponse.statusCode == 404) {
      throw const UpdateRepositoryException('目前找不到公開的 GitHub Release 更新來源。');
    }
    if (releaseResponse.statusCode != 200) {
      throw UpdateRepositoryException(
        'GitHub Release 查詢失敗（HTTP ${releaseResponse.statusCode}）。',
      );
    }

    final release = _decodeObject(releaseResponse.body, 'GitHub Release');
    if (release['draft'] == true || release['prerelease'] == true) {
      throw const FormatException('更新來源不是正式發布版本。');
    }
    final assets = release['assets'];
    if (assets is! List) throw const FormatException('Release 缺少檔案清單。');
    final manifestAsset = _findAsset(assets, 'update.json');
    final manifestResponse = await _get(_assetUri(manifestAsset), const {
      'User-Agent': 'Luna-Cycle-Android',
    }, _maxManifestBytes);
    if (manifestResponse.statusCode != 200) {
      throw UpdateRepositoryException(
        '更新資訊下載失敗（HTTP ${manifestResponse.statusCode}）。',
      );
    }
    await _verifyAssetDigest(manifestAsset, manifestResponse.body);
    final manifest = parseManifest(
      manifestBytes: manifestResponse.body,
      assets: assets,
      installedVersionCode: installedVersionCode,
      androidApiLevel: androidApiLevel,
    );
    return manifest;
  }

  Future<Uint8List> downloadApk(AvailableUpdate update) async {
    final response = await _get(update.apkUri, const {
      'User-Agent': 'Luna-Cycle-Android',
    }, maxUpdateApkBytes);
    if (response.statusCode != 200) {
      throw UpdateRepositoryException('APK 下載失敗（HTTP ${response.statusCode}）。');
    }
    if (response.body.length != update.apkSize) {
      throw const UpdateRepositoryException('APK 檔案大小與更新資訊不一致。');
    }
    final actualDigest = await sha256Hex(response.body);
    if (actualDigest != update.apkSha256) {
      throw const UpdateRepositoryException('APK SHA-256 驗證失敗，已取消安裝。');
    }
    return response.body;
  }

  Future<void> downloadApkToFile(
    AvailableUpdate update,
    File destination, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
    required void Function() onVerificationStarted,
  }) async {
    if (_fetcher != null) {
      final bytes = await downloadApk(update);
      await destination.writeAsBytes(bytes, flush: true);
      onProgress(bytes.length, update.apkSize);
      onVerificationStarted();
      return;
    }

    await destination.parent.create(recursive: true);
    var current = update.apkUri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_isAllowedRequestUri(current)) {
        throw const UpdateRepositoryException('更新伺服器網址不安全。');
      }
      final request = await _httpClient
          .getUrl(current)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.userAgentHeader, 'Luna-Cycle-Android');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) {
          await response.detachSocket().then((socket) => socket.destroy());
          throw const UpdateRepositoryException('更新下載重新導向無效。');
        }
        await response.detachSocket().then((socket) => socket.destroy());
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.detachSocket().then((socket) => socket.destroy());
        throw UpdateRepositoryException(
          'APK 下載失敗（HTTP ${response.statusCode}）。',
        );
      }
      if (response.contentLength > maxUpdateApkBytes ||
          (response.contentLength >= 0 &&
              response.contentLength != update.apkSize)) {
        await response.detachSocket().then((socket) => socket.destroy());
        throw const UpdateRepositoryException('APK 檔案大小與更新資訊不一致。');
      }

      final fileSink = destination.openWrite();
      final hashSink = Sha256().toSync().newHashSink();
      var receivedBytes = 0;
      var sinkClosed = false;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          receivedBytes += chunk.length;
          if (receivedBytes > update.apkSize ||
              receivedBytes > maxUpdateApkBytes) {
            await response.detachSocket().then((socket) => socket.destroy());
            throw const UpdateRepositoryException('APK 檔案大小與更新資訊不一致。');
          }
          fileSink.add(chunk);
          hashSink.add(chunk);
          onProgress(receivedBytes, update.apkSize);
        }
        await fileSink.flush();
        await fileSink.close();
        sinkClosed = true;
        if (receivedBytes != update.apkSize) {
          throw const UpdateRepositoryException('APK 檔案大小與更新資訊不一致。');
        }
        onVerificationStarted();
        hashSink.close();
        if (_hex(hashSink.hashBytes) != update.apkSha256) {
          throw const UpdateRepositoryException('APK SHA-256 驗證失敗，已取消安裝。');
        }
        return;
      } catch (_) {
        if (!sinkClosed) {
          await fileSink.close().catchError((_) {});
        }
        await destination.delete().catchError((_) => destination);
        rethrow;
      }
    }
    throw const UpdateRepositoryException('更新下載重新導向次數過多。');
  }

  Future<void> close() async {
    if (_fetcher == null) _httpClient.close(force: true);
  }

  static AvailableUpdate? parseManifest({
    required Uint8List manifestBytes,
    required List<dynamic> assets,
    required int installedVersionCode,
    required int androidApiLevel,
  }) {
    if (manifestBytes.isEmpty || manifestBytes.length > _maxManifestBytes) {
      throw const FormatException('更新資訊檔案大小不正確。');
    }
    final manifest = _decodeObject(manifestBytes, '更新資訊');
    if (manifest['formatVersion'] != 1) {
      throw const FormatException('不支援的更新資訊版本。');
    }
    if (manifest['applicationId'] != lunaApplicationId) {
      throw const FormatException('更新套件識別碼不相符。');
    }
    final versionName = _requiredString(
      manifest['versionName'],
      'versionName',
      80,
    );
    final versionCode = _requiredInt(
      manifest['versionCode'],
      'versionCode',
      1,
      0x7fffffff,
    );
    final minAndroidApi = _requiredInt(
      manifest['minAndroidApi'],
      'minAndroidApi',
      24,
      200,
    );
    if (minAndroidApi > androidApiLevel) {
      throw const FormatException('此更新不支援目前的 Android 版本。');
    }
    if (versionCode <= installedVersionCode) return null;

    final apkName = _requiredString(
      manifest['apkAssetName'],
      'apkAssetName',
      160,
    );
    final apkAsset = _findAsset(assets, apkName);
    final apkUri = _assetUri(apkAsset);
    final apkSize = _requiredInt(
      apkAsset['size'],
      'APK size',
      1,
      maxUpdateApkBytes,
    );
    final apkSha256 = _requiredSha256(manifest['apkSha256'], 'apkSha256');
    _verifyDeclaredDigest(apkAsset, apkSha256);
    return AvailableUpdate(
      versionName: versionName,
      versionCode: versionCode,
      minAndroidApi: minAndroidApi,
      apkAssetName: apkName,
      apkUri: apkUri,
      apkSha256: apkSha256,
      apkSize: apkSize,
      releaseNotes: _optionalString(manifest['releaseNotes'], 20000),
    );
  }

  Future<UpdateHttpResponse> _get(
    Uri uri,
    Map<String, String> headers,
    int maxBytes,
  ) async {
    var current = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_isAllowedRequestUri(current)) {
        throw const UpdateRepositoryException('更新伺服器網址不安全。');
      }
      final injected = _fetcher;
      if (injected != null) {
        final response = await injected(current, headers, maxBytes);
        if (response.body.length > maxBytes) {
          throw const UpdateRepositoryException('更新檔案超過允許大小。');
        }
        return response;
      }
      final request = await _httpClient
          .getUrl(current)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, headers['Accept'] ?? '*/*');
      request.headers.set(HttpHeaders.userAgentHeader, headers['User-Agent']!);
      final apiVersion = headers['X-GitHub-Api-Version'];
      if (apiVersion != null)
        request.headers.set('X-GitHub-Api-Version', apiVersion);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) {
          throw const UpdateRepositoryException('更新下載重新導向無效。');
        }
        await response.drain<void>();
        current = current.resolve(location);
        continue;
      }
      final body = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        length += chunk.length;
        if (length > maxBytes) {
          await response.detachSocket().then((socket) => socket.destroy());
          throw const UpdateRepositoryException('更新檔案超過允許大小。');
        }
        body.add(chunk);
      }
      return UpdateHttpResponse(
        statusCode: response.statusCode,
        body: body.takeBytes(),
      );
    }
    throw const UpdateRepositoryException('更新下載重新導向次數過多。');
  }
}

class UpdateRepositoryException implements Exception {
  const UpdateRepositoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

void validateAndroidUpdateApk({
  required AndroidUpdateDeviceInfo device,
  required AndroidApkInfo apk,
  required AvailableUpdate update,
}) {
  if (device.applicationId != lunaApplicationId ||
      apk.applicationId != lunaApplicationId) {
    throw const FormatException('APK 套件識別碼不符，已取消更新。');
  }
  if (device.signingCertificateSha256.toLowerCase() !=
          lunaReleaseCertificateSha256 ||
      apk.signingCertificateSha256.toLowerCase() !=
          lunaReleaseCertificateSha256 ||
      device.signingCertificateSha256.toLowerCase() !=
          apk.signingCertificateSha256.toLowerCase()) {
    throw const FormatException('APK 簽章指紋不符，已取消更新。');
  }
  if (apk.versionName != update.versionName ||
      apk.versionCode != update.versionCode ||
      apk.minAndroidApi != update.minAndroidApi ||
      apk.versionCode <= device.versionCode ||
      apk.minAndroidApi > device.androidApiLevel) {
    throw const FormatException('APK 版本資訊不符或不支援此裝置。');
  }
}

Map<String, dynamic> _decodeObject(List<int> bytes, String label) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$label 格式不正確。');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw FormatException('$label 無法讀取。');
  }
}

Map<String, dynamic> _findAsset(List<dynamic> assets, String name) {
  for (final value in assets) {
    if (value is Map<String, dynamic> && value['name'] == name) return value;
  }
  throw FormatException('Release 缺少 $name。');
}

Uri _assetUri(Map<String, dynamic> asset) {
  if (asset['state'] != null && asset['state'] != 'uploaded') {
    throw const FormatException('更新檔案尚未完整上傳。');
  }
  final uri = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
  if (uri == null || !_isSafeDownloadUri(uri)) {
    throw const FormatException('Release 檔案網址不安全。');
  }
  return uri;
}

bool _isAllowedRequestUri(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'api.github.com' ||
        _allowedDownloadHosts.contains(uri.host)) &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

bool _isSafeDownloadUri(Uri uri) =>
    uri.scheme == 'https' &&
    _allowedDownloadHosts.contains(uri.host) &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

Future<void> _verifyAssetDigest(
  Map<String, dynamic> asset,
  List<int> bytes,
) async {
  final digest = asset['digest'];
  if (digest == null) return;
  if (digest is! String || !digest.startsWith('sha256:')) {
    throw const FormatException('Release 更新資訊的雜湊格式不支援。');
  }
  final expected = digest.substring('sha256:'.length).toLowerCase();
  if (expected != await sha256Hex(bytes)) {
    throw const FormatException('Release 更新資訊雜湊驗證失敗。');
  }
}

void _verifyDeclaredDigest(Map<String, dynamic> asset, String expected) {
  final digest = asset['digest'];
  if (digest == null) return;
  if (digest is! String || digest.toLowerCase() != 'sha256:$expected') {
    throw const FormatException('GitHub APK 雜湊與更新資訊不一致。');
  }
}

Future<String> sha256Hex(List<int> bytes) async =>
    _hex((await Sha256().hash(bytes)).bytes);

Future<String> sha256FileHex(File file) async {
  final hashSink = Sha256().toSync().newHashSink();
  await for (final chunk in file.openRead()) {
    hashSink.add(chunk);
  }
  hashSink.close();
  return _hex(hashSink.hashBytes);
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String _validateRepositoryPart(String value, String name) {
  if (!RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'Invalid GitHub repository part');
  }
  return value;
}

String _requiredString(Object? value, String name, int maxLength) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('更新欄位 $name 不正確。');
  }
  return value;
}

String _optionalString(Object? value, int maxLength) {
  if (value == null) return '';
  if (value is! String || value.length > maxLength) {
    throw const FormatException('更新說明格式不正確。');
  }
  return value;
}

int _requiredInt(Object? value, String name, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('更新欄位 $name 不正確。');
  }
  return value;
}

String _requiredSha256(Object? value, String name) {
  if (value is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value)) {
    throw FormatException('更新欄位 $name 雜湊格式不正確。');
  }
  return value.toLowerCase();
}
