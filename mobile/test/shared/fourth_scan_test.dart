import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:gawago_mobile/src/features/admin/data/admin_models.dart';
import 'package:gawago_mobile/src/features/household/data/household_models.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_repository.dart';
import 'package:gawago_mobile/src/shared/widgets/worker_cards.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fourth scan of 2026-11-01: stepping away from a job, cancelling a hired
/// job, rates kept apart by rate type, and match cards that say why a worker
/// can't be asked.
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

  Map<String, dynamic> application(Map<String, dynamic> overrides) => {
    'id': 12,
    'job_id': 4,
    'job_title': 'Garden Trim',
    'status': 'pending',
    'status_stage': 'pending',
    'status_label': 'Pending',
    ...overrides,
  };

  Map<String, dynamic> job(Map<String, dynamic> overrides) => {
    'id': 4,
    'household_username': 'home1',
    'title': 'Garden Trim',
    'job_type': 'Gardening',
    'required_skill': 'Gardening',
    'schedule': '',
    'location_label': 'Alitao, Tayabas City',
    'latitude': '14.02',
    'longitude': '121.59',
    'service_rate': '700.00',
    'workers_needed': 1,
    'hired_count': 1,
    'status': 'assigned',
    'applications': [],
    ...overrides,
  };

  test('an application says whether the worker can withdraw or back out', () {
    final pending = WorkerApplication.fromJson(
      application({'can_withdraw': true}),
    );
    final hired = WorkerApplication.fromJson(
      application({'status': 'hired', 'can_back_out': true}),
    );
    final withdrawn = WorkerApplication.fromJson(
      application({'status': 'withdrawn', 'status_label': 'Withdrawn'}),
    );

    expect(pending.canWithdraw, isTrue);
    expect(pending.canBackOut, isFalse);
    expect(hired.canBackOut, isTrue);
    expect(withdrawn.statusLabel, 'Withdrawn');
    expect(withdrawn.canWithdraw, isFalse);
  });

  test('backing out sends the reason to the withdraw endpoint', () async {
    late http.Request sent;
    GawaGoApi.setClient(
      MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode(application({'status': 'withdrawn'})),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await WorkerRepository().withdraw(12, reason: 'I got sick.');

    expect(sent.method, 'POST');
    expect(sent.url.path, endsWith('/jobs/applications/12/withdraw/'));
    expect(jsonDecode(sent.body), {'reason': 'I got sick.'});
  });

  test('a hired job can be cancelled, with a reason owed', () {
    final hired = HouseholdJob.fromJson(
      job({'can_cancel': true, 'cancel_needs_reason': true}),
    );
    final done = HouseholdJob.fromJson(
      job({'status': 'completed', 'can_cancel': false}),
    );
    // An older backend without the flag: only an open job cancels.
    final legacyOpen = HouseholdJob.fromJson(job({'status': 'open'}));
    final legacyHired = HouseholdJob.fromJson(job({}));

    expect(hired.canCancel, isTrue);
    expect(hired.cancelNeedsReason, isTrue);
    expect(done.canCancel, isFalse);
    expect(legacyOpen.canCancel, isTrue);
    expect(legacyHired.canCancel, isFalse);
  });

  test('a rate row keeps the backend wording with its unit', () {
    final row = AdminAnalyticsItem.fromJson({
      'skill': 'Plumbing',
      'rateType': 'per_hour',
      'count': 2,
      'averageRate': 110.0,
      'averageRateLabel': 'PHP 110.00 / hour',
    });

    expect(row.label, 'Plumbing');
    expect(row.valueLabel, 'PHP 110.00 / hour');
  });

  testWidgets('a match card for a worker who cannot be asked is switched off', (
    tester,
  ) async {
    var sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: WorkerMatchCard(
                name: 'Worker Four',
                locationLabel: 'Ayaas',
                photoUrl: '',
                verified: false,
                matchScore: 0.4,
                ratingLabel: '3.0',
                ratingCount: 1,
                distanceLabel: '7.0 km away',
                completedJobs: 0,
                rateLabel: 'PHP 700/day',
                skills: const ['Childcare'],
                bio: '',
                onViewProfile: () {},
                onSendRequest: () => sent++,
                requestBlockedLabel: 'Not Verified Yet',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Not Verified Yet'), findsOneWidget);
    expect(find.text('Send a Request'), findsNothing);
    await tester.tap(find.text('Not Verified Yet'));
    expect(sent, 0);
  });
}
