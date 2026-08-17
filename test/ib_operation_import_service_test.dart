import 'package:encba_locker/features/locker/services/ib_operation_import_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

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

  test('제공된 실제 IB 운영표 양식을 읽는다', () {
    const path = r'C:\Users\Jaewon\Downloads\26-1 IB리그 운영표.xlsx';
    final file = File(path);
    if (!file.existsSync()) return;
    final result = IbOperationImportService().parseBytes(
      fileName: '26-1 IB리그 운영표.xlsx',
      bytes: file.readAsBytesSync(),
    );
    // 실제 운영표의 셀 위치·보조 시간 칸을 회귀 기준으로 고정한다.
    expect(result.dateCount, 13);
    expect(result.rows.length, greaterThan(50));
    expect(result.warnings, contains(contains('6월 22일은 실제 월요일')));
    final june22ThirdGameA = result.rows.where(
      (row) =>
          row['title'] == '3경기 운영 A' &&
          (row['memo'] as String).contains('6월 22일'),
    );
    expect(june22ThirdGameA, isNotEmpty);
    expect(june22ThirdGameA.map((row) => row['starts_at']).toSet(), {
      '2026-06-22T05:00:00.000Z',
    });
  });

  test('학기가 없는 파일명은 기존 학기 자료를 지우기 전에 거부한다', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
        TextCellValue('3월 14일 (토)');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('1경기 운영 A');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value =
        TextCellValue('김엔크바');

    expect(
      () => IbOperationImportService().parseBytes(
        fileName: 'IB리그 운영표.xlsx',
        bytes: workbook.encode()!,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
