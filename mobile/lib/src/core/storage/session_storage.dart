import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthSession {
  const AuthSession({required this.accessToken, required this.role});

  final String accessToken;
  final String role;

  bool get isAuthenticated => accessToken.isNotEmpty;
}

class SessionStorage {
  SessionStorage._();

  static const _tokenKey = 'gawago_access_token';
  static const _roleKey = 'gawago_account_role';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static AuthSession? _cachedSession;
  static final ValueNotifier<int> sessionExpired = ValueNotifier<int>(0);

  static AuthSession? get currentSession => _cachedSession;
  static String? get accessToken => _cachedSession?.accessToken;

  static Future<AuthSession?> restore() async {
    final String? token;
    final String? role;
    try {
      token = await _storage.read(key: _tokenKey);
      role = await _storage.read(key: _roleKey);
    } on MissingPluginException {
      return _cachedSession;
    }
    if (token == null || token.isEmpty || role == null || role.isEmpty) {
      _cachedSession = null;
      return null;
    }
    if (_isExpired(token)) {
      await clear();
      return null;
    }

    _cachedSession = AuthSession(accessToken: token, role: role);
    return _cachedSession;
  }

  static Future<void> save(AuthSession session) async {
    try {
      await Future.wait([
        _storage.write(key: _tokenKey, value: session.accessToken),
        _storage.write(key: _roleKey, value: session.role),
      ]);
    } on MissingPluginException {
      // Widget tests do not register the platform storage plugin.
    }
    _cachedSession = session;
  }

  static Future<void> clear() async {
    try {
      await Future.wait([
        _storage.delete(key: _tokenKey),
        _storage.delete(key: _roleKey),
      ]);
    } on MissingPluginException {
      // Keep the in-memory session behavior available in widget tests.
    }
    _cachedSession = null;
  }

  static Future<void> expire() async {
    await clear();
    sessionExpired.value++;
  }

  static bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final expiresAt = payload['exp'] as int?;
      if (expiresAt == null) return true;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt;
    } catch (_) {
      return true;
    }
  }
}
