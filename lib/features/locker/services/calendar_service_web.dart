import 'dart:js_interop';

import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:web/web.dart' as web;

Future<bool> addEventToCalendar(LockerEvent event) async {
  String stamp(DateTime value) =>
      '${value.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z';
  String escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;')
      .replaceAll('\n', '\\n');
  final ics =
      '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//ENCBA//LOCKER//KO
BEGIN:VEVENT
UID:${event.id}@encba-locker
DTSTAMP:${stamp(DateTime.now())}
DTSTART:${stamp(event.start)}
DTEND:${stamp(event.end)}
SUMMARY:${escape(event.title)}
LOCATION:${escape(event.fullPlace)}
DESCRIPTION:${escape(event.memo)}
END:VEVENT
END:VCALENDAR''';
  final blob = web.Blob(
    [ics.toJS].toJS,
    web.BlobPropertyBag(type: 'text/calendar;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = 'encba-${event.id}.ics'
    ..click();
  web.URL.revokeObjectURL(url);
  return true;
}
