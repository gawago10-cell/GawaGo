import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/errors/api_error.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';
import 'package:gawago_mobile/src/shared/widgets/change_password_dialog.dart';
import 'package:gawago_mobile/src/shared/widgets/reason_dialog.dart';
import 'package:gawago_mobile/src/shared/widgets/rejected_submission_note.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Third scan of 2026-11-01: change password, required reasons, the
/// rejected-submission note and the sign-up code flag.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
    await SessionStorage.save(
      const AuthSession(accessToken: 'test-token', role: 'worker'),
    );
  });

  tearDown(GawaGoApi.resetClient);

  Future<void> openChangePassword(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChangePasswordDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillPasswords(
    WidgetTester tester,
    String current,
    String next,
    String confirm,
  ) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), current);
    await tester.enterText(fields.at(1), next);
    await tester.enterText(fields.at(2), confirm);
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();
  }

  testWidgets('change password checks the new one before sending', (
    tester,
  ) async {
    var calls = 0;
    GawaGoApi.setClient(
      MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    await openChangePassword(tester);

    await fillPasswords(tester, 'OldPass#2026', 'short', 'short');
    expect(
      find.text('Use at least 8 characters for the new password.'),
      findsOneWidget,
    );
    await fillPasswords(tester, 'OldPass#2026', 'NewPass#2027', 'NewPass#2028');
    expect(find.text("The new passwords don't match."), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('change password sends both and confirms', (tester) async {
    http.Request? sent;
    GawaGoApi.setClient(
      MockClient((request) async {
        sent = request;
        return http.Response('{"detail":"Your password was updated."}', 200);
      }),
    );
    await openChangePassword(tester);

    await fillPasswords(tester, 'OldPass#2026', 'NewPass#2027', 'NewPass#2027');

    expect(sent!.url.path, endsWith('/accounts/me/password/'));
    expect(sent!.body, contains('"current_password":"OldPass#2026"'));
    expect(find.byType(ChangePasswordDialog), findsNothing);
    expect(find.text('Your password was updated.'), findsOneWidget);
  });

  testWidgets("change password shows the backend's reason", (tester) async {
    GawaGoApi.setClient(
      MockClient(
        (_) async => http.Response(
          '{"current_password":["That isn\'t your current password."]}',
          400,
        ),
      ),
    );
    await openChangePassword(tester);

    await fillPasswords(tester, 'nope', 'NewPass#2027', 'NewPass#2027');

    expect(
      find.textContaining("That isn't your current password."),
      findsOneWidget,
    );
    expect(find.byType(ChangePasswordDialog), findsOneWidget);
  });

  testWidgets('a reason dialog returns the trimmed reason', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showReasonDialog(
                  context,
                  title: 'Cancel this job?',
                  label: 'Why are you cancelling?',
                  actionLabel: 'Cancel Job',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final action = find.widgetWithText(FilledButton, 'Cancel Job');
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  The roof is fixed. ');
    await tester.pump();
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(result, 'The roof is fixed.');
  });

  testWidgets('the rejected note quotes the reason', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RejectedSubmissionNote(reason: 'The ID photo is blurry.'),
        ),
      ),
    );

    expect(
      find.textContaining('Your last submission was rejected.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Reason: “The ID photo is blurry.”'),
      findsOneWidget,
    );
  });

  test('a held sign-in is flagged for its email code', () async {
    GawaGoApi.setClient(
      MockClient(
        (_) async => http.Response(
          '{"detail":"Confirm your email first.","verification_required":true,'
          '"email":"new@example.com"}',
          403,
        ),
      ),
    );

    try {
      await GawaGoApi.login(username: 'new', password: 'Signup#2026');
      fail('login should be refused');
    } on ApiException catch (error) {
      expect(error.needsEmailCode, isTrue);
      expect(error.data?['email'], 'new@example.com');
    }
  });

  test('a worker reads why a certificate was rejected', () {
    final certificate = WorkerCertificate.fromJson({
      'id': 3,
      'certificate_name': 'Cookery NC II',
      'verification_status': 'rejected',
      'verification_notes': 'The photo is blurry.',
    });

    expect(certificate.verificationNotes, 'The photo is blurry.');
  });
}
