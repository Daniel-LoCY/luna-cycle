import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../cycle_prediction.dart';

class HealthReportPdfService {
  Future<Uint8List> generate({
    required Uint8List fontBytes,
    required Map<String, dynamic> export,
    required DateTime from,
    required DateTime to,
    required CyclePrediction prediction,
    bool clinicianSummary = false,
  }) async {
    final data = export['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('匯出資料格式不正確。');
    }
    final periods = _rows(data['periods'])
      ..sort((a, b) => _date(a['startDate']).compareTo(_date(b['startDate'])));
    final logs = _rows(data['dailyLogs'])
      ..sort((a, b) => _date(a['day']).compareTo(_date(b['day'])));
    final medicationIntakes = _rows(data['medicationIntakes']);
    final dateFormat = DateFormat('yyyy/MM/dd');
    final starts = periods.map((row) => _date(row['startDate'])).toList();
    final cycleLengths = [
      for (var index = 1; index < starts.length; index++)
        starts[index].difference(starts[index - 1]).inDays,
    ];
    final cycleMedian = _median(cycleLengths);
    final symptomCounts = <String, int>{};
    final moodCounts = <String, int>{};
    var painTotal = 0;
    var painCount = 0;
    for (final log in logs) {
      for (final symptom in _jsonList(log['symptomsJson'])) {
        symptomCounts[symptom] = (symptomCounts[symptom] ?? 0) + 1;
      }
      for (final mood in _jsonList(log['moodsJson'])) {
        moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
      }
      final pain = log['painLevel'];
      if (pain is int) {
        painTotal += pain;
        painCount++;
      }
    }
    final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
    final document = pw.Document(
      title: 'Luna Cycle 健康紀錄報告',
      subject: '個人週期及健康紀錄摘要',
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    const ink = PdfColor.fromInt(0xff282632);
    const muted = PdfColor.fromInt(0xff6d6976);
    const lavender = PdfColor.fromInt(0xffaa91d6);
    const pink = PdfColor.fromInt(0xfff2b7c6);
    const mint = PdfColor.fromInt(0xffa7d5c4);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'LUNA CYCLE  ・  個人健康紀錄',
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            '第 ${context.pageNumber} 頁  /  本報告僅整理使用者自行輸入的紀錄與估算',
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xfffaf8f6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
              border: pw.Border.all(color: const PdfColor.fromInt(0xffeee8f4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  clinicianSummary ? '就診摘要' : '健康紀錄摘要',
                  style: pw.TextStyle(
                    color: ink,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '實際資料範圍：${dateFormat.format(from)} 至 ${dateFormat.format(to)}',
                  style: pw.TextStyle(color: muted, fontSize: 10),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  '產生日期：${dateFormat.format(DateTime.now())}',
                  style: pw.TextStyle(color: muted, fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          _sectionTitle('實際紀錄摘要', ink),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              _stat('月經紀錄', '${periods.length} 次', pink, ink),
              pw.SizedBox(width: 8),
              _stat('每日健康紀錄', '${logs.length} 天', mint, ink),
              pw.SizedBox(width: 8),
              _stat(
                '週期中位數',
                cycleMedian == null ? '資料不足' : '$cycleMedian 天',
                lavender,
                ink,
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _sectionTitle('月經紀錄（實際）', ink),
          pw.SizedBox(height: 6),
          if (periods.isEmpty)
            _emptyMessage('此日期範圍沒有月經紀錄。', muted)
          else
            _table(
              ['開始日期', '結束日期', '經期天數', '經血量'],
              [
                for (final period in periods)
                  [
                    dateFormat.format(_date(period['startDate'])),
                    period['endDate'] == null || period['endDate'] == ''
                        ? '進行中'
                        : dateFormat.format(_date(period['endDate'])),
                    _periodDays(period),
                    _flowLabel(period['flow']),
                  ],
              ],
              ink,
              muted,
            ),
          if (clinicianSummary) ...[
            pw.SizedBox(height: 16),
            _sectionTitle('逐日紀錄（使用者輸入）', ink),
            pw.SizedBox(height: 6),
            if (logs.isEmpty)
              _emptyMessage('選定日期內沒有每日健康紀錄。', muted)
            else
              _table(
                ['日期', '症狀', '疼痛', '情緒', '經血量', '藥物／備註'],
                [
                  for (final log in logs.take(200))
                    [
                      dateFormat.format(_date(log['day'])),
                      _shortList(_jsonList(log['symptomsJson'])),
                      log['painLevel'] is int
                          ? '${log['painLevel']}/10'
                          : '未記錄',
                      _shortList(_jsonList(log['moodsJson'])),
                      _flowLabel(log['flow']),
                      _shortText(
                        [
                          ..._jsonList(log['medicationJson']),
                          if (log['note'] is String &&
                              (log['note'] as String).isNotEmpty)
                            log['note'] as String,
                        ].join(' · '),
                        100,
                      ),
                    ],
                ],
                ink,
                muted,
              ),
            if (medicationIntakes.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _sectionTitle('藥物服用標記（已記錄項目）', ink),
              pw.SizedBox(height: 5),
              _table(
                ['日期', '藥物／補充品', '預定時間', '使用者標記'],
                [
                  for (final intake in medicationIntakes)
                    [
                      dateFormat.format(_date(intake['scheduledDay'])),
                      _shortText('${intake['scheduleLabel'] ?? ''}', 80),
                      '${intake['scheduledTime'] ?? ''}',
                      intake['status'] == 'taken' ? '已服用' : '已略過',
                    ],
                ],
                ink,
                muted,
              ),
              pw.SizedBox(height: 3),
              _emptyMessage('未標記的提醒不會被推定為漏服。', muted),
            ],
          ],
          pw.SizedBox(height: 16),
          _sectionTitle('常見症狀與情緒（實際）', ink),
          pw.SizedBox(height: 6),
          _summaryLine('症狀', symptomCounts, muted),
          pw.SizedBox(height: 5),
          _summaryLine('情緒', moodCounts, muted),
          pw.SizedBox(height: 5),
          pw.Text(
            painCount == 0
                ? '疼痛：沒有疼痛程度紀錄'
                : '疼痛：平均 ${_oneDecimal(painTotal / painCount)} / 10（$painCount 筆）',
            style: pw.TextStyle(color: muted, fontSize: 9),
          ),
          pw.SizedBox(height: 16),
          _sectionTitle('預測資料（估算）', ink),
          pw.SizedBox(height: 6),
          if (prediction.nextStarts.isEmpty)
            _emptyMessage(_predictionMessage(prediction.support), muted)
          else ...[
            _emptyMessage('以下日期由已記錄的週期估算，與實際紀錄分開呈現；可能與實際情況不同，不可作為避孕依據。', muted),
            pw.SizedBox(height: 7),
            _table(
              ['預估經期開始區間', '預估經期結束區間'],
              [
                for (final start in prediction.nextStarts)
                  [
                    _rangeLabel(start, dateFormat),
                    _rangeLabel(
                      DateRange(
                        start.earliest.add(
                          Duration(
                            days: (prediction.estimatedPeriodLength ?? 5) - 1,
                          ),
                        ),
                        start.latest.add(
                          Duration(
                            days: (prediction.estimatedPeriodLength ?? 5) - 1,
                          ),
                        ),
                      ),
                      dateFormat,
                    ),
                  ],
              ],
              ink,
              muted,
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Text(
            'Luna Cycle 僅供個人紀錄與週期估算，不提供疾病診斷、治療建議或避孕保證。',
            style: pw.TextStyle(color: muted, fontSize: 8),
          ),
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _sectionTitle(String title, PdfColor color) => pw.Text(
    title,
    style: pw.TextStyle(
      fontSize: 12,
      color: color,
      fontWeight: pw.FontWeight.bold,
    ),
  );

  static pw.Widget _stat(
    String title,
    String value,
    PdfColor color,
    PdfColor ink,
  ) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(color: ink, fontSize: 8)),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: ink,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );

  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows,
    PdfColor ink,
    PdfColor muted,
  ) => pw.Table(
    border: pw.TableBorder.all(
      color: const PdfColor.fromInt(0xffeee8f4),
      width: .5,
    ),
    columnWidths: {
      for (var i = 0; i < headers.length; i++) i: const pw.FlexColumnWidth(),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xfffaf8f6)),
        children: [
          for (final header in headers) _cell(header, ink, bold: true),
        ],
      ),
      for (final row in rows)
        pw.TableRow(children: [for (final value in row) _cell(value, muted)]),
    ],
  );

  static pw.Widget _cell(String value, PdfColor color, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: pw.Text(
          value,
          style: pw.TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  static pw.Widget _emptyMessage(String text, PdfColor color) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: const pw.BoxDecoration(
      color: PdfColor.fromInt(0xfffaf8f6),
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Text(text, style: pw.TextStyle(color: color, fontSize: 8)),
  );

  static pw.Widget _summaryLine(
    String title,
    Map<String, int> values,
    PdfColor muted,
  ) {
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final summary = sorted
        .take(8)
        .map((item) => '${item.key} ${item.value} 次')
        .join('、');
    return pw.Text(
      '$title：${summary.isEmpty ? '沒有紀錄' : summary}',
      style: pw.TextStyle(color: muted, fontSize: 9),
    );
  }

  static List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];

  static List<String> _jsonList(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } on FormatException {
      return const [];
    }
  }

  static DateTime _date(Object? value) =>
      value is String ? DateTime.parse(value).toLocal() : DateTime(1970);

  static int? _median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  static String _periodDays(Map<String, dynamic> period) {
    if (period['endDate'] == null || period['endDate'] == '') return '進行中';
    final start = _date(period['startDate']);
    final end = _date(period['endDate']);
    return '${end.difference(start).inDays + 1} 天';
  }

  static String _flowLabel(Object? value) => switch (value) {
    'none' || '無' => '無',
    'light' || '少' => '少',
    'medium' || '中' => '中',
    'heavy' || '多' => '多',
    _ => '未記錄',
  };

  static String _rangeLabel(DateRange range, DateFormat format) =>
      range.earliest == range.latest
      ? format.format(range.earliest)
      : '${format.format(range.earliest)}–${format.format(range.latest)}';

  static String _predictionMessage(PredictionSupport support) =>
      switch (support) {
        PredictionSupport.disabled => '使用者已關閉週期預測。',
        PredictionSupport.notApplicable => '目前追蹤模式不適用一般週期預測。',
        PredictionSupport.insufficient => '目前資料不足，沒有可呈現的預測。',
        _ => '目前沒有可呈現的預測日期。',
      };

  static String _shortList(List<String> values) =>
      values.isEmpty ? '未記錄' : _shortText(values.join('、'), 80);

  static String _shortText(String value, int maxLength) =>
      value.length <= maxLength ? value : '${value.substring(0, maxLength)}…';

  static String _oneDecimal(double value) =>
      (value * 10).roundToDouble().toStringAsFixed(1);
}
