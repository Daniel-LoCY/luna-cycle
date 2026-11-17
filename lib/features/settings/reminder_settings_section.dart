import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design_system/widgets.dart';
import '../../core/notifications/local_reminder_service.dart';
import '../../core/providers.dart';

class ReminderSettingsSection extends ConsumerStatefulWidget {
  const ReminderSettingsSection({super.key});

  @override
  ConsumerState<ReminderSettingsSection> createState() =>
      _ReminderSettingsSectionState();
}

class _ReminderSettingsSectionState
    extends ConsumerState<ReminderSettingsSection> {
  bool _loading = true;
  bool _saving = false;
  bool _periodEnabled = false;
  bool _dailyEnabled = false;
  bool _scheduleNeedsAttention = false;
  int _daysBefore = 2;
  TimeOfDay _periodTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _dailyTime = const TimeOfDay(hour: 20, minute: 30);
  TimeOfDay _dndStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _dndEnd = const TimeOfDay(hour: 7, minute: 0);
  List<CustomLocalReminder> _custom = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => LunaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('本機提醒'),
          subtitle: const Text('只在這台裝置排程，通知文字不會顯示健康資料。'),
        ),
        if (_loading)
          const LinearProgressIndicator()
        else ...[
          if (_scheduleNeedsAttention) ...[
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.warning_amber_rounded),
              title: Text('提醒排程未完成'),
              subtitle: Text('請確認系統通知權限與提醒設定後再試。'),
            ),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('預估經期提醒'),
            subtitle: const Text('預估日期前幾天及當天各提醒一次。'),
            value: _periodEnabled,
            onChanged: _saving ? null : _setPeriodEnabled,
          ),
          if (_periodEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<int>(
                      initialValue: _daysBefore,
                      decoration: const InputDecoration(
                        labelText: '提前天數',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var day = 1; day <= 7; day++)
                          DropdownMenuItem(value: day, child: Text('$day 天前')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                _persist(() async {
                                  _daysBefore = value;
                                  await _save('period_reminder_days', '$value');
                                });
                              }
                            },
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickTime(isPeriod: true),
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text('提醒時間 ${_periodTime.format(context)}'),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('每日記錄提醒'),
            subtitle: const Text('每天以不透露內容的通知提醒記錄身體狀態。'),
            value: _dailyEnabled,
            onChanged: _saving ? null : _setDailyEnabled,
          ),
          if (_dailyEnabled)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _pickTime(isPeriod: false),
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text('提醒時間 ${_dailyTime.format(context)}'),
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('勿擾時段', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '時段內的提醒會延後至結束時間；開始與結束設為相同時間可關閉勿擾。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _pickDndTime(isStart: true),
                      child: Text('開始 ${_dndStart.format(context)}'),
                    ),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _pickDndTime(isStart: false),
                      child: Text('結束 ${_dndEnd.format(context)}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('藥物與自訂提醒'),
            subtitle: const Text('單次提醒；通知只顯示通用文字。'),
            trailing: IconButton(
              tooltip: '新增提醒',
              onPressed: _saving ? null : _addCustomReminder,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
          if (_custom.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '尚未設定單次提醒。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final reminder in _custom)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 16),
                title: Text(reminder.label),
                subtitle: Text(
                  DateFormat('yyyy/MM/dd  HH:mm').format(reminder.at),
                ),
                onTap: _saving ? null : () => _editCustomReminder(reminder),
                trailing: IconButton(
                  tooltip: '刪除提醒',
                  onPressed: _saving
                      ? null
                      : () => _removeCustomReminder(reminder.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          if (_saving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ],
    ),
  );

  Future<void> _load() async {
    try {
      final database = ref.read(databaseProvider);
      final rows = await database.select(database.appSettings).get();
      final values = {for (final row in rows) row.key: row.value};
      if (!mounted) return;
      setState(() {
        _periodEnabled = values['period_reminder_enabled'] == 'true';
        _dailyEnabled = values['daily_reminder_enabled'] == 'true';
        _daysBefore = int.tryParse(values['period_reminder_days'] ?? '') ?? 2;
        _periodTime = _parseTime(values['period_reminder_time'], _periodTime);
        _dailyTime = _parseTime(values['daily_reminder_time'], _dailyTime);
        _dndStart = _parseTime(values['dnd_start'], _dndStart);
        _dndEnd = _parseTime(values['dnd_end'], _dndEnd);
        _custom = _parseCustom(values['custom_reminders_json']);
        _scheduleNeedsAttention =
            values['reminder_schedule_status'] == 'needs_attention';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('無法讀取提醒設定：$error');
    }
  }

  Future<void> _setPeriodEnabled(bool enabled) async {
    if (enabled && !await _requestPermission()) return;
    await _persist(() async {
      _periodEnabled = enabled;
      await _save('period_reminder_enabled', '$enabled');
    });
  }

  Future<void> _setDailyEnabled(bool enabled) async {
    if (enabled && !await _requestPermission()) return;
    await _persist(() async {
      _dailyEnabled = enabled;
      await _save('daily_reminder_enabled', '$enabled');
    });
  }

  Future<bool> _requestPermission() async {
    try {
      final granted = await ref
          .read(localReminderServiceProvider)
          .requestPermission();
      if (!granted) _showMessage('通知權限未開啟；可到系統設定調整後再試。');
      return granted;
    } catch (error) {
      _showMessage('無法啟用通知：$error');
      return false;
    }
  }

  Future<void> _pickTime({required bool isPeriod}) async {
    final value = await showTimePicker(
      context: context,
      initialTime: isPeriod ? _periodTime : _dailyTime,
      helpText: isPeriod ? '預估經期提醒時間' : '每日記錄提醒時間',
    );
    if (value == null) return;
    await _persist(() async {
      if (isPeriod) {
        _periodTime = value;
        await _save('period_reminder_time', _formatTime(value));
      } else {
        _dailyTime = value;
        await _save('daily_reminder_time', _formatTime(value));
      }
    });
  }

  Future<void> _pickDndTime({required bool isStart}) async {
    final current = isStart ? _dndStart : _dndEnd;
    final value = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: isStart ? '勿擾時段開始' : '勿擾時段結束',
    );
    if (value == null) return;
    await _persist(() async {
      if (isStart) {
        _dndStart = value;
        await _save('dnd_start', _formatTime(value));
      } else {
        _dndEnd = value;
        await _save('dnd_end', _formatTime(value));
      }
    });
  }

  Future<void> _addCustomReminder() async {
    await _editCustomReminder();
  }

  Future<void> _editCustomReminder([CustomLocalReminder? existing]) async {
    if (existing == null && !await _requestPermission()) return;
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(text: existing?.label ?? '');
    var date = existing?.at ?? DateTime.now();
    var time = existing == null
        ? TimeOfDay.fromDateTime(
            DateTime.now().add(const Duration(minutes: 30)),
          )
        : TimeOfDay.fromDateTime(existing.at);
    final result = await showDialog<(String, DateTime, TimeOfDay)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '新增單次提醒' : '編輯單次提醒'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '提醒名稱',
                    hintText: '例如：服用補充品',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '請輸入提醒名稱' : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date.isBefore(DateTime.now())
                          ? DateTime.now()
                          : date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(DateFormat('yyyy/MM/dd').format(date)),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked != null) setDialogState(() => time = picked);
                  },
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(time.format(context)),
                ),
                Text(
                  '系統通知只會顯示通用文字，不會顯示提醒名稱。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(
                    dialogContext,
                  ).pop((controller.text.trim(), date, time));
                }
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    final at = DateTime(
      result.$2.year,
      result.$2.month,
      result.$2.day,
      result.$3.hour,
      result.$3.minute,
    );
    if (!at.isAfter(DateTime.now())) {
      _showMessage('提醒時間必須晚於現在。');
      return;
    }
    final updated = CustomLocalReminder(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch,
      label: result.$1,
      at: at,
    );
    if (existing == null) {
      await _persist(() async {
        _custom = [..._custom, updated]..sort((a, b) => a.at.compareTo(b.at));
        await _saveCustom();
      });
    } else {
      await _persist(() async {
        _custom = [
          for (final item in _custom) item.id == existing.id ? updated : item,
        ]..sort((a, b) => a.at.compareTo(b.at));
        await _saveCustom();
      });
    }
  }

  Future<void> _removeCustomReminder(int id) async {
    await _persist(() async {
      _custom = _custom.where((item) => item.id != id).toList();
      await _saveCustom();
    });
  }

  Future<void> _saveCustom() => _save(
    'custom_reminders_json',
    jsonEncode([for (final item in _custom) item.toJson()]),
  );

  Future<void> _persist(Future<void> Function() change) async {
    setState(() => _saving = true);
    try {
      await change();
      await ref.read(localReminderServiceProvider).reschedule();
      await _save('reminder_schedule_status', 'ready');
      if (mounted) setState(() {});
    } catch (error) {
      await _save('reminder_schedule_status', 'needs_attention');
      _showMessage('提醒設定無法儲存：$error');
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(String key, String value) =>
      ref.read(cycleRepositoryProvider).saveSetting(key, value);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTime(String? value, TimeOfDay fallback) {
    final match = value == null
        ? null
        : RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    if (match == null) return fallback;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return fallback;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static List<CustomLocalReminder> _parseCustom(String? value) {
    if (value == null) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .map(CustomLocalReminder.fromJson)
          .whereType<CustomLocalReminder>()
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));
    } on FormatException {
      return const [];
    }
  }
}
