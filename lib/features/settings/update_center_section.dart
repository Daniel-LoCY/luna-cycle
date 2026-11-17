import 'dart:io';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';
import '../../core/updates/github_update_repository.dart';
import '../../core/updates/update_manager.dart';

class UpdateCenterSection extends ConsumerStatefulWidget {
  const UpdateCenterSection({super.key});

  @override
  ConsumerState<UpdateCenterSection> createState() =>
      _UpdateCenterSectionState();
}

class _UpdateCenterSectionState extends ConsumerState<UpdateCenterSection> {
  bool _busy = false;
  bool _autoCheck = true;
  bool _disclosureSeen = false;
  bool _downloaded = false;
  DateTime? _lastCheckedAt;
  AvailableUpdate? _update;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) => LunaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.system_update_alt_rounded),
          title: Text('App 更新'),
          subtitle: Text('從 GitHub Release 取得已簽章的 Android APK。'),
        ),
        if (!Platform.isAndroid)
          const Text('App 內 APK 更新目前只支援 Android。')
        else ...[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('每日自動檢查'),
            subtitle: const Text('僅在 App 開啟時透過 HTTPS 查詢版本，不會傳送健康資料。'),
            value: _autoCheck,
            onChanged: _busy ? null : _setAutoCheck,
          ),
          if (!_disclosureSeen)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('首次使用時會先說明自動檢查內容與隱私範圍。'),
            ),
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],
          Text(_statusLabel(), style: Theme.of(context).textTheme.bodyMedium),
          if (_lastCheckedAt != null) ...[
            const SizedBox(height: 3),
            Text(
              '上次檢查：${DateFormat('yyyy/MM/dd HH:mm').format(_lastCheckedAt!.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_update case final update?) ...[
            const SizedBox(height: 8),
            Text(
              '版本 ${update.versionName}（${update.versionCode}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(update.releaseNotes),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_downloaded)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _download,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('下載並驗證 APK'),
                  ),
                if (_downloaded)
                  FilledButton.icon(
                    onPressed: _busy ? null : _install,
                    icon: const Icon(Icons.install_mobile_outlined),
                    label: const Text('交給 Android 安裝'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '下載完成後仍須由你點選安裝，Android 會顯示系統安裝確認。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _checkNow,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('立即檢查更新'),
          ),
        ],
      ],
    ),
  );

  String _statusLabel() {
    if (_status == 'current') return '目前已是最新版本。';
    if (_status == 'available') return '有新版本可供安裝。';
    if (_status == 'error') return '上次檢查未完成。';
    return '尚未檢查更新。';
  }

  Future<void> _refresh() async {
    try {
      final manager = ref.read(updateManagerProvider);
      final values = await ref.read(cycleRepositoryProvider).getSettings();
      final update = await manager.storedUpdate();
      final path = values['update_downloaded_path'];
      final downloaded =
          path != null && path.isNotEmpty && await File(path).exists();
      if (!mounted) return;
      setState(() {
        _autoCheck = values['update_auto_check_enabled'] != 'false';
        _disclosureSeen = values['update_disclosure_seen'] == 'true';
        _status = values['update_last_check_status'];
        _error = values['update_last_check_error']?.isEmpty == true
            ? null
            : values['update_last_check_error'];
        _lastCheckedAt = DateTime.tryParse(
          values['update_last_check_at'] ?? '',
        );
        _update = update;
        _downloaded = downloaded;
      });
    } catch (_) {
      // The settings page remains usable if update status cannot be read.
    }
  }

  Future<void> _setAutoCheck(bool enabled) async {
    try {
      await ref.read(updateManagerProvider).setAutomaticChecksEnabled(enabled);
      if (mounted) setState(() => _autoCheck = enabled);
    } catch (error) {
      _showMessage('更新設定無法儲存：$error');
    }
  }

  Future<void> _checkNow() async {
    await _run(() async {
      final update = await ref.read(updateManagerProvider).checkNow();
      _showMessage(
        update == null ? '目前已是最新版本。' : '找到版本 ${update.versionName}。',
      );
    });
  }

  Future<void> _download() async {
    await _run(() async {
      await ref.read(updateManagerProvider).downloadAndVerify(update: _update);
      _showMessage('APK 已驗證，請確認後再交由 Android 安裝。');
      if (mounted) setState(() => _downloaded = true);
    });
  }

  Future<void> _install() async {
    await _run(() async {
      final result = await ref.read(updateManagerProvider).installDownloaded();
      _showMessage(
        result == UpdateInstallResult.permissionRequired
            ? '已開啟 Android 安裝來源設定；完成設定後返回，再點選安裝。'
            : '已交給 Android 安裝程式，請確認版本資訊並完成安裝。',
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _showMessage('更新作業失敗：$error');
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
