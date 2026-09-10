import 'dart:convert';

class AvailabilityException implements Exception {
  const AvailabilityException(this.message);

  static const defaultMessage =
      'Unable to load library availability right now. Please try again shortly.';

  final String message;
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
      throw AvailabilityException(
        availabilityMessage(
          first['message'] ?? first['detail'] ?? first['error'],
        ),
      );
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
