import 'dart:io';

import 'package:encba_locker/features/locker/services/homecoming_import_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('열 순서가 달라도 헤더로 찾고 연락처 없는 사람도 보존한다', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];
    for (final entry in <int, String>{
      0: '비고',
      1: '휴대폰',
      2: '이름',
      3: '참석 여부',
      4: '학번',
      5: '연락 담당',
      6: '집/회사',
      7: '주차권',
      8: '참고',
    }.entries) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: entry.key, rowIndex: 2))
          .value = TextCellValue(
        entry.value,
      );
    }
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3)).value =
        TextCellValue('김엔크바');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 3)).value =
        IntCellValue(22);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 3)).value =
        TextCellValue('참석(주차권 0)');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value =
        TextCellValue('카톡 조사');

    final result = HomecomingImportService().parseBytes(
      fileName: '2026-2 홈커밍.xlsx',
      bytes: workbook.encode()!,
    );

    expect(result.rows, hasLength(1));
    expect(result.missingPhoneCount, 1);
    expect(result.rows.single['senior_name'], '김엔크바');
    expect(result.rows.single['generation'], 22);
    expect(result.rows.single['phone'], '');
    expect(result.rows.single['contact_status'], 'confirmed');
    expect(result.rows.single['parking_required'], isFalse);
    expect(result.rows.single['notes'], '카톡 조사');
  });

  test('숫자로 저장된 휴대폰의 앞자리 0을 복원한다', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value =
        TextCellValue('이름');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value =
        TextCellValue('휴대폰');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
        TextCellValue('이숫자');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value =
        IntCellValue(1012345678);

    final result = HomecomingImportService().parseBytes(
      fileName: '홈커밍.xlsx',
      bytes: workbook.encode()!,
    );

    expect(result.rows.single['phone'], '010-1234-5678');
  });

  test('제공된 실제 홈커밍 연락망의 모든 이름을 보존한다', () {
    const path = r'C:\Users\Jaewon\Downloads\2026-2 홈커밍 연락의 사본.xlsx';
    final file = File(path);
    if (!file.existsSync()) return;

    final result = HomecomingImportService().parseBytes(
      fileName: '2026-2 홈커밍 연락의 사본.xlsx',
      bytes: file.readAsBytesSync(),
    );

    expect(result.sheetName, '시트1');
    expect(result.rows, hasLength(137));
    expect(result.missingPhoneCount, 5);
    expect(result.duplicateNameCount, 1);
    expect(
      result.rows.where((row) => row['senior_name'] == '고영찬').single['phone'],
      '',
    );
    // 연락 담당은 합친 칸이라 첫 줄에만 적혀 있다. 137명 모두에게 붙어야 한다.
    expect(
      result.rows.where((row) => row['assigned_to_name'] == null),
      isEmpty,
    );
    final byAssignee = <String, int>{};
    for (final row in result.rows) {
      byAssignee.update(
        row['assigned_to_name'] as String,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    expect(byAssignee['톡방 조사'], 52);
    expect(byAssignee['윤석'], 11);
    expect(byAssignee['이민섭'], 11);
  });

  test('합쳐진 연락 담당 칸을 아래 행까지 이어 붙인다', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];
    void put(int column, int row, String value) =>
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: row,
                  ),
                )
                .value =
            TextCellValue(value);

    put(0, 0, '연락담당');
    put(1, 0, '이름');
    put(2, 0, '휴대폰');
    put(0, 1, '윤석');
    put(1, 1, '이동수');
    put(2, 1, '010-1111-2222');
    // 합친 칸의 둘째 줄은 담당이 비어 있다.
    put(1, 2, '김달수');
    put(2, 2, '010-3333-4444');
    put(0, 3, '우진');
    put(1, 3, '조정현');
    put(2, 3, '010-5555-6666');

    final result = HomecomingImportService().parseBytes(
      fileName: '홈커밍.xlsx',
      bytes: workbook.encode()!,
    );

    expect(
      result.rows.map((row) => row['assigned_to_name']),
      ['윤석', '윤석', '우진'],
    );
  });
}
