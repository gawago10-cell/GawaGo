enum ApiErrorType {
  network,
  unauthorized,
  forbidden,
  validation,
  rateLimited,
  server,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.type = ApiErrorType.unknown,
    this.data,
  });

  final String message;
  final int? statusCode;
  final ApiErrorType type;

  /// The error response's JSON body, when it was an object.
  final Map<String, dynamic>? data;

  /// Sign-in refused until the emailed sign-up code is entered
  /// (REQUIRE_SIGNUP_EMAIL_CODE on the backend).
  bool get needsEmailCode => data?['verification_required'] == true;

  bool get isNetworkError => type == ApiErrorType.network;
  bool get isSessionExpired => type == ApiErrorType.unauthorized;

  @override
  String toString() => message;
}

String friendlyApiError(Object error) {
  return error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('TimeoutException: ', '')
      .replaceFirst('ClientException: ', '');
}
