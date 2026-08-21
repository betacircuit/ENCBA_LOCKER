import 'dart:typed_data';

import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:file_picker/file_picker.dart';

class HomecomingExportService {
  Future<bool> export({
    required HomecomingCampaign campaign,
    required List<HomecomingContact> contacts,
  }) async {
    final bytes = buildBytes(campaign: campaign, contacts: contacts);
    if (bytes == null) return false;
    final result = await FilePicker.saveFile(
      dialogTitle: '홈커밍 연락망 저장',
      fileName:
          '${campaign.academicYear}-${campaign.term}_홈커밍_연락_응답.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    return result != null;
  }

  List<int>? buildBytes({
    required HomecomingCampaign campaign,
    required List<HomecomingContact> contacts,
  }) {
    final workbook = Excel.createExcel();
    const sheetName = '시트1';
    final sheet = workbook[sheetName];
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.delete(defaultSheet);
    }

    final navy = ExcelColor.fromHexString('#071F4B');
    final blue = ExcelColor.fromHexString('#0B5CAD');
    final paleBlue = ExcelColor.fromHexString('#EAF3FB');
    final paleYellow = ExcelColor.fromHexString('#FFF3CD');
    final paleGreen = ExcelColor.fromHexString('#E7F6EC');
    final paleGray = ExcelColor.fromHexString('#EEF1F4');
    final border = Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: ExcelColor.fromHexString('#CFD7E3'),
    );
    final centered = CellStyle(
      fontFamily: '맑은 고딕',
      fontSize: 10,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      leftBorder: border,
      rightBorder: border,
      topBorder: border,
      bottomBorder: border,
    );
    final header = centered.copyWith(
      boldVal: true,
      fontColorHexVal: ExcelColor.white,
      backgroundColorHexVal: blue,
    );
    final title = centered.copyWith(
      boldVal: true,
      fontSizeVal: 14,
      fontColorHexVal: ExcelColor.white,
      backgroundColorHexVal: navy,
    );
    final note = centered.copyWith(
      boldVal: true,
      fontColorHexVal: navy,
      backgroundColorHexVal: paleBlue,
    );

    sheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('E1'),
      customValue: TextCellValue(
        '${campaign.academicYear}년 엔크바 홈커밍 연락처',
      ),
    );
    sheet.setMergedCellStyle(CellIndex.indexByString('A1'), title);
    sheet.merge(
      CellIndex.indexByString('F1'),
      CellIndex.indexByString('J1'),
      customValue: TextCellValue('ENCBA Locker에서 내보낸 최신 응답입니다.'),
    );
    sheet.setMergedCellStyle(CellIndex.indexByString('F1'), note);

    const letters = ['', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I'];
    const headers = [
      '',
      '연락담당',
      '이름',
      '학번',
      '집/회사',
      '휴대폰',
      '참석여부',
      '주차권',
      '참고',
      '비고',
    ];
    for (var column = 0; column < headers.length; column++) {
      _writeCell(sheet, column, 1, letters[column], centered);
      _writeCell(sheet, column, 2, headers[column], header);
    }

    final ordered = contacts.toList(growable: false)
      ..sort((left, right) {
        final leftRow = left.sourceRow ?? 1 << 30;
        final rightRow = right.sourceRow ?? 1 << 30;
        final byRow = leftRow.compareTo(rightRow);
        if (byRow != 0) return byRow;
        return left.name.compareTo(right.name);
      });

    for (var index = 0; index < ordered.length; index++) {
      final contact = ordered[index];
      final row = index + 3;
      final parking = !contact.canRequestParking
          ? ''
          : contact.parkingRequired == null
          ? ''
          : contact.parkingRequired == true
          ? contact.parkingRegistered
                ? '필요 · 처리 완료'
                : '필요'
          : '불필요';
      final followUp = contact.followUpOn == null
          ? ''
          : '다시 연락 ${contact.followUpOn!.month}.${contact.followUpOn!.day}';
      final statusStyle = centered.copyWith(
        boldVal: true,
        backgroundColorHexVal: switch (contact.status) {
          'confirmed' => paleGreen,
          'contacted' => paleYellow,
          'declined' => paleGray,
          _ => ExcelColor.white,
        },
      );
      final values = [
        '${index + 1}',
        contact.assignedToName?.trim().isNotEmpty == true
            ? contact.assignedToName!.trim()
            : '담당 미지정',
        contact.name,
        contact.generationCode,
        contact.homeOrOfficePhone ?? '',
        contact.phone,
        contact.statusLabel,
        parking,
        followUp,
        contact.notes ?? '',
      ];
      for (var column = 0; column < values.length; column++) {
        _writeCell(
          sheet,
          column,
          row,
          values[column],
          column == 6 ? statusStyle : centered,
        );
      }
    }

    _mergeAssigneeGroups(sheet, ordered);
    const widths = [6.0, 13.0, 12.0, 8.0, 16.0, 16.0, 15.0, 15.0, 18.0, 34.0];
    for (var column = 0; column < widths.length; column++) {
      sheet.setColumnWidth(column, widths[column]);
    }
    sheet.setRowHeight(0, 28);
    sheet.setRowHeight(2, 24);
    return workbook.encode();
  }

  void _mergeAssigneeGroups(
    Sheet sheet,
    List<HomecomingContact> contacts,
  ) {
    var start = 0;
    while (start < contacts.length) {
      final assignee = contacts[start].assignedToName?.trim() ?? '';
      var end = start + 1;
      while (end < contacts.length &&
          (contacts[end].assignedToName?.trim() ?? '') == assignee) {
        end++;
      }
      if (end - start > 1) {
        final startCell = CellIndex.indexByColumnRow(
          columnIndex: 1,
          rowIndex: start + 3,
        );
        final endCell = CellIndex.indexByColumnRow(
          columnIndex: 1,
          rowIndex: end + 2,
        );
        sheet.merge(
          startCell,
          endCell,
          customValue: TextCellValue(
            assignee.isEmpty ? '담당 미지정' : assignee,
          ),
        );
      }
      start = end;
    }
  }

  void _writeCell(
    Sheet sheet,
    int column,
    int row,
    String value,
    CellStyle style,
  ) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
      TextCellValue(value),
      cellStyle: style,
    );
  }
}
