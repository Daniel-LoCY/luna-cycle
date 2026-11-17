import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/design_system/widgets.dart';
import '../../core/providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cycleLength = TextEditingController();
  final _periodLength = TextEditingController();
  DateTime? _lastStart;
  DateTime? _lastEnd;
  String _mode = '一般週期追蹤';
  bool _predictionEnabled = true;
  bool _remindersEnabled = false;
  bool _saving = false;

  @override
  void dispose() {
    _cycleLength.dispose();
    _periodLength.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.nightlight_round,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '你好，這裡是 Luna Cycle',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '建立你的私人週期紀錄。沒有答案也可以略過，稍後再補充。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              LunaCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '最近一次月經',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                  helpText: '選擇最近一次月經開始日',
                                );
                                if (date != null)
                                  setState(() {
                                    _lastStart = date;
                                    if (_lastEnd != null &&
                                        _lastEnd!.isBefore(date)) {
                                      _lastEnd = null;
                                    }
                                  });
                              },
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          _lastStart == null
                              ? '選擇開始日期（可略過）'
                              : '${_lastStart!.year}年${_lastStart!.month}月${_lastStart!.day}日',
                        ),
                      ),
                      if (_lastStart != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _lastEnd ?? _lastStart!,
                                    firstDate: _lastStart!,
                                    lastDate: DateTime.now(),
                                    helpText: '選擇最近一次月經結束日',
                                  );
                                  if (date != null) {
                                    setState(() => _lastEnd = date);
                                  }
                                },
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(
                            _lastEnd == null
                                ? '選擇結束日期（可略過）'
                                : '結束：${_lastEnd!.year}年${_lastEnd!.month}月${_lastEnd!.day}日',
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _cycleLength,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '平均週期長度（天，可略過）',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => _validateDays(value, 15, 60),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _periodLength,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '平均經期天數（可略過）',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => _validateDays(value, 1, 15),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '使用目的',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _mode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '一般週期追蹤',
                            child: Text('一般週期追蹤'),
                          ),
                          DropdownMenuItem(
                            value: '不規律週期',
                            child: Text('不規律週期'),
                          ),
                          DropdownMenuItem(value: '備孕', child: Text('備孕')),
                          DropdownMenuItem(
                            value: '荷爾蒙避孕紀錄',
                            child: Text('荷爾蒙避孕紀錄'),
                          ),
                          DropdownMenuItem(value: '懷孕', child: Text('懷孕')),
                          DropdownMenuItem(value: '產後', child: Text('產後')),
                          DropdownMenuItem(value: '只記錄', child: Text('只記錄')),
                        ],
                        onChanged: (value) =>
                            setState(() => _mode = value ?? _mode),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('啟用週期預測'),
                        subtitle: const Text('可隨時在「我的」關閉；預測不作為避孕依據。'),
                        value: _predictionEnabled,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _predictionEnabled = value),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('啟用預估經期提醒'),
                        subtitle: const Text('預設在估算經期前兩天及當天提醒；可到「我的」調整。'),
                        value: _remindersEnabled,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _remindersEnabled = value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const LunaCard(
                child: Text('你的健康資料只儲存在這台裝置，離線也能使用。週期與排卵日期皆為粗略估算，不可作為避孕依據。'),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _finish,
                child: Text(_saving ? '正在準備…' : '開始使用'),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          _cycleLength.clear();
                          _periodLength.clear();
                          _lastStart = null;
                          _lastEnd = null;
                          _mode = '一般週期追蹤';
                          _predictionEnabled = true;
                          _remindersEnabled = false;
                        });
                        _finish();
                      },
                child: const Text('略過設定'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _finish() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      var reminderPermission = false;
      if (_remindersEnabled) {
        try {
          reminderPermission = await ref
              .read(localReminderServiceProvider)
              .requestPermission();
        } catch (_) {
          reminderPermission = false;
        }
      }
      final database = ref.read(databaseProvider);
      final repo = ref.read(cycleRepositoryProvider);
      if (_lastStart != null) {
        await repo.savePeriod(startDate: _lastStart!, endDate: _lastEnd);
      }
      await database.transaction(() async {
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'onboarding_complete',
                value: 'true',
              ),
            );
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'prediction_enabled',
                value: '$_predictionEnabled',
              ),
            );
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(key: 'tracking_mode', value: _mode),
            );
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'period_reminder_enabled',
                value: '$reminderPermission',
              ),
            );
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'period_reminder_days',
                value: '2',
              ),
            );
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'period_reminder_time',
                value: '09:00',
              ),
            );
        if (_cycleLength.text.trim().isNotEmpty) {
          await database
              .into(database.appSettings)
              .insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'average_cycle_length',
                  value: _cycleLength.text.trim(),
                ),
              );
        }
        if (_periodLength.text.trim().isNotEmpty) {
          await database
              .into(database.appSettings)
              .insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: 'average_period_length',
                  value: _periodLength.text.trim(),
                ),
              );
        }
      });
      ref.invalidate(onboardingCompleteProvider);
      ref.invalidate(cycleConfigProvider);
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('設定無法儲存：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateDays(String? value, int minimum, int maximum) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    final days = int.tryParse(input);
    if (days == null || days < minimum || days > maximum) {
      return '請輸入 $minimum 至 $maximum 天';
    }
    return null;
  }
}
