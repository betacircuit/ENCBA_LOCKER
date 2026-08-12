import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class HomecomingImportResult {
  const HomecomingImportResult({required this.fileName, required this.rows});

  final String fileName;
  final List<Map<String, dynamic>> rows;
}

class HomecomingImportService {
  Future<HomecomingImportResult?> pickAndParse() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) throw const FormatException('엑셀 파일을 읽지 못했습니다.');
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) throw const FormatException('엑셀 시트가 비어 있습니다.');
    final sheet = workbook.tables.values.first;

    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < sheet.rows.length; index++) {
      final cells = sheet.rows[index];
      String valueAt(int column) {
        if (column >= cells.length) return '';
        return cells[column]?.value?.toString().trim() ?? '';
      }

      // 원본 양식은 B:J를 사용한다. C(이름), D(학번), F(휴대폰)가 핵심 키다.
      final name = valueAt(2);
      final phone = valueAt(5);
      if (name.isEmpty || name == '이름' || phone.isEmpty || phone == '휴대폰') {
        continue;
      }
      final generationText = valueAt(3).replaceAll(RegExp(r'[^0-9]'), '');
      final rawStatus = valueAt(6);
      rows.add({
        'source_row': index + 1,
        'senior_name': name,
        'generation': int.tryParse(generationText),
        'home_or_office_phone': valueAt(4).isEmpty ? null : valueAt(4),
        'phone': phone,
        'contact_status': _normalizeStatus(rawStatus),
        'parking_required': _parkingRequired(rawStatus, valueAt(7)),
        'assigned_to_name': valueAt(1).isEmpty ? null : valueAt(1),
        'notes': [
          valueAt(8),
          valueAt(9),
        ].where((value) => value.isNotEmpty).join(' · '),
      });
    }
    if (rows.isEmpty) throw const FormatException('연락 가능한 OB 행을 찾지 못했습니다.');
    return HomecomingImportResult(fileName: file.name, rows: rows);
  }

  String _normalizeStatus(String value) {
    if (value.contains('불참')) return 'declined';
    if (value.contains('참석')) return 'confirmed';
    if (value.contains('미정')) return 'contacted';
    return 'pending';
  }

  bool? _parkingRequired(String attendance, String parking) {
    final combined = '$attendance $parking';
    if (combined.contains('주차권 0') || combined.contains('주차권0')) return false;
    if (parking.contains('필요') || parking == 'O' || parking == 'o') return true;
    return null;
  }
}
