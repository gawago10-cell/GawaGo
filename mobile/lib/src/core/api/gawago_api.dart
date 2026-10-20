import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../shared/utils/display_formatters.dart';
import '../auth/account_role.dart';
import '../config/api_config.dart';
import '../errors/api_error.dart';
import '../storage/session_storage.dart';

class AuthResult {
  const AuthResult({required this.token, required this.role});

  final String token;
  final String role;
}

class GawaGoApi {
  GawaGoApi._();

  static http.Client _client = http.Client();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  static Future<Map<String, dynamic>> register({
    required String role,
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    required String phone,
    required String barangay,
    required String streetAddress,
    String bio = '',
    String hourlyRate = '0.00',
    String dailyRate = '0.00',
    int yearsExperience = 0,
    List<String> skills = const [],
    double? latitude,
    double? longitude,
  }) {
    return post(
      '/accounts/register/',
      authenticated: false,
      body: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'role': role,
        'phone': sanitizePhilippinesPhone(phone),
        'location_label': [
          if (streetAddress.trim().isNotEmpty) streetAddress.trim(),
          if (barangay.trim().isNotEmpty) barangay.trim(),
          'Tayabas City, Quezon',
        ].join(', '),
        ...?latitude == null ? null : {'latitude': _coordinateForApi(latitude)},
        ...?longitude == null
            ? null
            : {'longitude': _coordinateForApi(longitude)},
        if (role == 'worker') ...{
          'bio': bio.trim(),
          'skills': skills,
          'hourly_rate': hourlyRate.trim().isEmpty ? '0.00' : hourlyRate.trim(),
          'daily_rate': dailyRate.trim().isEmpty ? '0.00' : dailyRate.trim(),
          'years_experience': yearsExperience,
        },
      },
    );
  }

  static Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final data = await post(
      '/accounts/login/',
      authenticated: false,
      body: {'username': username.trim(), 'password': password},
    );
    final result = AuthResult(
      token: data['access']?.toString() ?? '',
      role: data['role']?.toString().trim().toLowerCase() ?? '',
    );
    if (result.token.isEmpty) {
      throw const ApiException(
        'Login response did not include an access token.',
      );
    }
    // An unknown role used to default to "worker" and open the worker app.
    if (accountRoleFrom(result.role) == null) {
      throw const ApiException(
        "This account type isn't supported in the app. Please contact support.",
        type: ApiErrorType.forbidden,
      );
    }
    await SessionStorage.save(
      AuthSession(accessToken: result.token, role: result.role),
    );
    return result;
  }

  /// True while a deliberate logout request is in flight: its 401 (an
  /// already-expired token) is not a session expiry and must not show
  /// "Your session expired" on top of the logout.
  static bool _loggingOut = false;

  static Future<void> logout() async {
    // Best-effort: the token is being cleared from local storage regardless,
    // but without this call it stays valid server-side (revoked only by
    // jti) until it expires on its own, up to an hour later (F-14). An
    // expired token is already dead, so there is nothing to revoke.
    final token = SessionStorage.accessToken;
    if (token == null ||
        token.isEmpty ||
        SessionStorage.isTokenExpired(token)) {
      return;
    }
    _loggingOut = true;
    try {
      await post('/accounts/logout/', body: const {});
    } catch (_) {
      // Already logging the user out locally either way.
    } finally {
      _loggingOut = false;
    }
  }

  static Future<void> requestPasswordReset(String email) async {
    await post(
      '/accounts/forgot-password/',
      authenticated: false,
      body: {'email': email.trim()},
    );
  }

  static Future<void> verifyPasswordResetToken({
    required String email,
    required String token,
  }) async {
    await post(
      '/accounts/verify-reset-token/',
      authenticated: false,
      body: {'email': email.trim(), 'token': token.trim()},
    );
  }

  static Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await post(
      '/accounts/reset-password/',
      authenticated: false,
      body: {
        'email': email.trim(),
        'token': token.trim(),
        'new_password': newPassword,
      },
    );
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    bool authenticated = true,
    Duration? timeout,
  }) async {
    final data = await _send(
      () => _client.get(_uri(path), headers: _headers(authenticated)),
      timeout: timeout,
    );
    return _asMap(data);
  }

  /// Fetches a binary file from an authenticated endpoint (e.g. a
  /// verification document) with the bearer token attached -- a plain
  /// `Image.network(url)` has no way to send that header, so an
  /// IsAuthenticated file route needs this instead of `get`/`getList`,
  /// which both assume a JSON body.
  static Future<Uint8List> getBytes(
    String path, {
    bool authenticated = true,
  }) async {
    http.Response response;
    try {
      response = await _client
          .get(_uri(path), headers: _headers(authenticated))
          .timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw const ApiException(
        'The request timed out. Check your connection and try again.',
        type: ApiErrorType.network,
      );
    } on http.ClientException catch (error) {
      throw ApiException(error.message, type: ApiErrorType.network);
    } on SocketException {
      throw const ApiException(
        'No internet connection. Check your network and try again.',
        type: ApiErrorType.network,
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Non-JSON error body (e.g. an HTML 404 page) -- fall through to the
      // generic message below.
    }
    if (response.statusCode == 401) {
      if (!_loggingOut) {
        await SessionStorage.expire(detail: body['detail']?.toString());
      }
    }
    throw ApiException(
      _errorMessage(body),
      statusCode: response.statusCode,
      type: _errorType(response.statusCode),
    );
  }

  // DRF paginates list endpoints at 20 records per page. Reading only
  // `results` from the first page silently drops everything past it once a
  // collection outgrows one page -- follow `next` until it is null, the way
  // the web client's fetchAllRecords does.
  static const int _maxListPages = 100;

  static Future<List<dynamic>> getList(
    String path, {
    bool authenticated = true,
    Duration? timeout,
  }) async {
    final records = <dynamic>[];
    Uri uri = _uri(path);
    for (var page = 0; page < _maxListPages; page++) {
      final data = await _send(
        () => _client.get(uri, headers: _headers(authenticated)),
        timeout: timeout,
      );
      if (data is List<dynamic>) return data;
      if (data is Map<String, dynamic> && data['results'] is List<dynamic>) {
        records.addAll(data['results'] as List<dynamic>);
        final next = data['next'];
        if (next is! String || next.isEmpty) return records;
        uri = Uri.parse(next);
        continue;
      }
      throw const ApiException('API response was expected to be a list.');
    }
    return records;
  }

  static Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final data = await _send(
      () => _client.post(
        _uri(path),
        headers: _headers(authenticated),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _asMap(data);
  }

  static Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final data = await _send(
      () => _client.patch(
        _uri(path),
        headers: _headers(true),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _asMap(data);
  }

  static Future<dynamic> put(String path, {required dynamic body}) {
    return _send(
      () => _client.put(
        _uri(path),
        headers: _headers(true),
        body: jsonEncode(body),
      ),
    );
  }

  /// Encodes a JSON-ish value map into multipart text fields.
  ///
  /// Lists and maps are JSON-encoded rather than run through toString(): a
  /// Dart list stringifies to `[House Cleaning, Laundry]`, which the API
  /// cannot parse back into a list.
  static Map<String, String> multipartFields(Map<String, dynamic> values) {
    return values.map((key, value) {
      if (value == null) return MapEntry(key, '');
      if (value is Iterable || value is Map) {
        return MapEntry(key, jsonEncode(value));
      }
      return MapEntry(key, value.toString());
    });
  }

  // All three multipart methods route through _send() (like every other
  // method here) instead of calling _client.send() directly, so a dropped
  // connection during an upload gets the same friendly, classified
  // ApiException as everything else -- it used to surface as a raw
  // SocketException/TimeoutException string that friendlyApiError doesn't
  // know how to clean up.
  static Future<Map<String, dynamic>> multipartPost(
    String path, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    final data = await _send(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      request.headers.addAll(_headers(true)..remove('Content-Type'));
      request.fields.addAll(fields);
      for (final entry in files.entries) {
        request.files.add(await _multipartFile(entry.key, entry.value));
      }
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: ApiConfig.uploadTimeout);
    return _asMap(data);
  }

  static Future<Map<String, dynamic>> multipartPostMany(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required List<String> filePaths,
  }) async {
    final data = await _send(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      request.headers.addAll(_headers(true)..remove('Content-Type'));
      request.fields.addAll(fields);
      for (final path in filePaths) {
        request.files.add(await _multipartFile(fileField, path));
      }
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: ApiConfig.uploadTimeout);
    return _asMap(data);
  }

  static Future<Map<String, dynamic>> multipartPatch(
    String path, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    final data = await _send(() async {
      final request = http.MultipartRequest('PATCH', _uri(path));
      request.headers.addAll(_headers(true)..remove('Content-Type'));
      request.fields.addAll(fields);
      for (final entry in files.entries) {
        request.files.add(await _multipartFile(entry.key, entry.value));
      }
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: ApiConfig.uploadTimeout);
    return _asMap(data);
  }

  /// Builds one upload part from a picked file's path.
  ///
  /// On web there is no filesystem behind that path -- file_selector hands
  /// back a blob: URL -- so MultipartFile.fromPath throws. XFile reads both
  /// shapes, so going through its bytes keeps uploads working on web and
  /// native alike.
  static Future<http.MultipartFile> _multipartFile(
    String field,
    String path,
  ) async {
    final file = XFile(path);
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return http.MultipartFile.fromBytes(
        field,
        bytes,
        // A blob: URL carries no name, and the API accepts uploads by
        // extension, so "upload" alone was rejected for every file.
        filename: file.name.isEmpty
            ? 'upload${_extensionFor(bytes)}'
            : file.name,
      );
    }
    return http.MultipartFile.fromPath(field, path);
  }

  /// File extension from the leading "magic" bytes of the formats the API
  /// accepts (images and PDF); empty when unrecognised.
  static String _extensionFor(List<int> bytes) {
    bool startsWith(List<int> prefix, [int offset = 0]) =>
        bytes.length >= offset + prefix.length &&
        List.generate(prefix.length, (i) => bytes[offset + i]).join(',') ==
            prefix.join(',');
    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return '.png';
    if (startsWith([0xFF, 0xD8, 0xFF])) return '.jpg';
    if (startsWith([0x25, 0x50, 0x44, 0x46])) return '.pdf';
    if (startsWith([0x52, 0x49, 0x46, 0x46]) &&
        startsWith([0x57, 0x45, 0x42, 0x50], 8)) {
      return '.webp';
    }
    if (startsWith([0x66, 0x74, 0x79, 0x70], 4)) return '.heic';
    return '';
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final data = await _send(
      () => _client.delete(_uri(path), headers: _headers(true)),
    );
    return _asMap(data);
  }

  /// A file URL the API returned (absolute, built from the request host) as
  /// a path on the configured API, so the bearer token is only ever sent to
  /// that API and never to whatever host a URL happens to name.
  static String apiPath(String url) {
    final index = url.indexOf('/api/');
    return index == -1 ? url : url.substring(index + 4);
  }

  static Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiConfig.baseUrl}$normalizedPath');
  }

  static Map<String, String> _headers(bool authenticated) {
    final headers = Map<String, String>.from(_jsonHeaders);
    final token = SessionStorage.accessToken;
    if (authenticated && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  @visibleForTesting
  static void setClient(http.Client client) {
    _client.close();
    _client = client;
  }

  @visibleForTesting
  static void resetClient() {
    _client.close();
    _client = http.Client();
  }

  static Future<dynamic> _send(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    try {
      final response = await request().timeout(timeout ?? ApiConfig.timeout);
      return await _decodeResponse(response);
    } on TimeoutException {
      throw ApiException(
        'The request timed out. Check your connection and try again.',
        type: ApiErrorType.network,
      );
    } on http.ClientException catch (error) {
      throw ApiException(error.message, type: ApiErrorType.network);
    } on SocketException {
      throw const ApiException(
        'No internet connection. Check your network and try again.',
        type: ApiErrorType.network,
      );
    }
  }

  static Future<dynamic> _decodeResponse(http.Response response) async {
    final dynamic body;
    try {
      body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'API returned an unreadable response from ${ApiConfig.baseUrl}.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    if (response.statusCode == 401) {
      if (!_loggingOut) {
        await SessionStorage.expire(
          detail: body is Map ? body['detail']?.toString() : null,
        );
      }
    }
    final type = _errorType(response.statusCode);
    throw ApiException(
      type == ApiErrorType.rateLimited
          ? _rateLimitMessage(body)
          : _errorMessage(body),
      statusCode: response.statusCode,
      type: type,
    );
  }

  // DRF sends "Request was throttled. Expected available in 42 seconds." --
  // accurate but reads like a server log, so surface the wait time plainly.
  static String _rateLimitMessage(dynamic body) {
    final detail = body is Map<String, dynamic>
        ? body['detail']?.toString()
        : null;
    final seconds = detail == null
        ? null
        : RegExp(r'(\d+)\s*second').firstMatch(detail)?.group(1);
    if (seconds != null) {
      return 'Too many attempts. Please wait $seconds seconds and try again.';
    }
    return 'Too many attempts. Please wait a moment and try again.';
  }

  static String _errorMessage(dynamic body) {
    if (body is! Map<String, dynamic>) return 'Request failed.';
    final detail = body['detail'];
    if (detail != null) return detail.toString();

    final messages = <String>[];
    for (final entry in body.entries) {
      final value = entry.value;
      if (value is List) {
        messages.add('${_fieldLabel(entry.key)}: ${value.join(' ')}');
      } else if (value != null) {
        messages.add('${_fieldLabel(entry.key)}: $value');
      }
    }
    return messages.isEmpty ? 'Request failed.' : messages.join('\n');
  }

  static String _fieldLabel(String field) {
    final words = field.replaceAll('_', ' ');
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static ApiErrorType _errorType(int statusCode) {
    if (statusCode == 401) return ApiErrorType.unauthorized;
    if (statusCode == 403) return ApiErrorType.forbidden;
    if (statusCode == 400 || statusCode == 422) {
      return ApiErrorType.validation;
    }
    if (statusCode == 429) return ApiErrorType.rateLimited;
    if (statusCode >= 500) return ApiErrorType.server;
    return ApiErrorType.unknown;
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const ApiException('API response was expected to be an object.');
  }
}

double _coordinateForApi(double value) =>
    double.parse(value.toStringAsFixed(7));
