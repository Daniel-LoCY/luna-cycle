import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';
import '../../core/updates/github_update_repository.dart';
import '../../core/updates/update_manager.dart';

enum _UpdateAction { check, download, install }

class UpdateCenterSection extends ConsumerStatefulWidget {
  const UpdateCenterSection({super.key});

  @override
  ConsumerState<UpdateCenterSection> createState() =>
      _UpdateCenterSectionState();
}

class _UpdateCenterSectionState extends ConsumerState<UpdateCenterSection> {
  final GlobalKey _operationProgressKey = GlobalKey();

  bool _busy = false;
  _UpdateAction? _operation;
  bool _autoCheck = true;
  bool _disclosureSeen = false;
  bool _downloaded = false;
  AvailableUpdate? _update;
  String? _operationMessage;
  String? _operationNotice;
  bool _operationNoticeIsError = false;
  double? _progressValue;
  int? _receivedBytes;
  int? _totalBytes;
  int _lastProgressPercent = -1;

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
        if (defaultTargetPlatform != TargetPlatform.android)
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
          if (_update case final update?) ...[
            const SizedBox(height: 8),
            Text(
              '版本 ${update.versionName}（${update.versionCode}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildReleaseNotes(context, update.releaseNotes),
            ],
            const SizedBox(height: 12),
            _buildPrimaryAction(),
            if (_operationNotice case final notice?) ...[
              const SizedBox(height: 10),
              _buildOperationNotice(context, notice),
            ],
            const SizedBox(height: 6),
            Text(
              '安裝前會由 Android 顯示確認畫面。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!_busy || _operation == _UpdateAction.check) ...[
            const SizedBox(height: 8),
            _buildCheckButton(),
          ],
          if (_update == null && _operationNotice != null) ...[
            const SizedBox(height: 8),
            _buildOperationNotice(context, _operationNotice!),
          ],
        ],
      ],
    ),
  );

  Widget _buildPrimaryAction() {
    if (_operation == _UpdateAction.download ||
        _operation == _UpdateAction.install) {
      return _buildProgressCard();
    }
    if (_downloaded) {
      return FilledButton.icon(
        onPressed: _busy ? null : _install,
        icon: const Icon(Icons.install_mobile_outlined),
        label: const Text('交給 Android 安裝'),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : _download,
      icon: const Icon(Icons.download_outlined),
      label: const Text('下載並驗證 APK'),
    );
  }

  Widget _buildProgressCard() {
    final colors = Theme.of(context).colorScheme;
    final progressValue = _progressValue;
    final receivedBytes = _receivedBytes;
    final percent = progressValue == null
        ? null
        : '${(progressValue * 100).round()}%';
    final isInstalling = _operation == _UpdateAction.install;

    return Container(
      key: _operationProgressKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Semantics(
        liveRegion: true,
        label: _operationMessage ?? '正在處理更新',
        value: percent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isInstalling
                      ? Icons.system_update_alt_rounded
                      : Icons.downloading_rounded,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _operationMessage ?? '正在處理更新…',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
                if (percent != null)
                  Text(
                    percent,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progressValue),
            if (receivedBytes != null && _totalBytes != null) ...[
              const SizedBox(height: 6),
              Text(
                '已下載 ${_formatBytes(receivedBytes)}／${_formatBytes(_totalBytes!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseNotes(BuildContext context, String notes) {
    final lines = notes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('## '))
        .map((line) {
          if (line.startsWith('- ') || line.startsWith('* ')) {
            return line.substring(2).trim();
          }
          return line;
        })
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '•',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(line)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCheckButton() => OutlinedButton.icon(
    onPressed: _busy ? null : _checkNow,
    icon: _operation == _UpdateAction.check
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh_rounded),
    label: Text(_operation == _UpdateAction.check ? '正在檢查…' : '立即檢查更新'),
  );

  Widget _buildOperationNotice(BuildContext context, String notice) {
    final colors = Theme.of(context).colorScheme;
    final background = _operationNoticeIsError
        ? colors.errorContainer
        : colors.secondaryContainer;
    final foreground = _operationNoticeIsError
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _operationNoticeIsError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              size: 20,
              color: foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      final manager = ref.read(updateManagerProvider);
      final values = await ref.read(cycleRepositoryProvider).getSettings();
      final storedUpdate = await manager.storedUpdate();
      final installedVersionCode =
          storedUpdate != null &&
              defaultTargetPlatform == TargetPlatform.android
          ? await manager.getInstalledVersionCode()
          : null;
      final update =
          storedUpdate != null &&
              (installedVersionCode == null ||
                  storedUpdate.versionCode > installedVersionCode)
          ? storedUpdate
          : null;
      final path = values['update_downloaded_path'];
      final downloaded =
          path != null && path.isNotEmpty && await File(path).exists();
      if (!mounted) return;
      setState(() {
        _autoCheck = values['update_auto_check_enabled'] != 'false';
        _disclosureSeen = values['update_disclosure_seen'] == 'true';
        _update = update;
        _downloaded = update != null && downloaded;
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
      if (mounted) {
        setState(() {
          _operationNotice = '更新設定無法儲存：$error';
          _operationNoticeIsError = true;
        });
      }
    }
  }

  Future<void> _checkNow() async {
    await _run(_UpdateAction.check, '正在檢查 GitHub Release…', () async {
      final update = await ref.read(updateManagerProvider).checkNow();
      if (mounted) {
        setState(() {
          _operationNotice = update == null
              ? '目前已是最新版本。'
              : '找到版本 ${update.versionName}，可下載並驗證 APK。';
          _operationNoticeIsError = false;
        });
      }
    });
  }

  Future<void> _download() async {
    await _run(_UpdateAction.download, '準備下載 APK…', () async {
      await ref
          .read(updateManagerProvider)
          .downloadAndVerify(
            update: _update,
            onPhase: (phase) => _setPreparationPhase(phase),
            onProgress: _reportDownloadProgress,
          );
      if (mounted) {
        setState(() {
          _downloaded = true;
          _operationNotice = 'APK 已下載，SHA-256、版本及簽章驗證完成。';
          _operationNoticeIsError = false;
        });
      }
    });
  }

  Future<void> _install() async {
    await _run(_UpdateAction.install, '正在重新驗證下載檔…', () async {
      final result = await ref
          .read(updateManagerProvider)
          .installDownloaded(onPhase: _setInstallPhase);
      if (mounted) {
        setState(() {
          _operationNotice = result == UpdateInstallResult.permissionRequired
              ? '已開啟 Android 安裝來源設定；允許後返回，再點「交給 Android 安裝」。'
              : '已交給 Android 安裝器。請依系統畫面確認，安裝進度會由 Android 顯示。';
          _operationNoticeIsError = false;
        });
      }
    });
  }

  Future<void> _run(
    _UpdateAction operation,
    String initialMessage,
    Future<void> Function() action,
  ) async {
    setState(() {
      _busy = true;
      _operation = operation;
      _operationMessage = initialMessage;
      _operationNotice = null;
      _operationNoticeIsError = false;
      _progressValue = null;
      _receivedBytes = null;
      _totalBytes = null;
      _lastProgressPercent = -1;
    });
    if (operation != _UpdateAction.check) _scrollProgressIntoView();
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _operationNotice = '更新作業未完成：$error';
          _operationNoticeIsError = true;
        });
      }
    } finally {
      await _refresh();
      if (mounted) {
        setState(() {
          _busy = false;
          _operation = null;
          _operationMessage = null;
          _progressValue = null;
          _receivedBytes = null;
          _totalBytes = null;
        });
      }
    }
  }

  void _setPreparationPhase(UpdatePreparationPhase phase) {
    final message = switch (phase) {
      UpdatePreparationPhase.downloading => '正在下載 APK…',
      UpdatePreparationPhase.verifying => '下載完成，正在驗證 SHA-256…',
      UpdatePreparationPhase.checkingCompatibility => '正在檢查版本與簽章…',
    };
    if (!mounted) return;
    setState(() {
      _operationMessage = message;
      _progressValue = phase == UpdatePreparationPhase.downloading ? 0 : null;
      _receivedBytes = null;
      _totalBytes = phase == UpdatePreparationPhase.downloading
          ? _update?.apkSize
          : null;
      _lastProgressPercent = -1;
    });
  }

  void _reportDownloadProgress(int receivedBytes, int totalBytes) {
    final percent = (receivedBytes * 100 ~/ totalBytes).clamp(0, 100).toInt();
    if (percent == _lastProgressPercent && receivedBytes < totalBytes) return;
    _lastProgressPercent = percent;
    if (!mounted) return;
    setState(() {
      _operationMessage = '正在下載 APK…';
      _progressValue = (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
      _receivedBytes = receivedBytes;
      _totalBytes = totalBytes;
    });
  }

  void _setInstallPhase(UpdateInstallPhase phase) {
    final message = switch (phase) {
      UpdateInstallPhase.verifying => '正在重新驗證 APK…',
      UpdateInstallPhase.checkingCompatibility => '正在檢查版本與簽章…',
      UpdateInstallPhase.requestingPermission => '正在確認 Android 安裝權限…',
      UpdateInstallPhase.handingOff => '正在交給 Android 安裝器…',
    };
    if (!mounted) return;
    setState(() {
      _operationMessage = message;
      _progressValue = null;
      _receivedBytes = null;
      _totalBytes = null;
    });
  }

  static String _formatBytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  void _scrollProgressIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final progressContext = _operationProgressKey.currentContext;
      if (!mounted || progressContext == null) return;
      Scrollable.ensureVisible(
        progressContext,
        alignment: 0.25,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }
}
