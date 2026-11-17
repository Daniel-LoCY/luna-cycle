import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/updates/android_update_installer.dart';
import 'package:luna_cycle/core/updates/github_update_repository.dart';

void main() {
  test(
    'checks a public release and downloads only a matching APK digest',
    () async {
      final apk = Uint8List.fromList(utf8.encode('test signed apk bytes'));
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
            'releaseNotes': '穩定性改善',
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
      final repository = GitHubUpdateRepository(
        fetcher: (uri, headers, maxBytes) async =>
            responses[uri.toString()] ??
            UpdateHttpResponse(statusCode: 404, body: Uint8List(0)),
      );

      final update = await repository.checkForUpdate(
        installedVersionCode: 2,
        androidApiLevel: 35,
      );
      expect(update?.versionName, '1.1.0');
      expect(update?.versionCode, 3);
      expect(update?.releaseNotes, '穩定性改善');
      expect(await repository.downloadApk(update!), apk);
      await repository.close();
    },
  );

  test('returns no update for an already installed build', () async {
    final apk = Uint8List.fromList([1, 2, 3]);
    final update = _manifest(
      apkName: 'app.apk',
      apkUri:
          'https://github.com/Daniel-LoCY/luna-cycle/releases/download/v1/app.apk',
      apkSize: apk.length,
      apkDigest: await _sha256(apk),
      versionCode: 3,
    );
    expect(
      GitHubUpdateRepository.parseManifest(
        manifestBytes: update,
        assets: _assets(apk.length),
        installedVersionCode: 3,
        androidApiLevel: 35,
      ),
      isNull,
    );
  });

  test(
    'rejects package mismatch, unsupported Android API and unsafe URLs',
    () async {
      final apk = Uint8List.fromList([1, 2, 3]);
      final base =
          jsonDecode(
                utf8.decode(
                  _manifest(
                    apkName: 'app.apk',
                    apkUri:
                        'https://github.com/Daniel-LoCY/luna-cycle/releases/download/v1/app.apk',
                    apkSize: apk.length,
                    apkDigest: await _sha256(apk),
                    versionCode: 3,
                  ),
                ),
              )
              as Map<String, dynamic>;

      expect(
        () => GitHubUpdateRepository.parseManifest(
          manifestBytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({...base, 'applicationId': 'other.package'}),
            ),
          ),
          assets: _assets(apk.length),
          installedVersionCode: 2,
          androidApiLevel: 35,
        ),
        throwsFormatException,
      );
      expect(
        () => GitHubUpdateRepository.parseManifest(
          manifestBytes: Uint8List.fromList(
            utf8.encode(jsonEncode({...base, 'minAndroidApi': 36})),
          ),
          assets: _assets(apk.length),
          installedVersionCode: 2,
          androidApiLevel: 35,
        ),
        throwsFormatException,
      );
      expect(
        () => GitHubUpdateRepository.parseManifest(
          manifestBytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                ...base,
                'apkUri': 'https://example.com/untrusted.apk',
              }),
            ),
          ),
          assets: [
            {
              'name': 'app.apk',
              'size': apk.length,
              'browser_download_url': 'https://example.com/untrusted.apk',
            },
          ],
          installedVersionCode: 2,
          androidApiLevel: 35,
        ),
        throwsFormatException,
      );
    },
  );

  test('refuses downloaded APKs whose size or SHA-256 differs', () async {
    final expected = Uint8List.fromList([1, 2, 3]);
    final update = AvailableUpdate(
      versionName: '1.1.0',
      versionCode: 3,
      minAndroidApi: 24,
      apkAssetName: 'app.apk',
      apkUri: Uri.https('github.com', '/Daniel-LoCY/luna-cycle/app.apk'),
      apkSha256: await _sha256(expected),
      apkSize: expected.length,
      releaseNotes: '',
    );
    final repository = GitHubUpdateRepository(
      fetcher: (uri, headers, maxBytes) async => UpdateHttpResponse(
        statusCode: 200,
        body: Uint8List.fromList([3, 2, 1]),
      ),
    );
    await expectLater(repository.downloadApk(update), throwsException);
    await repository.close();
  });

  test(
    'validates native package, build, Android API and signing certificate',
    () {
      final update = AvailableUpdate(
        versionName: '1.1.0',
        versionCode: 3,
        minAndroidApi: 24,
        apkAssetName: 'app.apk',
        apkUri: Uri.https('github.com', '/Daniel-LoCY/luna-cycle/app.apk'),
        apkSha256: 'a' * 64,
        apkSize: 1,
        releaseNotes: '',
      );
      final device = AndroidUpdateDeviceInfo(
        applicationId: lunaApplicationId,
        versionName: '1.0.0',
        versionCode: 2,
        androidApiLevel: 35,
        signingCertificateSha256: lunaReleaseCertificateSha256,
      );
      final apk = AndroidApkInfo(
        applicationId: lunaApplicationId,
        versionName: '1.1.0',
        versionCode: 3,
        minAndroidApi: 24,
        signingCertificateSha256: lunaReleaseCertificateSha256,
      );
      expect(
        () =>
            validateAndroidUpdateApk(device: device, apk: apk, update: update),
        returnsNormally,
      );
      expect(
        () => validateAndroidUpdateApk(
          device: device,
          apk: AndroidApkInfo(
            applicationId: lunaApplicationId,
            versionName: '1.1.0',
            versionCode: 3,
            minAndroidApi: 24,
            signingCertificateSha256: '0' * 64,
          ),
          update: update,
        ),
        throwsFormatException,
      );
    },
  );
}

List<dynamic> _assets(int size) => [
  {
    'name': 'app.apk',
    'state': 'uploaded',
    'browser_download_url':
        'https://github.com/Daniel-LoCY/luna-cycle/releases/download/v1/app.apk',
    'size': size,
  },
];

Uint8List _manifest({
  required String apkName,
  required String apkUri,
  required int apkSize,
  required String apkDigest,
  required int versionCode,
}) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'formatVersion': 1,
      'applicationId': lunaApplicationId,
      'versionName': '1.1.0',
      'versionCode': versionCode,
      'minAndroidApi': 24,
      'apkAssetName': apkName,
      'apkSha256': apkDigest,
      'releaseNotes': 'Notes',
    }),
  ),
);

Future<String> _sha256(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
