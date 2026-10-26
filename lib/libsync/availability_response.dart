import 'dart:convert';

class AvailabilityException implements Exception {
  const AvailabilityException(this.message);

  static const defaultMessage =
      'Unable to load library availability right now. Please try again shortly.';

  final String message;

  @override
  String toString() => message;
}

String availabilityMessage(Object? value) {
  if (value is! String) return AvailabilityException.defaultMessage;
  final message = value.trim();
  if (message.isEmpty ||
      message.length > 300 ||
      RegExp(
        r'[<>{}\[\]]|exception|traceback|stack trace|syntaxerror|socket|https?://',
        caseSensitive: false,
      ).hasMatch(message)) {
    return AvailabilityException.defaultMessage;
  }
  return message;
}

List<dynamic> parseAvailabilityResponse(int statusCode, String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const AvailabilityException(AvailabilityException.defaultMessage);
  }
  if (decoded is Map) {
    throw AvailabilityException(
      availabilityMessage(
        decoded['message'] ?? decoded['detail'] ?? decoded['error'],
      ),
    );
  }
  if (decoded is List && decoded.isNotEmpty) {
    final first = decoded.first;
    if (first is Map && !first.containsKey('room')) {
      final message = availabilityMessage(
        first['message'] ?? first['detail'] ?? first['error'],
      );
      if (statusCode == 200 &&
          message != AvailabilityException.defaultMessage) {
        return [
          <String, dynamic>{'message': message},
        ];
      }
      throw AvailabilityException(message);
    }
  }
  if (statusCode == 200 &&
      decoded is List &&
      decoded.every(
        (item) => item is Map && item['room'] is Map && item['slots'] is List,
      )) {
    return decoded;
  }
  throw const AvailabilityException(AvailabilityException.defaultMessage);
}

void validateAvailabilityRequest({
  required String startDate,
  required String endDate,
  required String startTime,
  required String endTime,
  required int capacity,
  required String library,
}) {
  DateTime? date(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().startsWith(value)
        ? parsed
        : null;
  }

  final start = date(startDate);
  final end = date(endDate);
  final time = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$');
  if (start == null ||
      end == null ||
      end.isBefore(start) ||
      !time.hasMatch(startTime) ||
      !time.hasMatch(endTime) ||
      (startDate == endDate && startTime.compareTo(endTime) >= 0) ||
      capacity < 1 ||
      capacity > 9 ||
      library.trim().isEmpty ||
      library == 'undefined' ||
      library == 'null') {
    throw const AvailabilityException(
      'Choose a valid date, time, library, and capacity.',
    );
  }
}
