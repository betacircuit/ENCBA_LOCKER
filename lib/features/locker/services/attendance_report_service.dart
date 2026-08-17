import 'dart:typed_data';

import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class AttendanceReportService {
  Future<bool> export({
    required List<AttendanceReportRow> rows,
    required bool freshmenOnly,
    required int year,
  }) async {
    final workbook = Excel.createExcel();
    final sheetName = freshmenOnly ? '신입생 출결' : '전체 출결';
    final sheet = workbook[sheetName];
    if (workbook.sheets.containsKey('Sheet1')) workbook.delete('Sheet1');

    final events = <String, AttendanceReportRow>{};
    for (final row in rows) {
      events[row.eventId] = row;
    }
    final orderedEvents = events.values.toList()
      ..sort((a, b) => a.eventStart.compareTo(b.eventStart));

    sheet.appendRow([
      TextCellValue('학번'),
      TextCellValue('이름'),
      TextCellValue('신입생'),
      ...orderedEvents.map(
        (event) => TextCellValue(
          '${DateFormat('M.d').format(event.eventStart)} ${event.eventTitle}',
        ),
      ),
      TextCellValue('참석'),
      TextCellValue('불참'),
      TextCellValue('미정/미응답'),
      TextCellValue('참석률'),
    ]);

    final byMember = <String, List<AttendanceReportRow>>{};
    for (final row in rows) {
      byMember.putIfAbsent(row.directoryId, () => []).add(row);
    }
    final members = byMember.values.toList()
      ..sort((left, right) {
        final yearCompare = (left.first.studentYear ?? 999).compareTo(
          right.first.studentYear ?? 999,
        );
        return yearCompare != 0
            ? yearCompare
            : left.first.memberName.compareTo(right.first.memberName);
      });

    for (final memberRows in members) {
      final first = memberRows.first;
      final responses = {for (final row in memberRows) row.eventId: row};
      final attending = memberRows.where((row) => row.choice == '참석').length;
      final absent = memberRows.where((row) => row.choice == '불참').length;
      final undecided = memberRows.length - attending - absent;
      final rate = memberRows.isEmpty ? 0.0 : attending / memberRows.length;
      sheet.appendRow([
        TextCellValue(first.studentYear?.toString() ?? ''),
        TextCellValue(first.memberName),
        TextCellValue(first.isFreshman ? '신입생' : ''),
        ...orderedEvents.map((event) {
          final response = responses[event.eventId];
          if (response == null || response.choice == null) {
            return TextCellValue('미응답');
          }
          final reason = response.absenceReason?.trim() ?? '';
          return TextCellValue(
            reason.isEmpty ? response.choice! : '${response.choice} · $reason',
          );
        }),
        IntCellValue(attending),
        IntCellValue(absent),
        IntCellValue(undecided),
        DoubleCellValue(rate),
      ]);
    }

    for (var column = 0; column < orderedEvents.length + 7; column++) {
      sheet.setColumnAutoFit(column);
    }
    final bytes = workbook.encode();
    if (bytes == null) return false;
    final suffix = freshmenOnly ? '신입생' : '전체';
    final result = await FilePicker.saveFile(
      dialogTitle: '출결 관리표 저장',
      fileName: '${year}_ENCBA_${suffix}_출결.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    return result != null;
  }
}
