import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/providers.dart';

Future<void> showPeriodEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  Period? period,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PeriodEditor(period: period, ref: ref),
  );
}

class _PeriodEditor extends StatefulWidget {
  const _PeriodEditor({required this.period, required this.ref});

  final Period? period;
  final WidgetRef ref;

  @override
  State<_PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<_PeriodEditor> {
  late DateTime _start = _day(widget.period?.startDate ?? DateTime.now());
  late DateTime? _end = widget.period?.endDate == null
      ? null
      : _day(widget.period!.endDate!);
  late String? _flow = widget.period?.flow;
  late bool _spotting = widget.period?.spotting ?? false;
  late bool _clots = widget.period?.clots ?? false;
  late final TextEditingController _note = TextEditingController(
    text: widget.period?.note ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
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
              widget.period == null ? '新增月經紀錄' : '編輯月經紀錄',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _dateButton(
              label: '開始日期',
              date: _start,
              onPressed: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('經期仍在進行'),
              value: _end == null,
              onChanged: (active) =>
                  setState(() => _end = active ? null : _start),
            ),
            if (_end != null)
              _dateButton(
                label: '結束日期',
                date: _end!,
                onPressed: () => _pickDate(isStart: false),
              ),
            const SizedBox(height: 14),
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
                child: Text(_saving ? '儲存中…' : '儲存月經紀錄'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dateButton({
    required String label,
    required DateTime date,
    required VoidCallback onPressed,
  }) => OutlinedButton.icon(
    onPressed: _saving ? null : onPressed,
    icon: const Icon(Icons.calendar_month_outlined),
    label: Text('$label：${DateFormat('yyyy年M月d日').format(date)}'),
  );

  Future<void> _pickDate({required bool isStart}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end ?? _start,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: isStart ? '選擇月經開始日期' : '選擇月經結束日期',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = _day(selected);
        if (_end != null && _end!.isBefore(_start)) _end = _start;
      } else {
        _end = _day(selected);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repository = widget.ref.read(cycleRepositoryProvider);
      if (widget.period == null) {
        await repository.savePeriod(
          startDate: _start,
          endDate: _end,
          flow: _flow,
          spotting: _spotting,
          clots: _clots,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
      } else {
        await repository.updatePeriod(
          id: widget.period!.id,
          startDate: _start,
          endDate: _end,
          flow: _flow,
          spotting: _spotting,
          clots: _clots,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('儲存失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
