// ignore_for_file: avoid_web_libraries_in_flutter

// ignore: deprecated_member_use
import 'dart:html' as html;

import 'package:encba_locker/features/locker/domain/locker_models.dart';

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
  final blob = html.Blob([ics], 'text/calendar;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = 'encba-${event.id}.ics'
    ..click();
  html.Url.revokeObjectUrl(url);
  return true;
}
