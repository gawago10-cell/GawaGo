import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:gawago_mobile/src/features/admin/data/admin_models.dart';
import 'package:gawago_mobile/src/features/admin/data/admin_repository.dart';
import 'package:gawago_mobile/src/features/admin/presentation/admin_credentials_queue.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _jwt({required Duration expiresIn}) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'exp': DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000,
      }),
    ),
  );
  return '$header.$payload.signature';
}

class _FakeAdminRepository extends AdminRepository {
  _FakeAdminRepository(this.certificates);

  final List<AdminCertificate> certificates;
  final List<(int, String, String)> reviews = [];

  @override
  Future<List<AdminCertificate>> getCertificates({
    String status = 'all',
  }) async => certificates;

  @override
  Future<AdminCertificate> reviewCertificate(
    int certificateId, {
    required String status,
    String notes = '',
  }) async {
    reviews.add((certificateId, status, notes));
    return certificates.first;
  }
}

AdminCertificate _certificate() => AdminCertificate.fromJson({
  'id': 7,
  'worker_username': 'nina',
  'worker_name': 'Nina Worker',
  'worker_location_label': 'Wakas',
  'certificate_type_label': 'TESDA Certificate',
  'certificate_name': 'NC II Housekeeping',
  'issuer': 'TESDA',
  'certificate_file_url':
      'http://host/api/accounts/portfolio/certifications/7/file/',
  'certificate_file_type': 'pdf',
  'verification_status': 'pending',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
  });

  tearDown(GawaGoApi.resetClient);

  group('session', () {
    test(
      'logging out with an expired token sends nothing and shows no expiry',
      () async {
        await SessionStorage.save(
          AuthSession(
            accessToken: _jwt(expiresIn: const Duration(hours: -1)),
            role: 'worker',
          ),
        );
        var requests = 0;
        GawaGoApi.setClient(
          MockClient((_) async {
            requests += 1;
            return http.Response('{"detail":"Token expired."}', 401);
          }),
        );
        final before = SessionStorage.sessionExpired.value;

        await GawaGoApi.logout();

        expect(requests, 0);
        expect(SessionStorage.sessionExpired.value, before);
      },
    );

    test(
      'a logout whose token turns out to be revoked is not a session expiry',
      () async {
        await SessionStorage.save(
          AuthSession(
            accessToken: _jwt(expiresIn: const Duration(hours: 1)),
            role: 'worker',
          ),
        );
        GawaGoApi.setClient(
          MockClient(
            (_) async => http.Response('{"detail":"Token revoked."}', 401),
          ),
        );
        final before = SessionStorage.sessionExpired.value;

        await GawaGoApi.logout();

        expect(SessionStorage.sessionExpired.value, before);
      },
    );

    test(
      'several requests failing with 401 at once end the session once',
      () async {
        await SessionStorage.save(
          AuthSession(
            accessToken: _jwt(expiresIn: const Duration(hours: 1)),
            role: 'worker',
          ),
        );
        GawaGoApi.setClient(
          MockClient(
            (_) async => http.Response('{"detail":"Token expired."}', 401),
          ),
        );
        final before = SessionStorage.sessionExpired.value;

        await Future.wait([
          GawaGoApi.get('/accounts/me/').catchError((_) => <String, dynamic>{}),
          GawaGoApi.get('/jobs/1/').catchError((_) => <String, dynamic>{}),
          GawaGoApi.get('/reviews/1/').catchError((_) => <String, dynamic>{}),
        ]);

        expect(SessionStorage.sessionExpired.value, before + 1);
      },
    );
  });

  group('api helpers', () {
    test('apiPath keeps file requests on the configured API', () {
      expect(
        GawaGoApi.apiPath(
          'http://elsewhere.example/api/accounts/portfolio/certifications/3/file/',
        ),
        '/accounts/portfolio/certifications/3/file/',
      );
      expect(GawaGoApi.apiPath('/notifications/'), '/notifications/');
    });

    test('the unread badge reads the count endpoint only', () async {
      await SessionStorage.save(
        AuthSession(
          accessToken: _jwt(expiresIn: const Duration(hours: 1)),
          role: 'worker',
        ),
      );
      final paths = <String>[];
      GawaGoApi.setClient(
        MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('{"unread": 4}', 200);
        }),
      );

      final count = await const WorkerRepository().getUnreadNotificationCount();

      expect(count, 4);
      expect(paths, hasLength(1));
      expect(paths.single, endsWith('/notifications/unread-count/'));
    });
  });

  group('admin dashboard parsing', () {
    test('every row shape gets a real label', () {
      final metrics = AdminDashboardMetrics.fromJson({
        'open_jobs': 9,
        'analytics': {
          'summary': {
            'activeJobs': 3,
            'totalJobPostings': 12,
            'verifiedUsers': 5,
          },
          'rateTransparency': {
            'averageRatesByCategory': [
              {'skill': 'Laundry', 'count': 2, 'averageRate': 450},
            ],
            'pricingTrends': [
              {'month': 'Oct', 'averageRate': 500, 'postings': 3},
            ],
          },
          'ratingDistribution': [
            {'stars': '5 stars', 'count': 2},
            {'stars': '4 stars', 'count': 0},
          ],
          'monthlyJobRequests': [
            {'month': 'Oct', 'requests': 4},
          ],
          'serviceAnalytics': [
            {'service': 'Cleaning', 'requests': 3},
            {'service': 'Welding', 'requests': 0},
          ],
          'enhancedAnalytics': {
            'hiringSuccessRate': 42.5,
            'jobMatchRate': 60,
            'workerHiringStats': {'hiredWorkers': 4, 'repeatHires': 1},
            'applicationTrends': [
              {'month': 'Oct', 'applications': 7},
            ],
          },
        },
      });

      expect(
        metrics.openJobs,
        3,
        reason: 'open jobs, as on web, not open slots',
      );
      expect(metrics.totalJobPostings, 12);
      expect(metrics.verifiedUsers, 5);
      expect(metrics.averageRates.single.label, 'Laundry');
      expect(metrics.averageRates.single.unit, 'PHP');
      expect(metrics.ratingDistribution.map((item) => item.label), ['5 stars']);
      expect(metrics.monthlyJobPostings.single.label, 'Oct');
      expect(metrics.monthlyJobPostings.single.value, 4);
      expect(metrics.serviceDistribution.map((item) => item.label), [
        'Cleaning',
      ]);
      expect(metrics.hiringSuccessRate, 42.5);
      expect(metrics.jobMatchRate, 60);
      expect(metrics.hiredWorkers, 4);
      expect(metrics.repeatHires, 1);
      expect(metrics.applicationTrend.single.value, 7);
      expect(metrics.pricingTrends.single.unit, 'PHP');
    });
  });

  group('admin credentials queue', () {
    Future<_FakeAdminRepository> pump(WidgetTester tester) async {
      final repository = _FakeAdminRepository([_certificate()]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminCredentialsQueue(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('lists a certificate and approves it', (tester) async {
      final repository = await pump(tester);

      expect(find.text('NC II Housekeeping'), findsOneWidget);
      expect(find.textContaining('PDF document'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(repository.reviews, [(7, 'approved', '')]);
    });

    testWidgets('cancelling the reject reason does not reject', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.reviews, isEmpty);
    });

    testWidgets('rejecting sends the reason', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Blurry scan');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(repository.reviews, [(7, 'rejected', 'Blurry scan')]);
    });
  });
}
