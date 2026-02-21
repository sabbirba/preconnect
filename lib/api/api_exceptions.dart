sealed class PreConnectException implements Exception {
  const PreConnectException([this.message]);
  final String? message;

  @override
  String toString() => message ?? runtimeType.toString();
}

class OfflineException extends PreConnectException {
  const OfflineException() : super('No network connection');
}

class UnauthenticatedException extends PreConnectException {
  const UnauthenticatedException() : super('Not authenticated');
}

class SessionExpiredException extends PreConnectException {
  const SessionExpiredException() : super('Session expired');
}

class ApiException extends PreConnectException {
  const ApiException(this.statusCode, [super.message]);
  final int statusCode;

  @override
  String toString() =>
      'ApiException($statusCode${message != null ? ': $message' : ''})';
}

class CacheEmptyException extends PreConnectException {
  const CacheEmptyException([super.message]);
}

class MissingDependencyException extends PreConnectException {
  const MissingDependencyException(String field)
    : super('Missing required field: $field');
}
