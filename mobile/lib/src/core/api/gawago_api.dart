import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
        'phone': phone.trim(),
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
      role: data['role']?.toString() ?? 'worker',
    );
    if (result.token.isEmpty) {
      throw const ApiException(
        'Login response did not include an access token.',
      );
    }
    await SessionStorage.save(
      AuthSession(accessToken: result.token, role: result.role),
    );
    return result;
  }

  static Future<Map<String, dynamic>> get(
    String path, {
    bool authenticated = true,
  }) async {
    final data = await _send(
      () => _client.get(_uri(path), headers: _headers(authenticated)),
    );
    return _asMap(data);
  }

  static Future<List<dynamic>> getList(
    String path, {
    bool authenticated = true,
  }) async {
    final data = await _send(
      () => _client.get(_uri(path), headers: _headers(authenticated)),
    );
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic> && data['results'] is List<dynamic>) {
      return data['results'] as List<dynamic>;
    }
    throw const ApiException('API response was expected to be a list.');
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

  static Future<Map<String, dynamic>> multipartPost(
    String path, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_headers(true)..remove('Content-Type'));
    request.fields.addAll(fields);
    for (final entry in files.entries) {
      request.files.add(
        await http.MultipartFile.fromPath(entry.key, entry.value),
      );
    }
    final streamed = await _client.send(request).timeout(ApiConfig.timeout);
    final response = await http.Response.fromStream(streamed);
    return _asMap(await _decodeResponse(response));
  }

  static Future<Map<String, dynamic>> multipartPostMany(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required List<String> filePaths,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_headers(true)..remove('Content-Type'));
    request.fields.addAll(fields);
    for (final path in filePaths) {
      request.files.add(await http.MultipartFile.fromPath(fileField, path));
    }
    final streamed = await _client.send(request).timeout(ApiConfig.timeout);
    final response = await http.Response.fromStream(streamed);
    return _asMap(await _decodeResponse(response));
  }

  static Future<Map<String, dynamic>> multipartPatch(
    String path, {
    required Map<String, String> fields,
    required Map<String, String> files,
  }) async {
    final request = http.MultipartRequest('PATCH', _uri(path));
    request.headers.addAll(_headers(true)..remove('Content-Type'));
    request.fields.addAll(fields);
    for (final entry in files.entries) {
      request.files.add(
        await http.MultipartFile.fromPath(entry.key, entry.value),
      );
    }
    final streamed = await _client.send(request).timeout(ApiConfig.timeout);
    final response = await http.Response.fromStream(streamed);
    return _asMap(await _decodeResponse(response));
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final data = await _send(
      () => _client.delete(_uri(path), headers: _headers(true)),
    );
    return _asMap(data);
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

  static Future<dynamic> _send(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(ApiConfig.timeout);
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
      await SessionStorage.expire();
    }
    throw ApiException(
      _errorMessage(body),
      statusCode: response.statusCode,
      type: _errorType(response.statusCode),
    );
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
