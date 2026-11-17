import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';

class MedicationRemindersSection extends ConsumerStatefulWidget {
  const MedicationRemindersSection({super.key});

  @override
  ConsumerState<MedicationRemindersSection> createState() =>
      _MedicationRemindersSectionState();
}

class _MedicationRemindersSectionState
    extends ConsumerState<MedicationRemindersSection> {
  bool _saving = false;
  List<MedicationIntakeEntry> _recentIntakes = const [];

  @override
  void initState() {
    super.initState();
    _loadIntakes();
  }

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(medicationSchedulesProvider);
    final today = _day(DateTime.now());
    return LunaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.medication_outlined),
            title: const Text('藥物排程與服用記錄'),
            subtitle: const Text('每日提醒可設定多個時段；服用與略過由你記錄。'),
            trailing: IconButton(
              tooltip: '新增每日藥物提醒',
              onPressed: _saving ? null : () => _editSchedule(),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
          if (_saving) const LinearProgressIndicator(),
          schedules.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text('無法讀取藥物提醒：$error'),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('尚未設定每日藥物提醒。'),
                );
              }
              return Column(
                children: [
                  for (final schedule in items)
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 12),
                      title: Text(schedule.label),
                      subtitle: Text(_scheduleDescription(schedule)),
                      leading: Icon(
                        schedule.enabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: '藥物提醒操作',
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              _editSchedule(schedule);
                            case 'toggle':
                              _setEnabled(schedule, !schedule.enabled);
                            case 'delete':
                              _deleteSchedule(schedule);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'edit', child: Text('編輯')),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(schedule.enabled ? '暫停提醒' : '啟用提醒'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('刪除提醒'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 20),
          Text('今日服用記錄', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          schedules.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (items) {
              final active = items.where((item) => item.enabled).toList();
              if (active.isEmpty) {
                return Text(
                  '啟用每日提醒後，可以在這裡記錄已服用或略過。',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              }
              return Column(
                children: [
                  for (final schedule in active)
                    for (final time in _times(schedule))
                      _todayDose(schedule, time, today),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            _adherenceSummary(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '未標記的提醒不會被推定為漏服；通知內容不顯示藥名或劑量。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _todayDose(MedicationSchedule schedule, String time, DateTime today) {
    final entry = _recentIntakes
        .where(
          (value) =>
              value.scheduleId == schedule.id &&
              _sameDay(value.scheduledDay, today) &&
              value.scheduledTime == time,
        )
        .firstOrNull;
    return Semantics(
      label:
          '${schedule.label}，$time，${entry?.status == 'taken'
              ? '已服用'
              : entry?.status == 'skipped'
              ? '已略過'
              : '尚未記錄'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text('${schedule.label} · $time')),
            ChoiceChip(
              label: const Text('已服用'),
              selected: entry?.status == 'taken',
              onSelected: _saving
                  ? null
                  : (_) => _recordDose(schedule, time, today, 'taken'),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('略過'),
              selected: entry?.status == 'skipped',
              onSelected: _saving
                  ? null
                  : (_) => _recordDose(schedule, time, today, 'skipped'),
            ),
          ],
        ),
      ),
    );
  }

  String _adherenceSummary() {
    final since = _day(DateTime.now().subtract(const Duration(days: 29)));
    final recent = _recentIntakes
        .where((entry) => !entry.scheduledDay.isBefore(since))
        .toList();
    final taken = recent.where((entry) => entry.status == 'taken').length;
    final skipped = recent.where((entry) => entry.status == 'skipped').length;
    return '近 30 天已記錄：$taken 次已服用、$skipped 次略過。';
  }

  Future<void> _loadIntakes() async {
    try {
      final now = DateTime.now();
      final from = _day(now.subtract(const Duration(days: 29)));
      final to = _day(now);
      final entries = await ref
          .read(cycleRepositoryProvider)
          .getMedicationIntakes(from: from, to: to);
      if (mounted) setState(() => _recentIntakes = entries);
    } catch (_) {
      // The reminder list remains usable if history cannot be loaded.
    }
  }

  Future<void> _recordDose(
    MedicationSchedule schedule,
    String time,
    DateTime day,
    String status,
  ) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(cycleRepositoryProvider)
          .saveMedicationIntake(
            scheduleId: schedule.id,
            scheduleLabel: schedule.label,
            scheduledDay: day,
            scheduledTime: time,
            status: status,
          );
      await _loadIntakes();
      _showMessage(status == 'taken' ? '已記錄服用。' : '已記錄略過。');
    } catch (error) {
      _showMessage('服用記錄無法儲存：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editSchedule([MedicationSchedule? existing]) async {
    final form = await showDialog<_MedicationFormValue>(
      context: context,
      builder: (_) => _MedicationScheduleDialog(existing: existing),
    );
    if (form == null || !mounted) return;
    await _persist(() async {
      await ref
          .read(cycleRepositoryProvider)
          .saveMedicationSchedule(
            id: existing?.id,
            label: form.label,
            dosage: form.dosage,
            times: form.times,
            enabled: form.enabled,
          );
    });
  }

  Future<void> _setEnabled(MedicationSchedule schedule, bool enabled) =>
      _persist(() async {
        await ref
            .read(cycleRepositoryProvider)
            .saveMedicationSchedule(
              id: schedule.id,
              label: schedule.label,
              dosage: schedule.dosage,
              times: _times(schedule),
              enabled: enabled,
            );
      });

  Future<void> _deleteSchedule(MedicationSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這個藥物提醒？'),
        content: const Text('過去的已服用或略過記錄會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除提醒'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _persist(
      () => ref
          .read(cycleRepositoryProvider)
          .softDeleteMedicationSchedule(schedule.id),
    );
  }

  Future<void> _persist(Future<void> Function() operation) async {
    setState(() => _saving = true);
    try {
      await operation();
      await ref.read(localReminderServiceProvider).rescheduleSafely();
      await _loadIntakes();
      _showMessage('藥物提醒已更新。');
    } catch (error) {
      _showMessage('藥物提醒無法儲存：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static List<String> _times(MedicationSchedule? schedule) {
    if (schedule == null) return const [];
    try {
      final value = jsonDecode(schedule.timesJson);
      if (value is List) return value.whereType<String>().toList();
    } on FormatException {
      return const [];
    }
    return const [];
  }

  static String _scheduleDescription(MedicationSchedule schedule) {
    final times = _times(schedule).join('、');
    final dosage = schedule.dosage == null ? '' : ' · ${schedule.dosage}';
    return '${schedule.enabled ? '每日 $times' : '已暫停'}$dosage';
  }

  static DateTime _day(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _MedicationScheduleDialog extends StatefulWidget {
  const _MedicationScheduleDialog({this.existing});

  final MedicationSchedule? existing;

  @override
  State<_MedicationScheduleDialog> createState() =>
      _MedicationScheduleDialogState();
}

class _MedicationScheduleDialogState extends State<_MedicationScheduleDialog> {
  late final TextEditingController _label;
  late final TextEditingController _dosage;
  late final List<TimeOfDay> _times;
  final _formKey = GlobalKey<FormState>();
  late bool _active;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.existing?.label ?? '');
    _dosage = TextEditingController(text: widget.existing?.dosage ?? '');
    _times = _decodeTimes(widget.existing).map(_parseTime).toList();
    if (widget.existing == null)
      _times.add(const TimeOfDay(hour: 8, minute: 0));
    _active = widget.existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
    _dosage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '新增每日藥物提醒' : '編輯每日藥物提醒'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _label,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: '藥物或補充品名稱',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '請輸入名稱' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _dosage,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: '劑量（選填）',
                hintText: '例如：1 顆',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text('每日提醒時間', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final time in _times)
                  InputChip(
                    label: Text(time.format(context)),
                    onDeleted: _times.length <= 1
                        ? null
                        : () => setState(() => _times.remove(time)),
                  ),
                OutlinedButton.icon(
                  onPressed: _times.length >= 8 ? null : _addTime,
                  icon: const Icon(Icons.add_alarm_outlined),
                  label: const Text('新增時段'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '提醒會每天重複。通知只顯示通用文字；藥名與劑量只保存在此裝置。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('啟用提醒與今日服用記錄'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('儲存提醒')),
    ],
  );

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times.isEmpty
          ? const TimeOfDay(hour: 8, minute: 0)
          : _times.last,
      helpText: '選擇每日服用提醒時間',
    );
    if (picked == null || !mounted) return;
    if (_times.any((item) => _formatTime(item) == _formatTime(picked))) return;
    setState(() {
      _times.add(picked);
      _times.sort(_compareTimes);
    });
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false) || _times.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _MedicationFormValue(
        label: _label.text.trim(),
        dosage: _dosage.text.trim(),
        times: _times.map(_formatTime).toList(),
        enabled: _active,
      ),
    );
  }
}

class _MedicationFormValue {
  const _MedicationFormValue({
    required this.label,
    required this.dosage,
    required this.times,
    required this.enabled,
  });

  final String label;
  final String dosage;
  final List<String> times;
  final bool enabled;
}

List<String> _decodeTimes(MedicationSchedule? schedule) {
  if (schedule == null) return const [];
  try {
    final value = jsonDecode(schedule.timesJson);
    if (value is List) return value.whereType<String>().toList();
  } on FormatException {
    return const [];
  }
  return const [];
}

String _formatTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

TimeOfDay _parseTime(String time) {
  final parts = time.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

int _compareTimes(TimeOfDay left, TimeOfDay right) =>
    left.hour * 60 + left.minute - (right.hour * 60 + right.minute);
