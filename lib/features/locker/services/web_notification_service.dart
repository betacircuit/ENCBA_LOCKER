export 'web_notification_service_stub.dart'
    if (dart.library.html) 'web_notification_service_web.dart'
    if (dart.library.io) 'web_notification_service_native.dart';
