import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/cycle_prediction.dart';
import '../../core/data_management/export_archive_service.dart';
import '../../core/data_management/health_report_pdf_service.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';

class DataToolsSection extends ConsumerStatefulWidget {
  const DataToolsSection({super.key});

  @override
  ConsumerState<DataToolsSection> createState() => _DataToolsSectionState();
}

class _DataToolsSectionState extends ConsumerState<DataToolsSection> {
  bool _busy = false;
  DateTime? _lastBackupAt;
  int _backupReminderDays = 30;
  DateTime? _snoozedUntil;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackupSettings());
  }

  @override
  Widget build(BuildContext context) => LunaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_open_outlined),
          title: const Text('資料與備份'),
          subtitle: const Text('匯出 CSV／JSON／PDF，或建立密碼加密備份。'),
        ),
        _backupStatus(),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: ValueKey(_backupReminderDays),
          initialValue: _backupReminderDays,
          decoration: const InputDecoration(
            labelText: '備份提醒',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 7, child: Text('每 7 天')),
            DropdownMenuItem(value: 30, child: Text('每 30 天')),
            DropdownMenuItem(value: 90, child: Text('每 90 天')),
            DropdownMenuItem(value: 0, child: Text('關閉')),
          ],
          onChanged: _busy ? null : _setBackupReminder,
        ),
        const SizedBox(height: 8),
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(context, 'CSV'),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('匯出 CSV'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(context, 'JSON'),
              icon: const Icon(Icons.data_object_outlined),
              label: const Text('匯出 JSON'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(context, 'PDF'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('健康報告 PDF'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(context, '醫師摘要 PDF'),
              icon: const Icon(Icons.medical_information_outlined),
              label: const Text('醫師就診摘要'),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _createBackup(context),
              icon: const Icon(Icons.enhanced_encryption_outlined),
              label: const Text('加密備份'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _inspectBackup(context),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('檢查備份'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _restoreBackup(context),
              icon: const Icon(Icons.settings_backup_restore_outlined),
              label: const Text('從備份還原'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'CSV、JSON 和 PDF 是未加密檔案。加密備份只儲存在你選擇的位置；Luna Cycle 不會上傳備份。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Future<void> _export(BuildContext context, String format) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('匯出 $format 個人健康資料？'),
        content: Text(
          format.contains('PDF')
              ? format == '醫師摘要 PDF'
                    ? '就診摘要會包含選定日期內的月經日期、每日症狀、疼痛、情緒、經血量、藥物、備註與已標記的服用狀態。未標記項目不會被推定為漏服。PDF 未加密，請只分享給你選擇的醫療人員。'
                    : '報告會包含選定期間的月經日期、症狀、情緒及疼痛摘要，並分開標示週期預測。PDF 未加密，請確認分享目的地安全。'
              : '檔案可能包含月經日期、症狀、情緒、藥物與日記。匯出檔未加密，請確認分享目的地安全。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('選擇日期範圍'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 90)),
        end: DateTime.now(),
      ),
      helpText: '選擇要包含的實際紀錄日期',
      saveText: '套用日期',
    );
    if (range == null || !context.mounted) return;
    await _run(context, () async {
      final service = ref.read(exportArchiveServiceProvider);
      final start = _dateOnly(range.start);
      final end = _dateOnly(range.end);
      final suffix = '${_compactDate(start)}_${_compactDate(end)}';
      if (format == 'CSV') {
        final bytes = Uint8List.fromList(
          utf8.encode(await service.exportCsv(from: start, to: end)),
        );
        await _share(
          bytes,
          fileName: 'luna_cycle_records_$suffix.csv',
          mimeType: 'text/csv',
        );
        return;
      }
      final jsonText = await service.exportJson(from: start, to: end);
      if (format == 'JSON') {
        await _share(
          Uint8List.fromList(utf8.encode(jsonText)),
          fileName: 'luna_cycle_records_$suffix.json',
          mimeType: 'application/json',
        );
        return;
      }
      final export = Map<String, dynamic>.from(
        jsonDecode(jsonText) as Map<String, dynamic>,
      );
      final periods = await ref.read(cycleRepositoryProvider).getPeriods();
      final config = await ref.read(cycleConfigProvider.future);
      final prediction = predictCycles(
        periods: [
          for (final period in periods)
            PeriodRecord(start: period.startDate, end: period.endDate),
        ],
        mode: config.mode,
        configuredCycleLength: config.averageCycleLength,
        configuredPeriodLength: config.averagePeriodLength,
        fertilityEstimatesEnabled: config.fertilityEstimatesEnabled,
        predictionEnabled: config.predictionEnabled,
        forecastCount: 6,
      );
      final font = await rootBundle.load('assets/fonts/NotoSansTC-VF.ttf');
      final pdf = await HealthReportPdfService().generate(
        fontBytes: Uint8List.sublistView(font),
        export: export,
        from: start,
        to: end,
        prediction: prediction,
        clinicianSummary: format == '醫師摘要 PDF',
      );
      await _share(
        pdf,
        fileName: format == '醫師摘要 PDF'
            ? 'luna_cycle_visit_summary_$suffix.pdf'
            : 'luna_cycle_health_report_$suffix.pdf',
        mimeType: 'application/pdf',
      );
    });
  }

  Widget _backupStatus() {
    final now = DateTime.now();
    final lastBackup = _lastBackupAt?.toLocal();
    final isSnoozed = _snoozedUntil?.isAfter(now) ?? false;
    final isDue =
        _backupReminderDays > 0 &&
        !isSnoozed &&
        (lastBackup == null ||
            now.difference(lastBackup).inDays >= _backupReminderDays);
    final summary = lastBackup == null
        ? '尚未儲存加密備份'
        : '上次加密備份：${DateFormat('yyyy/MM/dd').format(lastBackup)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDue
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary, style: Theme.of(context).textTheme.bodyMedium),
          if (isDue) ...[
            const SizedBox(height: 4),
            const Text('建議將最新的加密備份儲存在安全位置。'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : _snoozeBackupReminder,
                child: const Text('7 天後提醒'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadBackupSettings() async {
    try {
      final database = ref.read(databaseProvider);
      final rows = await database.select(database.appSettings).get();
      final values = {for (final row in rows) row.key: row.value};
      if (!mounted) return;
      setState(() {
        _lastBackupAt = DateTime.tryParse(values['backup_last_saved_at'] ?? '');
        _backupReminderDays = switch (int.tryParse(
          values['backup_reminder_days'] ?? '30',
        )) {
          7 => 7,
          30 => 30,
          90 => 90,
          0 => 0,
          _ => 30,
        };
        _snoozedUntil = DateTime.tryParse(
          values['backup_reminder_snoozed_until'] ?? '',
        );
      });
    } catch (_) {
      // The backup controls remain available if settings cannot be read.
    }
  }

  Future<void> _setBackupReminder(int? days) async {
    if (days == null) return;
    try {
      await ref
          .read(cycleRepositoryProvider)
          .saveSetting('backup_reminder_days', '$days');
      if (mounted) setState(() => _backupReminderDays = days);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('備份提醒設定無法儲存：$error')));
      }
    }
  }

  Future<void> _snoozeBackupReminder() async {
    final until = DateTime.now().add(const Duration(days: 7)).toUtc();
    try {
      await ref
          .read(cycleRepositoryProvider)
          .saveSetting(
            'backup_reminder_snoozed_until',
            until.toIso8601String(),
          );
      if (mounted) setState(() => _snoozedUntil = until);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('提醒時間無法更新：$error')));
      }
    }
  }

  Future<void> _createBackup(BuildContext context) async {
    final password = await _passwordDialog(context, confirm: true);
    if (password == null || !context.mounted) return;
    await _run(context, () async {
      final bytes = await ref
          .read(exportArchiveServiceProvider)
          .createEncryptedBackup(password);
      final destination = await FilePicker.saveFile(
        fileName: 'luna_cycle_backup_${_compactDate(DateTime.now())}.luna',
        bytes: bytes,
        mimeType: 'application/vnd.lunacycle.backup+json',
        dialogTitle: '儲存加密備份',
      );
      if (destination == null) return;
      final savedAt = DateTime.now().toUtc();
      await ref
          .read(cycleRepositoryProvider)
          .saveSetting('backup_last_saved_at', savedAt.toIso8601String());
      if (!mounted || !context.mounted) return;
      setState(() => _lastBackupAt = savedAt);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加密備份已儲存至所選位置。')));
    }, successMessage: null);
  }

  Future<void> _inspectBackup(BuildContext context) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '選擇要檢查的 Luna Cycle 備份',
      type: FileType.custom,
      allowedExtensions: const ['luna'],
    );
    if (picked == null || !context.mounted) return;
    final password = await _passwordDialog(context, confirm: false);
    if (password == null || !context.mounted) return;
    BackupInspection? inspection;
    await _run(context, () async {
      inspection = await ref
          .read(exportArchiveServiceProvider)
          .inspectEncryptedBackup(await picked.readAsBytes(), password);
    }, successMessage: null);
    if (inspection == null || !context.mounted) return;
    final backup = inspection!;
    String dateLabel(DateTime? date) =>
        date == null ? '無紀錄' : DateFormat('yyyy/MM/dd').format(date.toLocal());
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('備份檢查完成'),
        content: Text(
          '密碼驗證與檔案完整性檢查通過。\n\n'
          '月經紀錄：${backup.periodCount} 筆\n'
          '每日紀錄：${backup.dailyLogCount} 筆\n'
          '藥物排程：${backup.medicationScheduleCount} 個\n'
          '服用記錄：${backup.medicationIntakeCount} 筆\n'
          '涵蓋日期：${dateLabel(backup.earliestDate)}–${dateLabel(backup.latestDate)}\n\n'
          '這次檢查沒有變更目前資料。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '選擇 Luna Cycle 加密備份',
      type: FileType.custom,
      allowedExtensions: const ['luna'],
    );
    if (picked == null || !context.mounted) return;
    final password = await _passwordDialog(context, confirm: false);
    if (password == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('以備份內容取代目前資料？'),
        content: const Text('還原會取代這台裝置目前的週期、健康紀錄和個人設定。若檔案格式或密碼不正確，現有資料會保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('還原並取代'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () async {
      final bytes = await picked.readAsBytes();
      await ref
          .read(exportArchiveServiceProvider)
          .restoreEncryptedBackup(bytes, password);
      ref.invalidate(periodsProvider);
      ref.invalidate(dailyLogsProvider);
      ref.invalidate(cycleConfigProvider);
      ref.invalidate(themeModeProvider);
      ref.invalidate(appLockEnabledProvider);
      ref.invalidate(onboardingCompleteProvider);
    }, successMessage: '加密備份已還原，原有資料已替換。');
  }

  Future<String?> _passwordDialog(
    BuildContext context, {
    required bool confirm,
  }) async {
    final formKey = GlobalKey<FormState>();
    final password = TextEditingController();
    final confirmation = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(confirm ? '設定備份密碼' : '輸入備份密碼'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: password,
                  autofocus: true,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '備份密碼',
                    helperText: '至少 12 個字元，遺失後無法還原。',
                  ),
                  validator: (value) {
                    final length = value?.runes.length ?? 0;
                    return length < 12 || length > 128
                        ? '請輸入 12 至 128 個字元'
                        : null;
                  },
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmation,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: '再次輸入密碼'),
                    validator: (value) =>
                        value != password.text ? '兩次輸入的密碼不一致' : null,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(context).pop(password.text);
                }
              },
              child: Text(confirm ? '建立加密備份' : '繼續還原'),
            ),
          ],
        ),
      );
    } finally {
      password.dispose();
      confirmation.dispose();
    }
  }

  Future<void> _share(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        fileNameOverrides: [fileName],
        subject: fileName,
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    String? successMessage = '檔案已交由系統分享。',
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (successMessage != null && mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('作業失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static String _compactDate(DateTime value) =>
      DateFormat('yyyyMMdd').format(value);
}
