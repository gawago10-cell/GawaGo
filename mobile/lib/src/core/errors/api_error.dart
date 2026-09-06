enum ApiErrorType {
  network,
  unauthorized,
  forbidden,
  validation,
  server,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.type = ApiErrorType.unknown,
  });

  final String message;
  final int? statusCode;
  final ApiErrorType type;

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
