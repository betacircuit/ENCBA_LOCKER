// pub.dev의 archive 3.6.1은 dart.library.io/js 조건에만 반응해서, wasm 빌드
// (dart2wasm)에서는 이 둘 다 거짓이라 스텁으로 빠져 "inflateBuffer requires
// html or io."로 죽는다. dart.library.js_interop은 wasm에서도 참이고,
// _inflate_buffer_html.dart는 애초에 dart:html 없이 순수 Dart Inflate만
// 쓰므로 그대로 재사용해도 안전하다. (archive 4.0.3에서 정식으로 고쳐졌지만
// 4.x는 excel 4.0.6이 쓰는 API와 호환되지 않아 이 저장소에 직접 반영한다.)
import '_inflate_buffer_stub.dart'
    if (dart.library.io) '_inflate_buffer_io.dart'
    if (dart.library.js) '_inflate_buffer_html.dart'
    if (dart.library.js_interop) '_inflate_buffer_html.dart';

List<int>? inflateBuffer(List<int> array) {
  return inflateBuffer_(array);
}

bool useNativeZLib() {
  return useNativeZLib_();
}
