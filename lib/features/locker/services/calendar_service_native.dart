import 'package:add_2_calendar/add_2_calendar.dart' as calendar;
import 'package:encba_locker/features/locker/domain/locker_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<bool> addEventToCalendar(LockerEvent event) async {
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return await calendar.Add2Calendar.addEvent2Cal(
      calendar.Event(
        title: event.title,
        description: event.memo,
        location: event.fullPlace,
        startDate: event.start,
        endDate: event.end,
        iosParams: const calendar.IOSParams(reminder: Duration(hours: 1)),
      ),
    );
  } on MissingPluginException {
    return false;
  }
}
