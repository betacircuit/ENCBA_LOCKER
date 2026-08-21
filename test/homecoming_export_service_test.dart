import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:encba_locker/features/locker/services/homecoming_export_service.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final campaign = HomecomingCampaign(
    id: 'campaign-1',
    title: '2026-2 홈커밍',
    academicYear: 2026,
    term: 2,
    eventDate: _eventDate,
    startsAt: '14:00',
    endsAt: '18:00',
    venue: '기숙사체육관',
    isActive: true,
    afterpartyNote: '',
  );

  test('기존 홈커밍 열 순서로 응답을 내보내고 07학번을 보존한다', () {
    final bytes = HomecomingExportService().buildBytes(
      campaign: campaign,
      contacts: [
        HomecomingContact(
          id: 'later',
          name: '불참선배',
          phone: '010-2222-2222',
          status: 'declined',
          generation: 8,
          parkingRequired: true,
          sourceRow: 8,
          assignedToName: '성준',
        ),
        HomecomingContact(
          id: 'first',
          name: '참석선배',
          phone: '010-1111-1111',
          status: 'confirmed',
          generation: 7,
          parkingRequired: true,
          parkingRegistered: true,
          sourceRow: 7,
          assignedToName: '성준',
          notes: '확인 완료',
        ),
      ],
    );

    expect(bytes, isNotNull);
    final workbook = Excel.decodeBytes(bytes!);
    final sheet = workbook['시트1'];
    expect(_text(sheet, 1, 2), '연락담당');
    expect(_text(sheet, 2, 2), '이름');
    expect(_text(sheet, 3, 2), '학번');
    expect(_text(sheet, 6, 2), '참석여부');
    expect(_text(sheet, 7, 2), '주차권');

    expect(_text(sheet, 2, 3), '참석선배');
    expect(_text(sheet, 3, 3), '07');
    expect(_text(sheet, 6, 3), '참석');
    expect(_text(sheet, 7, 3), '필요 · 처리 완료');
    expect(_text(sheet, 9, 3), '확인 완료');

    expect(_text(sheet, 2, 4), '불참선배');
    expect(_text(sheet, 3, 4), '08');
    expect(_text(sheet, 6, 4), '불참');
    expect(_text(sheet, 7, 4), isEmpty);
  });

  test('홈커밍 표시 값은 두 자리 기수와 응답 상태를 제공한다', () {
    const contact = HomecomingContact(
      id: 'contact-1',
      name: '선배',
      phone: '',
      status: 'contacted',
      generation: 7,
    );

    expect(contact.generationCode, '07');
    expect(contact.generationLabel, '07학번');
    expect(contact.statusLabel, '미정 · 재연락');
    expect(contact.canRequestParking, isFalse);
  });
}

final _eventDate = DateTime(2026, 11, 7);

Object _text(Sheet sheet, int column, int row) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
      .value;
  return switch (value) {
    TextCellValue() => value.value.toString(),
    IntCellValue() => value.value.toString(),
    _ => '',
  };
}
