export 'calendar_service_stub.dart'
    if (dart.library.js_interop) 'calendar_service_web.dart'
    if (dart.library.io) 'calendar_service_native.dart';
