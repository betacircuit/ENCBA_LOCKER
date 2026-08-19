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
    // WASM 웹 빌드에서는 FileReader가 정상 종료돼도 bytes가 비어 오는 경우가
    // 있다. readStream은 Blob.arrayBuffer를 쓰는 별도 경로라 함께 요청한다.
    withReadStream: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = await readPickedExcelBytes(file);
  return PickedHomecomingFile(name: file.name, bytes: bytes);
}

Future<List<int>> readPickedExcelBytes(PlatformFile file) async {
  final eagerBytes = file.bytes;
  if (eagerBytes != null && eagerBytes.isNotEmpty) return eagerBytes;

  final stream = file.readStream;
  if (stream != null) {
    final streamedBytes = <int>[];
    await for (final chunk in stream) {
      streamedBytes.addAll(chunk);
    }
    if (streamedBytes.isNotEmpty) return streamedBytes;
  }

  throw const FormatException('엑셀 파일을 읽지 못했습니다. 파일을 다시 선택해 주세요.');
}
