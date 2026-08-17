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
    required this.explicitTimeCount,
    required this.defaultTimeCount,
    this.warnings = const [],
  });

  final String fileName;
  final int academicYear;
  final int term;
  final List<Map<String, dynamic>> rows;
  final int dateCount;
  final int explicitTimeCount;
  final int defaultTimeCount;
  final List<String> warnings;
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
    final period = _periodFromFileName(fileName);
    final layouts = workbook.tables.entries
        .map((entry) => _findLayout(entry, period.$1))
        .whereType<_IbSheetLayout>()
        .toList();
    if (layouts.isEmpty) {
      throw const FormatException('운영 날짜와 1·2·3경기 배정표를 함께 찾지 못했습니다.');
    }
    layouts.sort((a, b) => b.score.compareTo(a.score));
    final layout = layouts.first;
    final sheet = layout.sheet;
    final dateColumns = layout.dateColumns;
    final warnings = <String>[
      ..._weekdayWarnings(layout),
      if (layouts.length > 1)
        '운영표 형식의 시트가 여러 개라 배정이 가장 많은 ${layout.sheetName} 시트를 선택했습니다.',
    ];

    final pending =
        <({String name, String title, int row, int column, DateTime date})>[];
    final timeOverrides = <String, ({int hour, int minute})>{};
    final unrecognizedCells = <String>[];
    String? currentTitle;

    for (
      var rowIndex = layout.headerRow + 1;
      rowIndex < sheet.rows.length;
      rowIndex++
    ) {
      final row = sheet.rows[rowIndex];
      final first = _valueAt(row, 0);
      // 배정표 아래에는 운영 횟수를 세는 통계 표가 붙는다. 그 표는 A열이
      // 아니라 가운데 열들에서 시작하기도 해서, 행 전체를 보고 끊어야
      // 통계 표의 이름과 머리글이 배정으로 딸려 들어오지 않는다.
      if (_isSummaryRow(row)) break;
      if (_isAssignmentTitle(first)) currentTitle = _normalizeTitle(first);
      final title = currentTitle;
      if (title == null) continue;

      for (final entry in dateColumns.entries) {
        final raw = _valueAt(row, entry.key);
        if (raw.isEmpty || raw.toLowerCase() == 'x') continue;
        final explicitTime = _parseTime(raw);
        if (explicitTime != null) {
          timeOverrides['$title:${entry.key}'] = explicitTime;
        }
        final names = _namesFromCell(raw);
        if (names.isEmpty &&
            explicitTime == null &&
            !_isIgnoredCell(raw) &&
            unrecognizedCells.length < 5) {
          unrecognizedCells.add(
            '${layout.sheetName}!${rowIndex + 1}:${entry.key + 1} `$raw`',
          );
        }
        for (final name in names) {
          pending.add((
            name: name,
            title: title,
            row: rowIndex + 1,
            column: entry.key + 1,
            date: entry.value,
          ));
        }
      }

      // 실제 양식은 마지막 날짜의 시작 시간을 바로 오른쪽 보조 칸에 적기도 한다.
      for (var column = 0; column < row.length; column++) {
        if (dateColumns.containsKey(column)) continue;
        final explicitTime = _parseTime(_valueAt(row, column));
        if (explicitTime == null) continue;
        final previousDateColumns =
            dateColumns.keys.where((dateColumn) => dateColumn < column).toList()
              ..sort();
        if (previousDateColumns.isEmpty) continue;
        final nearestDateColumn = previousDateColumns.last;
        if (column - nearestDateColumn <= 2) {
          timeOverrides['$title:$nearestDateColumn'] = explicitTime;
        }
      }
    }
    if (pending.isEmpty) {
      throw const FormatException('담당자 배정 내용을 찾지 못했습니다.');
    }
    if (unrecognizedCells.isNotEmpty) {
      warnings.add(
        '이름으로 해석하지 못한 셀 ${unrecognizedCells.length}개가 있습니다: '
        '${unrecognizedCells.join(', ')}',
      );
    }

    final seen = <String>{};
    final duplicateKeys = <String>{};
    final rows = <Map<String, dynamic>>[];
    var explicitTimeCount = 0;
    var defaultTimeCount = 0;
    for (final item in pending) {
      final semanticKey =
          '${item.title}:${item.date.year}-${item.date.month}-${item.date.day}:${item.name}';
      if (!seen.add(semanticKey)) {
        duplicateKeys.add(semanticKey);
        continue;
      }
      final override = timeOverrides['${item.title}:${item.column - 1}'];
      final time = override ?? _defaultTime(item.title);
      if (override == null) {
        defaultTimeCount++;
      } else {
        explicitTimeCount++;
      }
      final start = _koreaTimeAsUtc(
        item.date,
        hour: time.hour,
        minute: time.minute,
      );
      rows.add({
        'assignee_name': item.name,
        'title': item.title,
        'starts_at': start.toIso8601String(),
        'ends_at': start.add(const Duration(hours: 2)).toIso8601String(),
        'location': '71동 종합체육관',
        'memo': 'IB 리그 운영 · ${item.date.month}월 ${item.date.day}일',
        'source_sheet': layout.sheetName,
        'source_row': item.row,
        'source_column': item.column,
      });
    }
    if (duplicateKeys.isNotEmpty) {
      warnings.add('같은 날짜·역할·이름의 중복 배정 ${duplicateKeys.length}건은 한 번만 가져옵니다.');
    }
    if (rows.length > 2000) {
      throw const FormatException('한 번에 가져올 수 있는 운영 배정은 2,000건까지입니다.');
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
      explicitTimeCount: explicitTimeCount,
      defaultTimeCount: defaultTimeCount,
      warnings: warnings,
    );
  }

  _IbSheetLayout? _findLayout(MapEntry<String, Sheet> entry, int year) {
    _IbSheetLayout? best;
    final sheet = entry.value;
    for (
      var headerRow = 0;
      headerRow < sheet.rows.length && headerRow < 12;
      headerRow++
    ) {
      final dateColumns = <int, DateTime>{};
      final headerValues = <int, String>{};
      final row = sheet.rows[headerRow];
      for (var column = 1; column < row.length; column++) {
        final raw = _valueAt(row, column);
        final parsed = _parseDate(raw, year);
        if (parsed != null) {
          dateColumns[column] = parsed;
          headerValues[column] = raw;
        }
      }
      if (dateColumns.isEmpty) continue;
      final assignmentTitleCount = sheet.rows
          .skip(headerRow + 1)
          .take(30)
          .where((candidate) => _isAssignmentTitle(_valueAt(candidate, 0)))
          .length;
      if (assignmentTitleCount == 0) continue;
      final candidate = _IbSheetLayout(
        sheetName: entry.key,
        sheet: sheet,
        headerRow: headerRow,
        dateColumns: dateColumns,
        headerValues: headerValues,
        score: dateColumns.length * 10 + assignmentTitleCount,
      );
      if (best == null || candidate.score > best.score) best = candidate;
    }
    return best;
  }

  List<String> _weekdayWarnings(_IbSheetLayout layout) {
    const labels = <int, String>{
      DateTime.monday: '월',
      DateTime.tuesday: '화',
      DateTime.wednesday: '수',
      DateTime.thursday: '목',
      DateTime.friday: '금',
      DateTime.saturday: '토',
      DateTime.sunday: '일',
    };
    final warnings = <String>[];
    for (final entry in layout.dateColumns.entries) {
      final raw = layout.headerValues[entry.key] ?? '';
      final match = RegExp(r'\(([월화수목금토일])\)').firstMatch(raw);
      if (match != null && match.group(1) != labels[entry.value.weekday]) {
        warnings.add(
          '${entry.value.month}월 ${entry.value.day}일은 실제 ${labels[entry.value.weekday]}요일인데 원본에는 ${match.group(1)}요일로 적혀 있습니다.',
        );
      }
    }
    return warnings;
  }

  (int, int) _periodFromFileName(String fileName) {
    final match = RegExp(r'(\d{2,4})\s*[-_]\s*([12])').firstMatch(fileName);
    if (match == null) {
      throw const FormatException(
        '파일명에서 학기를 확인할 수 없습니다. `26-1 IB리그 운영표.xlsx`처럼 연도-학기를 포함해 주세요.',
      );
    }
    final rawYear = int.parse(match.group(1)!);
    final year = rawYear < 100 ? 2000 + rawYear : rawYear;
    if (year < 2020 || year > 2100) {
      throw const FormatException('운영표 연도는 2020–2100 범위여야 합니다.');
    }
    return (year, int.parse(match.group(2)!));
  }

  DateTime? _parseDate(String value, int year) {
    final match = RegExp(
      r'(\d{1,2})\s*(?:/|월)\s*(\d{1,2})\s*(?:일)?',
    ).firstMatch(value);
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final date = DateTime.utc(year, month, day);
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

  List<String> _namesFromCell(String value) {
    final withoutTimes = value
        .replaceAll(RegExp(r'(?<!\d)([01]?\d|2[0-3]):[0-5]\d'), '')
        .replaceAll('경기시작', '')
        .replaceAll('경기사작', '')
        .trim();
    if (_isIgnoredCell(withoutTimes)) return const [];
    return withoutTimes
        .split(RegExp(r'[,/\n·&]'))
        .map((name) => name.trim())
        .where(_looksLikeName)
        .toList();
  }

  DateTime _koreaTimeAsUtc(
    DateTime date, {
    required int hour,
    required int minute,
  }) => DateTime.utc(date.year, date.month, date.day, hour - 9, minute);

  ({int hour, int minute}) _defaultTime(String title) => switch (title[0]) {
    '1' => (hour: 11, minute: 0),
    '2' => (hour: 13, minute: 0),
    _ => (hour: 15, minute: 0),
  };

  String _normalizeTitle(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool _isAssignmentTitle(String value) =>
      RegExp(r'^[123]경기\s+(운영\s+[AB]|심판)\s*$').hasMatch(value.trim());

  /// 배정표가 끝나고 집계 표가 시작되는 행인지 본다.
  static const _summaryMarkers = [
    '운영제외',
    '인원제외',
    '총인원수',
    '인당운영',
    '총운영수',
    '칸담당',
  ];

  bool _isSummaryRow(List<Data?> row) {
    for (var column = 0; column < row.length; column++) {
      final normalized = _valueAt(row, column).replaceAll(' ', '');
      if (normalized.isEmpty) continue;
      if (_summaryMarkers.any(normalized.contains)) return true;
    }
    return false;
  }

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

  /// 한글 이름은 붙여 쓰는 2–5자다. 공백까지 허용하면 "총 인원수" 같은
  /// 집계 표 머리글이 사람 이름으로 딸려 들어온다.
  bool _looksLikeName(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^[가-힣]{2,5}$').hasMatch(trimmed)) return true;
    return RegExp(r'^[A-Za-z][A-Za-z.-]*( [A-Za-z.-]+)*$').hasMatch(trimmed) &&
        trimmed.length >= 2 &&
        trimmed.length <= 30;
  }

  String _valueAt(List<Data?> row, int column) {
    if (column >= row.length) return '';
    final value = row[column]?.value;
    return switch (value) {
      TextCellValue() => value.value.toString().trim(),
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => value.value.toString(),
      DateCellValue() => '${value.month}/${value.day}',
      DateTimeCellValue() => '${value.month}/${value.day}',
      TimeCellValue() =>
        '${value.hour.toString().padLeft(2, '0')}:'
            '${value.minute.toString().padLeft(2, '0')}',
      _ => value?.toString().trim() ?? '',
    };
  }
}

class _IbSheetLayout {
  const _IbSheetLayout({
    required this.sheetName,
    required this.sheet,
    required this.headerRow,
    required this.dateColumns,
    required this.headerValues,
    required this.score,
  });

  final String sheetName;
  final Sheet sheet;
  final int headerRow;
  final Map<int, DateTime> dateColumns;
  final Map<int, String> headerValues;
  final int score;
}
