import 'package:flutter/services.dart';
import 'package:preconnect/tools/platform_channels.dart';

enum Frequency { daily, weekly, monthly, yearly }

class Recurrence {
  const Recurrence({required this.frequency, this.interval = 1});

  final Frequency frequency;
  final int interval;
}

class Event {
  const Event({
    required this.title,
    required this.startDate,
    required this.endDate,
    this.description,
    this.location,
    this.recurrence,
  });

  final String title;
  final String? description;
  final String? location;
  final DateTime startDate;
  final DateTime endDate;
  final Recurrence? recurrence;
}

class Add2Calendar {
  Add2Calendar._();

  static const MethodChannel _channel = MethodChannel(
    PlatformChannels.calendar,
  );

  static Future<bool> addEvent2Cal(Event event) async {
    return await _channel.invokeMethod<bool>('add', <String, Object?>{
          'title': event.title,
          'description': event.description,
          'location': event.location,
          'start': event.startDate.millisecondsSinceEpoch,
          'end': event.endDate.millisecondsSinceEpoch,
          'frequency': event.recurrence?.frequency.index,
          'interval': event.recurrence?.interval,
        }) ??
        false;
  }
}
