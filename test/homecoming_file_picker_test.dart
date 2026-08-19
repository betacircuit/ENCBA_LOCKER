import 'dart:typed_data';

import 'package:encba_locker/features/locker/services/homecoming_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('즉시 바이트가 없으면 파일 스트림으로 엑셀을 읽는다', () async {
    final file = PlatformFile(
      name: '홈커밍.xlsx',
      size: 5,
      readStream: Stream<List<int>>.fromIterable(const [
        [1, 2],
        [3, 4, 5],
      ]),
    );

    expect(await readPickedExcelBytes(file), [1, 2, 3, 4, 5]);
  });

  test('즉시 바이트가 있으면 스트림보다 먼저 사용한다', () async {
    final file = PlatformFile(
      name: 'IB리그 운영표.xlsx',
      size: 3,
      bytes: Uint8List.fromList(const [7, 8, 9]),
      readStream: Stream<List<int>>.error(StateError('읽으면 안 됨')),
    );

    expect(await readPickedExcelBytes(file), [7, 8, 9]);
  });
}
