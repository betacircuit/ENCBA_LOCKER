import 'package:encba_locker/features/locker/services/ib_operation_import_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IB 운영표의 날짜와 담당자를 분리해 읽는다', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
        TextCellValue('3월 14일 (토)');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('1경기 운영 A');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value =
        TextCellValue('최재원');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value =
        TextCellValue('11:30 경기시작');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value =
        TextCellValue('1경기 운영 B');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)).value =
        TextCellValue('강준성/김연준');

    final result = IbOperationImportService().parseBytes(
      fileName: '26-1 IB리그 운영표.xlsx',
      bytes: workbook.encode()!,
    );

    expect(result.academicYear, 2026);
    expect(result.term, 1);
    expect(result.dateCount, 1);
    expect(result.rows, hasLength(3));
    final choi = result.rows.singleWhere(
      (row) => row['assignee_name'] == '최재원',
    );
    expect(choi['starts_at'], contains('02:30:00.000Z'));
  });
}
