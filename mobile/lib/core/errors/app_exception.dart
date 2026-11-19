/// Custom exceptions and failure handling for the mobile app.
library aph_mobile.core.errors;

/// Base exception for all APH app errors.
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic source;

  AppException(this.message, {this.code, this.source});

  @override
  String toString() => 'AppException$code: $message';
}

/// Thrown when there is no network connectivity.
class NoInternetException extends AppException {
  NoInternetException({String? message, dynamic source})
      : super(message ?? 'No internet connection', source: source);
}

/// Thrown when the API returns an error.
class ApiException extends AppException {
  ApiException({String? message, int? statusCode, dynamic source})
      : super(message ?? 'API error', code: statusCode?.toString(), source: source);
}

/// Thrown when local storage fails.
class StorageException extends AppException {
  StorageException({String? message, dynamic source})
      : super(message ?? 'Storage error', source: source);
}

/// Thrown when authentication fails.
class AuthException extends AppException {
  AuthException({String? message, dynamic source})
      : super(message ?? 'Authentication error', source: source);
}

/// Unified failure type used by domain/data layers.
class Failure {
  final String message;
  final bool isCritical;

  const Failure({required this.message, this.isCritical = false});
}
