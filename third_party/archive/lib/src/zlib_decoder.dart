import 'util/input_stream.dart';
// wasm 빌드 대응: js_interop 조건 추가 이유는 zlib/inflate_buffer.dart 참고.
import 'zlib/zlib_decoder_stub.dart'
    if (dart.library.io) 'zlib/_zlib_decoder_io.dart'
    if (dart.library.js) 'zlib/_zlib_decoder_js.dart'
    if (dart.library.js_interop) 'zlib/_zlib_decoder_js.dart';

/// Decompress data with the zlib format decoder.
class ZLibDecoder {
  static const int DEFLATE = 8;

  const ZLibDecoder();

  List<int> decodeBytes(List<int> data, {bool verify = false}) {
    return platformZLibDecoder.decodeBytes(data, verify: verify);
  }

  List<int> decodeBuffer(InputStreamBase input, {bool verify = false}) {
    return platformZLibDecoder.decodeBuffer(input, verify: verify);
  }
}
