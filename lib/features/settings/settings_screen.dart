import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import 'package:flutter/services.dart';

import '../../core/cycle_prediction.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';
import 'data_tools_section.dart';
import 'reminder_settings_section.dart';
import 'update_center_section.dart';
import 'medication_reminders_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(cycleConfigProvider);
    final theme = ref.watch(themeModeProvider).value ?? 'system';
    final cycle = config.value;
    return LunaPage(
      title: '我的',
      children: [
        LunaCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('週期設定'),
                subtitle: Text(
                  cycle == null
                      ? '讀取中…'
                      : '${_modeLabel(cycle.mode)}・週期 ${cycle.averageCycleLength ?? '依紀錄'} 天・經期 ${cycle.averagePeriodLength ?? '依紀錄'} 天',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: cycle == null
                    ? null
                    : () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (context) =>
                            _CycleSettingsSheet(ref: ref, config: cycle),
                      ),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text('啟用週期預測'),
                subtitle: const Text('只根據已記錄的月經日期估算，可隨時關閉。'),
                value: cycle?.predictionEnabled ?? true,
                onChanged: cycle == null
                    ? null
                    : (value) => _saveSetting(
                        context,
                        ref,
                        'prediction_enabled',
                        '$value',
                        invalidate: () => ref.invalidate(cycleConfigProvider),
                      ),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.spa_outlined),
                title: const Text('顯示粗略排卵與易受孕期估算'),
                subtitle: const Text('只在模式適用且週期紀錄穩定時顯示；不可作為避孕依據。'),
                value: cycle?.fertilityEstimatesEnabled ?? false,
                onChanged: cycle == null
                    ? null
                    : (value) => _saveSetting(
                        context,
                        ref,
                        'fertility_estimates_enabled',
                        '$value',
                        invalidate: () => ref.invalidate(cycleConfigProvider),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const DataToolsSection(),
        const SizedBox(height: 12),
        LunaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.palette_outlined),
                title: Text('外觀'),
              ),
              DropdownButtonFormField<String>(
                initialValue: theme,
                decoration: const InputDecoration(
                  labelText: '主題',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('跟隨系統')),
                  DropdownMenuItem(value: 'light', child: Text('淺色')),
                  DropdownMenuItem(value: 'dark', child: Text('深色')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _saveSetting(
                    context,
                    ref,
                    'theme_mode',
                    value,
                    invalidate: () => ref.invalidate(themeModeProvider),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LunaCard(
          child: ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('清除全部資料'),
            subtitle: const Text('刪除這台裝置內的月經、健康紀錄與設定。請先完成需要的備份。'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _clearAllData(context, ref),
          ),
        ),
        const SizedBox(height: 12),
        LunaCard(
          child: Column(
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('隱私保護'),
                subtitle: Text('資料庫使用本機加密；解鎖時使用指紋、臉部辨識或裝置螢幕鎖。'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('開啟 App 鎖定'),
                subtitle: const Text('離開 App 後再次開啟時，需先完成裝置驗證。'),
                value: ref.watch(appLockEnabledProvider).value ?? false,
                onChanged: ref.watch(appLockEnabledProvider).hasValue
                    ? (enabled) => _setAppLock(context, ref, enabled)
                    : null,
              ),
              if (Platform.isAndroid)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('隱藏 App 切換畫面預覽'),
                  subtitle: const Text(
                    '切換到其他 App 時遮蔽 Luna Cycle 畫面；前景使用時仍可截圖。',
                  ),
                  value: ref.watch(appSwitcherPrivacyProvider).value ?? false,
                  onChanged: ref.watch(appSwitcherPrivacyProvider).hasValue
                      ? (enabled) => _setSwitcherPrivacy(context, ref, enabled)
                      : null,
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.visibility_off_outlined),
                  title: Text('App 切換畫面隱私保護'),
                  subtitle: Text('此版本的背景預覽遮蔽目前支援 Android。'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const ReminderSettingsSection(),
        const SizedBox(height: 12),
        const MedicationRemindersSection(),
        const SizedBox(height: 12),
        const UpdateCenterSection(),
        const SizedBox(height: 12),
        const LunaCard(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('關於 Luna Cycle'),
            subtitle: Text('版本 1.1.0 · 離線個人健康紀錄'),
          ),
        ),
      ],
    );
  }
}

Future<void> _setSwitcherPrivacy(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  try {
    await ref
        .read(cycleRepositoryProvider)
        .saveSetting('privacy_hide_app_switcher', '$enabled');
    await const MethodChannel(
      'app.lunacycle/update_installer',
    ).invokeMethod<void>('setSwitcherPrivacyEnabled', {'enabled': enabled});
    ref.invalidate(appSwitcherPrivacyProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('隱私設定無法更新：$error')));
    }
  }
}

Future<void> _saveSetting(
  BuildContext context,
  WidgetRef ref,
  String key,
  String value, {
  required void Function() invalidate,
}) async {
  try {
    await ref.read(cycleRepositoryProvider).saveSetting(key, value);
    invalidate();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('設定無法儲存：$error')));
    }
  }
}

Future<void> _setAppLock(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  try {
    if (enabled && !await LocalAuthentication().isDeviceSupported()) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('此裝置尚未設定可用的螢幕鎖定。')));
      }
      return;
    }
    await ref
        .read(cycleRepositoryProvider)
        .saveSetting('app_lock_enabled', '$enabled');
    ref.invalidate(appLockEnabledProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('隱私設定無法儲存：$error')));
    }
  }
}

Future<void> _clearAllData(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除這台裝置上的全部資料？'),
      content: const Text('月經紀錄、每日健康紀錄、預測快照和個人設定都會刪除，無法復原。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('保留資料'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('清除資料'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(cycleRepositoryProvider).clearAllUserData();
    ref.invalidate(periodsProvider);
    ref.invalidate(dailyLogsProvider);
    ref.invalidate(cycleConfigProvider);
    ref.invalidate(themeModeProvider);
    ref.invalidate(appLockEnabledProvider);
    ref.invalidate(onboardingCompleteProvider);
    if (context.mounted) context.go('/welcome');
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除資料失敗：$error')));
    }
  }
}

String _modeLabel(CycleMode mode) => switch (mode) {
  CycleMode.general => '一般追蹤',
  CycleMode.irregular => '不規律週期',
  CycleMode.tryingToConceive => '備孕',
  CycleMode.hormonalContraception => '荷爾蒙避孕紀錄',
  CycleMode.pregnancy => '懷孕',
  CycleMode.postpartum => '產後',
  CycleMode.trackingOnly => '只記錄',
};

class _CycleSettingsSheet extends StatefulWidget {
  const _CycleSettingsSheet({required this.ref, required this.config});

  final WidgetRef ref;
  final CycleConfig config;

  @override
  State<_CycleSettingsSheet> createState() => _CycleSettingsSheetState();
}

class _CycleSettingsSheetState extends State<_CycleSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _cycleLength = TextEditingController(
    text: widget.config.averageCycleLength?.toString() ?? '',
  );
  late final _periodLength = TextEditingController(
    text: widget.config.averagePeriodLength?.toString() ?? '',
  );
  late String _mode = _modeSettingValue(widget.config.mode);
  bool _saving = false;

  @override
  void dispose() {
    _cycleLength.dispose();
    _periodLength.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('週期設定', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cycleLength,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '平均週期長度（15–60 天，可略過）',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validate(value, 15, 60),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _periodLength,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '平均經期天數（1–15 天，可略過）',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validate(value, 1, 15),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(
                  labelText: '使用目的',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '一般週期追蹤', child: Text('一般週期追蹤')),
                  DropdownMenuItem(value: '不規律週期', child: Text('不規律週期')),
                  DropdownMenuItem(value: '備孕', child: Text('備孕')),
                  DropdownMenuItem(value: '荷爾蒙避孕紀錄', child: Text('荷爾蒙避孕紀錄')),
                  DropdownMenuItem(value: '懷孕', child: Text('懷孕')),
                  DropdownMenuItem(value: '產後', child: Text('產後')),
                  DropdownMenuItem(value: '只記錄', child: Text('只記錄')),
                ],
                onChanged: (value) => setState(() => _mode = value ?? _mode),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '儲存中…' : '儲存設定'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String? _validate(String? value, int minimum, int maximum) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    final days = int.tryParse(input);
    if (days == null || days < minimum || days > maximum) {
      return '請輸入 $minimum 至 $maximum 天';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repository = widget.ref.read(cycleRepositoryProvider);
      await repository.saveSetting('tracking_mode', _mode);
      await repository.saveSetting(
        'average_cycle_length',
        _cycleLength.text.trim(),
      );
      await repository.saveSetting(
        'average_period_length',
        _periodLength.text.trim(),
      );
      widget.ref.invalidate(cycleConfigProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('設定無法儲存：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _modeSettingValue(CycleMode mode) => switch (mode) {
  CycleMode.general => '一般週期追蹤',
  CycleMode.irregular => '不規律週期',
  CycleMode.tryingToConceive => '備孕',
  CycleMode.hormonalContraception => '荷爾蒙避孕紀錄',
  CycleMode.pregnancy => '懷孕',
  CycleMode.postpartum => '產後',
  CycleMode.trackingOnly => '只記錄',
};
