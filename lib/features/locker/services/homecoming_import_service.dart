import 'package:encba_locker/features/locker/services/homecoming_file_picker.dart'
    as platform_picker;
import 'package:excel/excel.dart';

class HomecomingImportResult {
  const HomecomingImportResult({
    required this.fileName,
    required this.sheetName,
    required this.rows,
    required this.missingPhoneCount,
    required this.duplicateNameCount,
    this.warnings = const [],
  });

  final String fileName;
  final String sheetName;
  final List<Map<String, dynamic>> rows;
  final int missingPhoneCount;
  final int duplicateNameCount;
  final List<String> warnings;
}

class HomecomingImportService {
  Future<HomecomingImportResult?> pickAndParse() async {
    final file = await platform_picker.pickHomecomingFile();
    if (file == null) return null;
    return parseBytes(fileName: file.name, bytes: file.bytes);
  }

  HomecomingImportResult parseBytes({
    required String fileName,
    required List<int> bytes,
  }) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('엑셀 시트가 비어 있습니다.');
    }

    final layouts = workbook.tables.entries
        .map(_findLayout)
        .whereType<_HomecomingSheetLayout>()
        .toList();
    if (layouts.isEmpty) {
      throw const FormatException(
        '홈커밍 연락망 헤더를 찾지 못했습니다. 이름과 휴대폰 또는 집/회사 열을 확인해 주세요.',
      );
    }
    layouts.sort((a, b) => b.score.compareTo(a.score));
    final layout = layouts.first;

    final rows = <Map<String, dynamic>>[];
    final nameCounts = <String, int>{};
    var missingPhoneCount = 0;
    for (
      var rowIndex = layout.headerRow + 1;
      rowIndex < layout.sheet.rows.length;
      rowIndex++
    ) {
      final row = layout.sheet.rows[rowIndex];
      final name = _valueAt(row, layout.columns[_HomecomingColumn.name]).trim();
      if (name.isEmpty) continue;
      if (name.length > 80) {
        throw FormatException('${rowIndex + 1}행 이름이 너무 깁니다.');
      }

      final mobilePhone = _normalizePhone(
        _valueAt(row, layout.columns[_HomecomingColumn.mobilePhone]),
      );
      final alternatePhone = _normalizePhone(
        _valueAt(row, layout.columns[_HomecomingColumn.alternatePhone]),
      );
      if (mobilePhone.isEmpty && alternatePhone.isEmpty) missingPhoneCount++;

      final rawStatus = _valueAt(
        row,
        layout.columns[_HomecomingColumn.attendance],
      );
      final parking = _valueAt(row, layout.columns[_HomecomingColumn.parking]);
      final notes = layout.noteColumns
          .map((column) => _valueAt(row, column))
          .where((value) => value.isNotEmpty)
          .toSet()
          .join(' · ');
      final generationText = _valueAt(
        row,
        layout.columns[_HomecomingColumn.generation],
      ).replaceAll(RegExp(r'[^0-9]'), '');
      final generation = int.tryParse(generationText);
      final assignedTo = _valueAt(
        row,
        layout.columns[_HomecomingColumn.assignedTo],
      );

      nameCounts.update(name, (count) => count + 1, ifAbsent: () => 1);
      rows.add({
        'source_row': rowIndex + 1,
        'source_reference': '${layout.sheetName}!${rowIndex + 1}',
        'senior_name': name,
        'generation': generation == null || generation == 0 ? null : generation,
        'home_or_office_phone': alternatePhone.isEmpty ? null : alternatePhone,
        // 휴대폰이 없어도 카카오톡 조사·추후 확인 대상인 사람 자체는 보존한다.
        'phone': mobilePhone,
        'contact_status': _normalizeStatus(rawStatus),
        'parking_required': _parkingRequired(rawStatus, parking),
        'assigned_to_name': assignedTo.isEmpty ? null : assignedTo,
        'notes': notes.isEmpty ? null : notes,
      });
    }
    if (rows.isEmpty) {
      throw const FormatException('홈커밍 연락 대상 행을 찾지 못했습니다.');
    }
    if (rows.length > 1000) {
      throw const FormatException('한 번에 가져올 수 있는 연락 대상은 1,000명까지입니다.');
    }

    final duplicateNameCount = nameCounts.values
        .where((count) => count > 1)
        .length;
    final warnings = <String>[
      if (missingPhoneCount > 0)
        '휴대폰과 집/회사 번호가 모두 없는 $missingPhoneCount명도 명단에 포함됩니다.',
      if (duplicateNameCount > 0)
        '동명이인으로 보이는 이름 $duplicateNameCount개가 있습니다. 원본 행을 유지해 각각 가져옵니다.',
      if (layouts.length > 1)
        '연락망 형식의 시트가 여러 개라 데이터가 가장 많은 ${layout.sheetName} 시트를 선택했습니다.',
    ];
    return HomecomingImportResult(
      fileName: fileName,
      sheetName: layout.sheetName,
      rows: rows,
      missingPhoneCount: missingPhoneCount,
      duplicateNameCount: duplicateNameCount,
      warnings: warnings,
    );
  }

  _HomecomingSheetLayout? _findLayout(MapEntry<String, Sheet> entry) {
    _HomecomingSheetLayout? best;
    final rows = entry.value.rows;
    for (
      var rowIndex = 0;
      rowIndex < rows.length && rowIndex < 25;
      rowIndex++
    ) {
      final columns = <_HomecomingColumn, int>{};
      final noteColumns = <int>[];
      for (var column = 0; column < rows[rowIndex].length; column++) {
        final header = _normalizedHeader(_valueAt(rows[rowIndex], column));
        final kind = _headerAliases[header];
        if (kind == null) continue;
        if (kind == _HomecomingColumn.note) {
          noteColumns.add(column);
        } else {
          columns.putIfAbsent(kind, () => column);
        }
      }
      if (!columns.containsKey(_HomecomingColumn.name) ||
          (!columns.containsKey(_HomecomingColumn.mobilePhone) &&
              !columns.containsKey(_HomecomingColumn.alternatePhone))) {
        continue;
      }
      final populatedNames = rows
          .skip(rowIndex + 1)
          .where(
            (row) => _valueAt(row, columns[_HomecomingColumn.name]).isNotEmpty,
          )
          .length;
      final candidate = _HomecomingSheetLayout(
        sheetName: entry.key,
        sheet: entry.value,
        headerRow: rowIndex,
        columns: columns,
        noteColumns: noteColumns,
        score: populatedNames * 10 + columns.length + noteColumns.length,
      );
      if (best == null || candidate.score > best.score) best = candidate;
    }
    return best;
  }

  String _normalizeStatus(String value) {
    if (value.contains('불참')) return 'declined';
    if (value.contains('참석')) return 'confirmed';
    if (value.contains('미정') || value.contains('연락')) return 'contacted';
    return 'pending';
  }

  bool? _parkingRequired(String attendance, String parking) {
    final combined = '$attendance $parking'.replaceAll(' ', '').toLowerCase();
    if (combined.contains('주차권0') ||
        parking.trim() == '0' ||
        parking.trim().toLowerCase() == 'x' ||
        parking.contains('불필요')) {
      return false;
    }
    if (parking.contains('필요') ||
        parking.trim() == '1' ||
        parking.trim().toLowerCase() == 'o') {
      return true;
    }
    return null;
  }

  String _normalizePhone(String raw) {
    var value = raw.trim();
    if (value.endsWith('.0') && RegExp(r'^\d+\.0$').hasMatch(value)) {
      value = value.substring(0, value.length - 2);
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10 && digits.startsWith('10')) {
      return '0${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    if (digits.length == 11 && digits.startsWith('010')) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    return value;
  }

  String _valueAt(List<Data?> row, int? column) {
    if (column == null || column >= row.length) return '';
    final value = row[column]?.value;
    return switch (value) {
      TextCellValue() => value.value.toString().trim(),
      IntCellValue() => value.value.toString(),
      DoubleCellValue() => value.value.toString(),
      DateCellValue() => '${value.year}-${value.month}-${value.day}',
      DateTimeCellValue() => value.toString(),
      TimeCellValue() =>
        '${value.hour.toString().padLeft(2, '0')}:'
            '${value.minute.toString().padLeft(2, '0')}',
      _ => value?.toString().trim() ?? '',
    };
  }

  String _normalizedHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s/·_.-]'), '');
}

enum _HomecomingColumn {
  assignedTo,
  name,
  generation,
  alternatePhone,
  mobilePhone,
  attendance,
  parking,
  note,
}

const _headerAliases = <String, _HomecomingColumn>{
  '연락담당': _HomecomingColumn.assignedTo,
  '담당자': _HomecomingColumn.assignedTo,
  '이름': _HomecomingColumn.name,
  '성명': _HomecomingColumn.name,
  '학번': _HomecomingColumn.generation,
  '기수': _HomecomingColumn.generation,
  '집회사': _HomecomingColumn.alternatePhone,
  '집전화': _HomecomingColumn.alternatePhone,
  '회사전화': _HomecomingColumn.alternatePhone,
  '휴대폰': _HomecomingColumn.mobilePhone,
  '휴대전화': _HomecomingColumn.mobilePhone,
  '핸드폰': _HomecomingColumn.mobilePhone,
  '참석여부': _HomecomingColumn.attendance,
  '참석': _HomecomingColumn.attendance,
  '주차권': _HomecomingColumn.parking,
  '주차': _HomecomingColumn.parking,
  '참고': _HomecomingColumn.note,
  '비고': _HomecomingColumn.note,
  '메모': _HomecomingColumn.note,
};

class _HomecomingSheetLayout {
  const _HomecomingSheetLayout({
    required this.sheetName,
    required this.sheet,
    required this.headerRow,
    required this.columns,
    required this.noteColumns,
    required this.score,
  });

  final String sheetName;
  final Sheet sheet;
  final int headerRow;
  final Map<_HomecomingColumn, int> columns;
  final List<int> noteColumns;
  final int score;
}
