// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedHomecomingFile {
  const PickedHomecomingFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

Future<PickedHomecomingFile?> pickHomecomingFile() async {
  final input = html.FileUploadInputElement()..accept = '.xlsx';
  input.click();
  await input.onChange.first;
  final file = input.files?.firstOrNull;
  if (file == null) return null;

  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;
  final result = reader.result;
  if (result is! ByteBuffer) {
    throw const FormatException('엑셀 파일을 읽지 못했습니다.');
  }
  return PickedHomecomingFile(name: file.name, bytes: Uint8List.view(result));
}
