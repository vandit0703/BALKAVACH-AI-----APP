import 'package:dio/dio.dart';

/// A field-level validation message from the backend's `validation_error`.
class FieldError {
  const FieldError({required this.field, required this.message});

  /// Last segment of the backend `location`, e.g. `email` for
  /// `["body", "email"]`.
  final String field;
  final String message;
}

/// Typed failure for every API call. Repositories throw only these.
sealed class ApiException implements Exception {
  const ApiException({required this.message, this.code, this.statusCode});

  /// Backend error code (e.g. `invalid_credentials`), when the server sent one.
  final String? code;

  /// Backend message. Safe to log; screens show localized text instead.
  final String message;
  final int? statusCode;

  @override
  String toString() => '$runtimeType($statusCode, $code)';
}

class NetworkException extends ApiException {
  const NetworkException() : super(message: 'Network unavailable');
}

class RequestTimeoutException extends ApiException {
  const RequestTimeoutException() : super(message: 'Request timed out');
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException({required super.message, super.code})
    : super(statusCode: 401);
}

class ForbiddenException extends ApiException {
  const ForbiddenException({required super.message, super.code})
    : super(statusCode: 403);
}

class NotFoundException extends ApiException {
  const NotFoundException({required super.message, super.code})
    : super(statusCode: 404);
}

class ConflictException extends ApiException {
  const ConflictException({required super.message, super.code})
    : super(statusCode: 409);
}

class ValidationException extends ApiException {
  const ValidationException({
    required super.message,
    super.code,
    this.fieldErrors = const [],
  }) : super(statusCode: 422);

  final List<FieldError> fieldErrors;
}

class ServerException extends ApiException {
  const ServerException({required super.message, super.code, super.statusCode});
}

class UnknownApiException extends ApiException {
  const UnknownApiException({
    required super.message,
    super.code,
    super.statusCode,
  });
}

/// Maps a [DioException] (and the backend error envelope inside it) to an
/// [ApiException].
ApiException mapDioException(DioException error) {
  final response = error.response;
  if (response == null) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const RequestTimeoutException(),
      _ => const NetworkException(),
    };
  }

  final status = response.statusCode;
  final envelope = _readEnvelope(response.data);
  final message = envelope.message ?? 'Request failed';
  final code = envelope.code;

  return switch (status) {
    401 => UnauthorizedException(message: message, code: code),
    403 => ForbiddenException(message: message, code: code),
    404 => NotFoundException(message: message, code: code),
    409 => ConflictException(message: message, code: code),
    422 => ValidationException(
      message: message,
      code: code,
      fieldErrors: envelope.fieldErrors,
    ),
    final int s when s >= 500 => ServerException(
      message: message,
      code: code,
      statusCode: s,
    ),
    _ => UnknownApiException(message: message, code: code, statusCode: status),
  };
}

/// Runs [request] and converts transport/HTTP failures to [ApiException].
Future<T> guardApi<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw mapDioException(error);
  } on FormatException catch (error) {
    throw UnknownApiException(message: 'Malformed response: ${error.message}');
  } on TypeError {
    throw const UnknownApiException(message: 'Unexpected response shape');
  }
}

class _Envelope {
  const _Envelope({this.code, this.message, this.fieldErrors = const []});

  final String? code;
  final String? message;
  final List<FieldError> fieldErrors;
}

_Envelope _readEnvelope(Object? data) {
  if (data is! Map<String, dynamic>) return const _Envelope();
  final error = data['error'];
  if (error is! Map<String, dynamic>) {
    // FastAPI's default shape, in case a route bypasses the custom handlers.
    final detail = data['detail'];
    return _Envelope(message: detail is String ? detail : null);
  }
  final details = error['details'];
  final fieldErrors = <FieldError>[];
  if (details is List<dynamic>) {
    for (final item in details) {
      if (item is! Map<String, dynamic>) continue;
      final location = item['location'];
      final message = item['message'];
      if (location is List<dynamic> &&
          location.isNotEmpty &&
          message is String) {
        fieldErrors.add(
          FieldError(field: location.last.toString(), message: message),
        );
      }
    }
  }
  return _Envelope(
    code: error['code'] as String?,
    message: error['message'] as String?,
    fieldErrors: fieldErrors,
  );
}
