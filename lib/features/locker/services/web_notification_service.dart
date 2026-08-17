export 'web_notification_service_stub.dart'
    if (dart.library.js_interop) 'web_notification_service_web.dart'
    if (dart.library.io) 'web_notification_service_native.dart';
