import 'package:file_picker/file_picker.dart';

class PickedHomecomingFile {
  const PickedHomecomingFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// `file_picker`는 웹과 네이티브를 모두 지원하므로 플랫폼 분기가 필요하지 않다.
Future<PickedHomecomingFile?> pickHomecomingFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    throw const FormatException('엑셀 파일을 읽지 못했습니다.');
  }
  return PickedHomecomingFile(name: file.name, bytes: bytes);
}
