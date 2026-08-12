import 'package:encba_locker/features/locker/services/homecoming_file_picker.dart'
    as platform_picker;
import 'package:excel/excel.dart';

class IbOperationImportResult {
  const IbOperationImportResult({
    required this.fileName,
    required this.academicYear,
    required this.term,
    required this.rows,
    required this.dateCount,
  });

  final String fileName;
  final int academicYear;
  final int term;
  final List<Map<String, dynamic>> rows;
  final int dateCount;
}

class IbOperationImportService {
  Future<IbOperationImportResult?> pickAndParse() async {
    final file = await platform_picker.pickHomecomingFile();
    if (file == null) return null;
    return parseBytes(fileName: file.name, bytes: file.bytes);
  }

  IbOperationImportResult parseBytes({
    required String fileName,
    required List<int> bytes,
  }) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('IB 운영표 시트가 비어 있습니다.');
    }
    final sheetEntry = workbook.tables.entries.first;
    final sheet = sheetEntry.value;
    if (sheet.rows.isEmpty) {
      throw const FormatException('IB 운영표 행을 찾지 못했습니다.');
    }

    final period = _periodFromFileName(fileName);
    final dateColumns = <int, DateTime>{};
    for (var column = 1; column < sheet.rows.first.length; column++) {
      final parsed = _parseDate(_valueAt(sheet.rows.first, column), period.$1);
      if (parsed != null) dateColumns[column] = parsed;
    }
    if (dateColumns.isEmpty) {
      throw const FormatException('첫 행에서 운영 날짜를 찾지 못했습니다.');
    }

    final pending =
        <({String name, String title, int row, int column, DateTime date})>[];
    final timeOverrides = <String, ({int hour, int minute})>{};
    String? currentTitle;

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final first = _valueAt(row, 0);
      if (first.contains('운영제외')) break;
      if (_isAssignmentTitle(first)) currentTitle = first;
      final title = currentTitle;
      if (title == null) continue;

      for (final entry in dateColumns.entries) {
        final raw = _valueAt(row, entry.key);
        if (raw.isEmpty || raw.toLowerCase() == 'x') continue;
        final explicitTime = _parseTime(raw);
        if (explicitTime != null) {
          timeOverrides['$title:${entry.key}'] = explicitTime;
          continue;
        }
        if (_isIgnoredCell(raw)) continue;
        for (final name
            in raw
                .split(RegExp(r'[,/\n]'))
                .map((value) => value.trim())
                .where(_looksLikeName)) {
          pending.add((
            name: name,
            title: title,
            row: rowIndex + 1,
            column: entry.key + 1,
            date: entry.value,
          ));
        }
      }
    }
    if (pending.isEmpty) {
      throw const FormatException('담당자 배정 내용을 찾지 못했습니다.');
    }

    final seen = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final item in pending) {
      final unique = '${item.row}:${item.column}:${item.name}';
      if (!seen.add(unique)) continue;
      final time =
          timeOverrides['${item.title}:${item.column - 1}'] ??
          _defaultTime(item.title);
      final start = DateTime(
        item.date.year,
        item.date.month,
        item.date.day,
        time.hour,
        time.minute,
      );
      rows.add({
        'assignee_name': item.name,
        'title': item.title,
        'starts_at': start.toUtc().toIso8601String(),
        'ends_at': start
            .add(const Duration(hours: 2))
            .toUtc()
            .toIso8601String(),
        'location': '71동 종합체육관',
        'memo': 'IB 리그 운영 · ${item.date.month}월 ${item.date.day}일',
        'source_sheet': sheetEntry.key,
        'source_row': item.row,
        'source_column': item.column,
      });
    }
    rows.sort((a, b) {
      final byTime = (a['starts_at'] as String).compareTo(
        b['starts_at'] as String,
      );
      return byTime != 0
          ? byTime
          : (a['title'] as String).compareTo(b['title'] as String);
    });
    return IbOperationImportResult(
      fileName: fileName,
      academicYear: period.$1,
      term: period.$2,
      rows: rows,
      dateCount: dateColumns.length,
    );
  }

  (int, int) _periodFromFileName(String fileName) {
    final match = RegExp(r'(\d{2,4})\s*[-_]\s*([12])').firstMatch(fileName);
    if (match != null) {
      final rawYear = int.parse(match.group(1)!);
      return (
        rawYear < 100 ? 2000 + rawYear : rawYear,
        int.parse(match.group(2)!),
      );
    }
    final now = DateTime.now();
    return (now.year, now.month >= 9 ? 2 : 1);
  }

  DateTime? _parseDate(String value, int year) {
    final match = RegExp(
      r'(\d{1,2})\s*(?:/|월)\s*(\d{1,2})\s*(?:일)?',
    ).firstMatch(value);
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final date = DateTime(year, month, day);
    return date.month == month && date.day == day ? date : null;
  }

  ({int hour, int minute})? _parseTime(String value) {
    final match = RegExp(
      r'(?<!\d)([01]?\d|2[0-3]):([0-5]\d)',
    ).firstMatch(value);
    return match == null
        ? null
        : (
            hour: int.parse(match.group(1)!),
            minute: int.parse(match.group(2)!),
          );
  }

  ({int hour, int minute}) _defaultTime(String title) => switch (title[0]) {
    '1' => (hour: 11, minute: 0),
    '2' => (hour: 13, minute: 0),
    _ => (hour: 15, minute: 0),
  };

  bool _isAssignmentTitle(String value) =>
      RegExp(r'^[123]경기\s+(운영\s+[AB]|심판)$').hasMatch(value);

  bool _isIgnoredCell(String value) {
    final normalized = value.replaceAll(' ', '').toLowerCase();
    return normalized.isEmpty ||
        normalized == 'x' ||
        normalized.contains('경기시작') ||
        normalized.contains('경기사작') ||
        normalized.contains('인원제외') ||
        normalized.startsWith('count') ||
        normalized.startsWith('sum(');
  }

  bool _looksLikeName(String value) =>
      RegExp(r'^[가-힣A-Za-z][가-힣A-Za-z .-]{1,29}$').hasMatch(value);

  String _valueAt(List<Data?> row, int column) {
    if (column >= row.length) return '';
    return row[column]?.value?.toString().trim() ?? '';
  }
}
