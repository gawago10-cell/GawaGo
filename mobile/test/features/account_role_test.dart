import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/app/gawago_app.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/auth/account_role.dart';
import 'package:gawago_mobile/src/core/errors/api_error.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
  });

  tearDown(GawaGoApi.resetClient);

  test('maps each backend account role, and nothing else', () {
    expect(accountRoleFrom('superadmin'), AccountRole.superadmin);
    expect(accountRoleFrom('admin'), AccountRole.admin);
    expect(accountRoleFrom(' Household '), AccountRole.household);
    expect(accountRoleFrom('worker'), AccountRole.worker);
    expect(accountRoleFrom(''), isNull);
    expect(accountRoleFrom(null), isNull);
    expect(accountRoleFrom('moderator'), isNull);
  });

  Future<Object?> loginWith(Map<String, dynamic> body) async {
    GawaGoApi.setClient(
      MockClient((_) async => http.Response(jsonEncode(body), 200)),
    );
    try {
      await GawaGoApi.login(username: 'someone', password: 'password');
      return null;
    } catch (error) {
      return error;
    }
  }

  test(
    'login with a missing or unknown role is refused, not treated as worker',
    () async {
      for (final body in [
        {'access': 'a.b.c'},
        {'access': 'a.b.c', 'role': 'moderator'},
      ]) {
        final error = await loginWith(body);
        expect(error, isA<ApiException>());
        expect((error! as ApiException).type, ApiErrorType.forbidden);
        expect(SessionStorage.currentSession, isNull);
      }
    },
  );

  test('a staff admin login keeps the admin role', () async {
    expect(await loginWith({'access': 'a.b.c', 'role': 'admin'}), isNull);
    expect(SessionStorage.currentSession?.role, 'admin');
  });

  testWidgets(
    'a stored session with an unknown role gets the unsupported screen',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: UnsupportedAccountScreen()),
      );
      await tester.pump();
      expect(
        find.text("This account type isn't supported in the app."),
        findsOneWidget,
      );
      expect(find.text('Back to sign in'), findsOneWidget);
    },
  );
}
