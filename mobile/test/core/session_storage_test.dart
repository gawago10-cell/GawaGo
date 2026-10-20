import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
  });

  test('saves and restores an authenticated session', () async {
    final token = _tokenExpiringAt(
      DateTime.now().add(const Duration(hours: 1)),
    );
    await SessionStorage.save(AuthSession(accessToken: token, role: 'worker'));

    final restored = await SessionStorage.restore();

    expect(restored?.accessToken, token);
    expect(restored?.role, 'worker');
    expect(restored?.isAuthenticated, isTrue);
  });

  test('clears an expired persisted session', () async {
    await SessionStorage.save(
      AuthSession(
        accessToken: _tokenExpiringAt(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        role: 'household',
      ),
    );

    expect(await SessionStorage.restore(), isNull);
    expect(SessionStorage.currentSession, isNull);
  });
}

String _tokenExpiringAt(DateTime dateTime) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'exp': dateTime.millisecondsSinceEpoch ~/ 1000})),
  );
  return '$header.$payload.signature';
}
