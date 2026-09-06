import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiConfig {
  const ApiConfig._();

  static const String _definedBaseUrl = String.fromEnvironment(
    'GAWAGO_API_BASE_URL',
    defaultValue: '',
  );
  static String get defaultBaseUrl {
    if (_definedBaseUrl.trim().isNotEmpty) {
      return normalizeBaseUrl(_definedBaseUrl);
    }
    return kIsWeb ? 'http://localhost:8000/api' : 'http://10.0.2.2:8000/api';
  }

  static const String _baseUrlKey = 'gawago_api_base_url';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _baseUrl = defaultBaseUrl;

  static String get baseUrl => _baseUrl;

  static Future<void> restoreBaseUrl() async {
    try {
      final savedBaseUrl = await _storage.read(key: _baseUrlKey);
      _baseUrl = savedBaseUrl == null || savedBaseUrl.trim().isEmpty
          ? defaultBaseUrl
          : normalizeBaseUrl(savedBaseUrl);
    } on MissingPluginException {
      // Widget tests do not register the platform storage plugin.
      _baseUrl = defaultBaseUrl;
    }
  }

  static Future<void> saveBaseUrl(String value) async {
    final normalizedBaseUrl = normalizeBaseUrl(value);
    _baseUrl = normalizedBaseUrl;
    try {
      await _storage.write(key: _baseUrlKey, value: normalizedBaseUrl);
    } on MissingPluginException {
      // Keep the in-memory config available in widget tests.
    }
  }

  static String normalizeBaseUrl(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) return defaultBaseUrl;
    return cleaned.endsWith('/api') ? cleaned : '$cleaned/api';
  }

  static const Duration timeout = Duration(seconds: 12);
}
