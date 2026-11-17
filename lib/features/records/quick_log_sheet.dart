import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers.dart';

Future<void> showQuickLogSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) async {
  DailyLog? existing;
  try {
    existing = await ref.read(cycleRepositoryProvider).getDailyLog(day);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('讀取紀錄失敗：$error')));
    }
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _QuickLogForm(day: day, existing: existing, ref: ref),
  );
}

class _QuickLogForm extends StatefulWidget {
  const _QuickLogForm({
    required this.day,
    required this.existing,
    required this.ref,
  });
  final DateTime day;
  final DailyLog? existing;
  final WidgetRef ref;

  @override
  State<_QuickLogForm> createState() => _QuickLogFormState();
}

class _QuickLogFormState extends State<_QuickLogForm> {
  late final Set<String> _symptoms;
  late final Set<String> _moods;
  late final Map<String, Object?> _body;
  late final Map<String, Object?> _reproductive;
  int? _pain;
  String? _flow;
  bool _spotting = false;
  bool _clots = false;
  String? _energy;
  String? _appetite;
  String? _exercise;
  String? _discharge;
  String? _ovulationTest;
  String? _pregnancyTest;
  String? _sexualActivity;
  String? _contraception;
  late final TextEditingController _note;
  late final TextEditingController _sleepHours;
  late final TextEditingController _weight;
  late final TextEditingController _temperature;
  late final TextEditingController _exerciseNote;
  late final TextEditingController _medications;
  late final TextEditingController _customSymptoms;
  late final TextEditingController _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _symptoms = _decodeSet(widget.existing?.symptomsJson);
    _moods = _decodeSet(widget.existing?.moodsJson);
    _body = _decodeMap(widget.existing?.bodyJson);
    _reproductive = _decodeMap(widget.existing?.reproductiveJson);
    _pain = widget.existing?.painLevel;
    _flow = widget.existing?.flow;
    _spotting = widget.existing?.spotting ?? false;
    _clots = widget.existing?.clots ?? false;
    _energy = _optionalChoice(_body['energy'], const ['1', '2', '3', '4', '5']);
    _appetite = _optionalChoice(_body['appetite'], const [
      '1',
      '2',
      '3',
      '4',
      '5',
    ]);
    _exercise = _optionalChoice(_body['exercise'], const [
      '無',
      '輕度',
      '中度',
      '高強度',
    ]);
    _discharge = _optionalChoice(_reproductive['discharge'], const [
      '乾燥',
      '黏稠',
      '乳液狀',
      '蛋清狀',
      '水狀',
      '其他',
    ]);
    _ovulationTest = _optionalChoice(_reproductive['ovulationTest'], const [
      '陰性',
      '陽性',
    ]);
    _pregnancyTest = _optionalChoice(_reproductive['pregnancyTest'], const [
      '陰性',
      '陽性',
    ]);
    _sexualActivity = _optionalChoice(_reproductive['sexualActivity'], const [
      '無',
      '有',
    ]);
    _contraception = _optionalChoice(_reproductive['contraception'], const [
      '無',
      '保險套',
      '口服避孕藥',
      '避孕器',
      '其他',
    ]);
    _note = TextEditingController(text: widget.existing?.note ?? '');
    _sleepHours = TextEditingController(
      text: _body['sleepHours']?.toString() ?? '',
    );
    _weight = TextEditingController(text: _body['weightKg']?.toString() ?? '');
    _temperature = TextEditingController(
      text: _body['temperatureC']?.toString() ?? '',
    );
    _exerciseNote = TextEditingController(
      text: _body['exerciseNote']?.toString() ?? '',
    );
    _medications = TextEditingController(
      text: _decodeSet(widget.existing?.medicationJson).join('、'),
    );
    _customSymptoms = TextEditingController(
      text: _symptoms
          .where((value) => !_symptomChoices.contains(value))
          .join('、'),
    );
    _tags = TextEditingController(
      text: _decodeSet(widget.existing?.tagsJson).join('、'),
    );
  }

  static const _symptomChoices = [
    '經痛',
    '腹痛',
    '腰痛',
    '頭痛',
    '腹脹',
    '痘痘',
    '疲倦',
    '噁心',
    '頭暈',
    '胸部脹痛',
    '便祕',
    '腹瀉',
    '水腫',
  ];
  static const _moodChoices = ['開心', '平靜', '焦慮', '煩躁', '難過', '敏感', '壓力'];

  @override
  void dispose() {
    _note.dispose();
    _sleepHours.dispose();
    _weight.dispose();
    _temperature.dispose();
    _exerciseNote.dispose();
    _medications.dispose();
    _customSymptoms.dispose();
    _tags.dispose();
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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '記錄 ${widget.day.year}年${widget.day.month}月${widget.day.day}日',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text('症狀'),
            Wrap(
              spacing: 6,
              children: [
                for (final item in _symptomChoices) _choice(item, _symptoms),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customSymptoms,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '自訂症狀，以頓號分隔',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text('情緒'),
            Wrap(
              spacing: 6,
              children: [
                for (final item in _moodChoices) _choice(item, _moods),
              ],
            ),
            const SizedBox(height: 12),
            const Text('疼痛程度'),
            Slider(
              value: (_pain ?? 0).toDouble(),
              min: 0,
              max: 10,
              divisions: 10,
              label: _pain?.toString() ?? '未記錄',
              onChanged: (value) => setState(() => _pain = value.round()),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('經血與出血'),
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _flow,
                  decoration: const InputDecoration(
                    labelText: '經血量',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<String?>(value: null, child: Text('未記錄')),
                    DropdownMenuItem(value: '無', child: Text('無')),
                    DropdownMenuItem(value: '少', child: Text('少')),
                    DropdownMenuItem(value: '中', child: Text('中')),
                    DropdownMenuItem(value: '多', child: Text('多')),
                  ],
                  onChanged: (value) => setState(() => _flow = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('點狀出血'),
                  value: _spotting,
                  onChanged: (value) => setState(() => _spotting = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('有血塊'),
                  value: _clots,
                  onChanged: (value) => setState(() => _clots = value),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('身體狀態'),
              children: [
                _numberField(_sleepHours, '睡眠時數', '0–24 小時'),
                const SizedBox(height: 10),
                _choiceField(
                  '精力',
                  _energy,
                  const ['1', '2', '3', '4', '5'],
                  (value) => setState(() => _energy = value),
                  labels: const ['很低', '偏低', '普通', '不錯', '很好'],
                ),
                const SizedBox(height: 10),
                _choiceField(
                  '食慾',
                  _appetite,
                  const ['1', '2', '3', '4', '5'],
                  (value) => setState(() => _appetite = value),
                  labels: const ['很低', '偏低', '普通', '偏高', '很高'],
                ),
                const SizedBox(height: 10),
                _choiceField('運動強度', _exercise, const [
                  '無',
                  '輕度',
                  '中度',
                  '高強度',
                ], (value) => setState(() => _exercise = value)),
                const SizedBox(height: 10),
                TextField(
                  controller: _exerciseNote,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '運動項目（選填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                _numberField(_weight, '體重', '公斤，0.2–700'),
                const SizedBox(height: 10),
                _numberField(_temperature, '基礎體溫', '°C，30–45'),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('生殖健康（選填）'),
              children: [
                _choiceField('分泌物', _discharge, const [
                  '乾燥',
                  '黏稠',
                  '乳液狀',
                  '蛋清狀',
                  '水狀',
                  '其他',
                ], (value) => setState(() => _discharge = value)),
                const SizedBox(height: 10),
                _choiceField('排卵試紙', _ovulationTest, const [
                  '陰性',
                  '陽性',
                ], (value) => setState(() => _ovulationTest = value)),
                const SizedBox(height: 10),
                _choiceField('驗孕結果', _pregnancyTest, const [
                  '陰性',
                  '陽性',
                ], (value) => setState(() => _pregnancyTest = value)),
                const SizedBox(height: 10),
                _choiceField('性行為', _sexualActivity, const [
                  '無',
                  '有',
                ], (value) => setState(() => _sexualActivity = value)),
                const SizedBox(height: 10),
                _choiceField('避孕方式', _contraception, const [
                  '無',
                  '保險套',
                  '口服避孕藥',
                  '避孕器',
                  '其他',
                ], (value) => setState(() => _contraception = value)),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('藥物與標籤'),
              children: [
                TextField(
                  controller: _medications,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: '藥物或補充品，以頓號分隔',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tags,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: '自訂標籤，以頓號分隔',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _note,
              maxLength: 10000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '備註（選填）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? '儲存中…'
                      : widget.existing == null
                      ? '儲存紀錄'
                      : '更新紀錄',
                ),
              ),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('刪除此筆紀錄'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _choice(String label, Set<String> selected) => FilterChip(
    label: Text(label),
    selected: selected.contains(label),
    onSelected: (value) =>
        setState(() => value ? selected.add(label) : selected.remove(label)),
  );

  Widget _numberField(
    TextEditingController controller,
    String label,
    String hint,
  ) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _choiceField(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged, {
    List<String>? labels,
  }) => DropdownButtonFormField<String?>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('未記錄')),
      for (var i = 0; i < values.length; i++)
        DropdownMenuItem<String?>(
          value: values[i],
          child: Text(labels == null ? values[i] : labels[i]),
        ),
    ],
    onChanged: onChanged,
  );

  Future<void> _save() async {
    final double? sleepHours;
    final double? weightKg;
    final double? temperatureC;
    try {
      sleepHours = _parseNumber(_sleepHours.text, '睡眠時數', 0, 24);
      weightKg = _parseNumber(_weight.text, '體重', .2, 700);
      temperatureC = _parseNumber(_temperature.text, '基礎體溫', 30, 45);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.ref
          .read(cycleRepositoryProvider)
          .saveDailyLog(
            day: widget.day,
            painLevel: _pain,
            flow: _flow,
            spotting: _spotting,
            clots: _clots,
            symptoms: {
              ..._symptoms,
              ..._parseList(_customSymptoms.text),
            }.toList(),
            moods: _moods.toList(),
            body: {
              if (sleepHours != null) 'sleepHours': sleepHours,
              if (_energy != null) 'energy': _energy,
              if (_appetite != null) 'appetite': _appetite,
              if (_exercise != null) 'exercise': _exercise,
              if (_exerciseNote.text.trim().isNotEmpty)
                'exerciseNote': _exerciseNote.text.trim(),
              if (weightKg != null) 'weightKg': weightKg,
              if (temperatureC != null) 'temperatureC': temperatureC,
            },
            reproductive: {
              if (_discharge != null) 'discharge': _discharge,
              if (_ovulationTest != null) 'ovulationTest': _ovulationTest,
              if (_pregnancyTest != null) 'pregnancyTest': _pregnancyTest,
              if (_sexualActivity != null) 'sexualActivity': _sexualActivity,
              if (_contraception != null) 'contraception': _contraception,
            },
            medications: _parseList(_medications.text),
            tags: _parseList(_tags.text),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      widget.ref.invalidate(dailyLogsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('儲存失敗：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除這筆紀錄？'),
        content: const Text('刪除後不會出現在日曆與健康記錄中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.ref
          .read(cycleRepositoryProvider)
          .softDeleteDailyLog(widget.existing!.id);
      widget.ref.invalidate(dailyLogsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刪除失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

Set<String> _decodeSet(String? encoded) {
  if (encoded == null) return {};
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is List) return decoded.whereType<String>().toSet();
  } on FormatException {
    return {};
  }
  return {};
}

Map<String, Object?> _decodeMap(String? encoded) {
  if (encoded == null) return {};
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    return {};
  }
  return {};
}

String? _optionalChoice(Object? value, List<String> choices) {
  if (value == null) return null;
  final text = value.toString();
  return choices.contains(text) ? text : null;
}

double? _parseNumber(
  String input,
  String label,
  double minimum,
  double maximum,
) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed < minimum || parsed > maximum) {
    throw FormatException('請輸入 $minimum 至 $maximum 的$label數值。');
  }
  return parsed;
}

List<String> _parseList(String input) => input
    .split('、')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();
