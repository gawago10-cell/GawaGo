import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:gawago_mobile/src/app/gawago_app.dart';
import 'package:gawago_mobile/src/features/household/presentation/household_home_screen.dart';
import 'package:gawago_mobile/src/features/worker/presentation/worker_home_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
  });

  tearDown(GawaGoApi.resetClient);

  testWidgets('worker dashboard renders live profile and activity data', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    GawaGoApi.setClient(MockClient(_workerResponses));

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('OPEN JOBS'), findsOneWidget);
    expect(find.text('SKILL MATCHES'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
    expect(badges.length, 1);
    expect(badges.every((badge) => (badge.label as Text).data == '1'), isTrue);
  });

  testWidgets('worker job filters survive bottom navigation', (tester) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    GawaGoApi.setClient(MockClient(_workerResponses));

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    await _openWorkerPage(tester, 'Find Jobs');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Poblacion');

    await _openWorkerPage(tester, 'My Applications');
    await tester.pumpAndSettle();
    await _openWorkerPage(tester, 'Find Jobs');
    await tester.pumpAndSettle();

    expect(find.text('Poblacion'), findsOneWidget);
  });

  testWidgets('worker notification menu opens the backend job action', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    GawaGoApi.setClient(MockClient(_workerResponses));

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Action Required'), findsOneWidget);
    await tester.tap(find.byTooltip('Notification options').first);
    await tester.pumpAndSettle();
    expect(find.text('View Details'), findsOneWidget);

    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();

    expect(find.text('Application accepted'), findsWidgets);
    expect(find.text('Review the household request.'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('worker notification tools match the website behavior', (
    tester,
  ) async {
    var markReadRequests = 0;
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.url.path.endsWith('/notifications/2/read/')) {
          markReadRequests += 1;
        }
        return _workerResponses(request);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Filter notifications by date'), findsOneWidget);
    expect(find.byTooltip('Notification actions'), findsOneWidget);
    expect(find.textContaining('Jun 9, 2026 10:01 AM'), findsOneWidget);

    await tester.tap(find.text('Application accepted'));
    await tester.pumpAndSettle();
    expect(find.text('Job Details'), findsNothing);

    await tester.tap(find.text('Mark all as read').first);
    await tester.pumpAndSettle();
    expect(markReadRequests, 1);
    expect(find.text('All notifications marked as read.'), findsOneWidget);
  });

  testWidgets('worker drawer follows website account navigation', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    GawaGoApi.setClient(MockClient(_workerResponses));

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Get Verified'), findsOneWidget);
    expect(find.text('Reviews & Feedback'), findsNothing);
  });

  testWidgets('unverified household sees the posting restriction', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    GawaGoApi.setClient(MockClient(_householdResponses));

    await tester.pumpWidget(
      MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome, Maria Household'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    await _openDashboardPage(tester, 'Post a Job');
    await tester.pumpAndSettle();

    expect(
      find.text('Your household must be verified before posting a job.'),
      findsOneWidget,
    );
  });

  testWidgets('household dashboard shows recent completed and cancelled jobs', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    GawaGoApi.setClient(MockClient(_householdDashboardResponses));

    await tester.pumpWidget(
      MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome, juan dela cruz'), findsOneWidget);
    expect(find.text('Recent Post Jobs'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Other'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Calumpang'), findsOneWidget);
    expect(find.text('PHP 200.00 / Per Day'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('House Cleaning'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Laundry'), findsOneWidget);
    expect(find.text('House Cleaning'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Cancelled'), findsWidgets);
  });

  testWidgets('household notification tools remain available when empty', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    GawaGoApi.setClient(MockClient(_householdResponses));

    await tester.pumpWidget(
      MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Filter notifications by date'), findsOneWidget);
    expect(find.byTooltip('Notification actions'), findsOneWidget);
    expect(find.text('No notifications.'), findsOneWidget);
  });

  testWidgets('worker bottom navigation does not pop back to the launcher', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    GawaGoApi.setClient(MockClient(_workerResponses));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkerHomeScreen(onLogout: () {}),
                    ),
                  );
                },
                child: const Text('Open Worker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Worker'));
    await tester.pumpAndSettle();
    await _openWorkerPage(tester, 'Find Jobs');
    await tester.pumpAndSettle();

    expect(find.text('Open Worker'), findsNothing);
    expect(find.text('Job type'), findsOneWidget);
  });

  testWidgets('household bottom navigation does not pop back to the launcher', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    GawaGoApi.setClient(MockClient(_householdResponses));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HouseholdHomeScreen(onLogout: () {}),
                    ),
                  );
                },
                child: const Text('Open Household'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Household'));
    await tester.pumpAndSettle();
    await _openDashboardPage(tester, 'My Jobs');
    await tester.pumpAndSettle();

    expect(find.text('Open Household'), findsNothing);
    expect(find.text('My Jobs'), findsOneWidget);
  });

  testWidgets('an expired session returns the user to the landing page', (
    tester,
  ) async {
    await SessionStorage.save(
      AuthSession(accessToken: _tokenExpiringTomorrow(), role: 'worker'),
    );
    GawaGoApi.setClient(MockClient(_workerResponses));

    await tester.pumpWidget(const GawaGoApp());
    await tester.pumpAndSettle();
    expect(find.text('OPEN JOBS'), findsOneWidget);

    await SessionStorage.expire();
    await tester.pumpAndSettle();

    expect(find.text('OPEN JOBS LIVE'), findsOneWidget);
    expect(
      find.text('Your session expired. Please log in again.'),
      findsOneWidget,
    );
  });
}

Future<void> _openWorkerPage(WidgetTester tester, String label) async {
  await _openDashboardPage(tester, label);
}

Future<void> _openDashboardPage(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<http.Response> _workerResponses(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/accounts/me/')) {
    return _json({
      'user': {
        'username': 'juan',
        'email': 'juan@example.com',
        'first_name': 'Juan',
        'last_name': 'Worker',
      },
      'profile': {
        'phone': '09123456789',
        'bio': 'Cleaner',
        'skills': ['Cleaning'],
        'hourly_rate': '100.00',
        'daily_rate': '800.00',
        'years_experience': 2,
        'location_label': 'Tayabas City',
        'verification_status': 'verified',
        'display_rating': 'No ratings yet',
        'weekly_availability': [],
      },
    });
  }
  if (path.endsWith('/jobs/applications/')) {
    return _json([
      {
        'id': 1,
        'job_id': 8,
        'job_title': 'House cleaning',
        'job_type': 'Cleaning',
        'status': 'accepted',
        'note': '',
        'applied_at': '2026-06-09T10:00:00+08:00',
      },
    ]);
  }
  if (path.endsWith('/jobs/')) {
    return _json([
      {
        'id': 8,
        'title': 'House cleaning',
        'household_username': 'maria',
        'household_name': 'Maria Household',
        'job_type': 'Cleaning',
        'required_skill': 'Cleaning',
        'schedule': 'June 12, 2026 at 9:00 AM',
        'description': 'Clean the living room.',
        'location_label': 'Tayabas City',
        'service_rate': '500.00',
        'status': 'open',
        'route_points': [],
        'can_apply': true,
        'can_accept_hire_request': false,
        'can_request_completion': false,
        'can_review': false,
      },
    ]);
  }
  if (path.endsWith('/notifications/')) {
    return _json([
      {
        'id': 2,
        'title': 'Application accepted',
        'message': 'Review the household request.',
        'notification_type': 'hiring',
        'is_read': false,
        'requires_action': true,
        'related_job_id': null,
        'related_application_id': 1,
        'actor_username': 'maria',
        'action_type': 'hire_request',
        'action_url': '/worker/jobs/8',
        'created_at': '2026-06-09T10:01:00+08:00',
      },
    ]);
  }
  if (path.endsWith('/jobs/8/')) {
    return _json({
      'id': 8,
      'title': 'House cleaning',
      'household_username': 'maria',
      'household_name': 'Maria Household',
      'job_type': 'Cleaning',
      'required_skill': 'Cleaning',
      'schedule': 'June 12, 2026 at 9:00 AM',
      'description': 'Clean the living room.',
      'location_label': 'Tayabas City',
      'service_rate': '500.00',
      'status': 'open',
      'route_points': [],
      'can_apply': false,
      'can_accept_hire_request': true,
      'can_request_completion': false,
      'can_review': false,
      'current_worker_application': {
        'id': 1,
        'job_id': 8,
        'job_title': 'House cleaning',
        'job_type': 'Cleaning',
        'status': 'hire_requested',
      },
    });
  }
  if (path.endsWith('/notifications/2/read/')) {
    return _json({});
  }
  if (path.endsWith('/reviews/')) {
    final given = request.url.queryParameters['author_username'] == 'juan';
    return _json([
      {
        'id': given ? 6 : 5,
        'author_username': given ? 'juan' : 'maria',
        'author_name': given ? 'Juan Worker' : 'Maria Household',
        'target_username': given ? 'maria' : 'juan',
        'target_name': given ? 'Maria Household' : 'Juan Worker',
        'job': 8,
        'job_title': 'House cleaning',
        'rating': given ? '4.0' : '5.0',
        'feedback': given ? 'Helpful household.' : 'Excellent cleaning.',
        'created_at': '2026-06-10T09:30:00+08:00',
      },
    ]);
  }
  return _json({});
}

Future<http.Response> _householdResponses(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/accounts/me/')) {
    return _json({
      'user': {
        'username': 'maria',
        'email': 'maria@example.com',
        'first_name': 'Maria',
        'last_name': 'Household',
      },
      'profile': {
        'phone': '09987654321',
        'location_label': 'Tayabas City',
        'verification_status': 'unverified',
      },
    });
  }
  if (path.endsWith('/jobs/') || path.endsWith('/notifications/')) {
    return _json([]);
  }
  return _json({});
}

Future<http.Response> _householdDashboardResponses(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/notifications/')) {
    return _json([]);
  }
  if (path.endsWith('/accounts/me/')) {
    return _json({
      'user': {
        'username': 'juan',
        'email': '',
        'first_name': 'juan',
        'last_name': 'dela cruz',
      },
      'profile': {
        'phone': '',
        'location_label': 'Mainit',
        'verification_status': 'verified',
      },
    });
  }
  if (path.endsWith('/jobs/')) {
    return _json([
      {
        'id': 13,
        'household_username': 'juan',
        'title': 'Driver',
        'job_type': 'Other',
        'required_skill': 'Other',
        'schedule': '',
        'description': '',
        'location_label': 'Calumpang',
        'latitude': 13.95,
        'longitude': 121.59,
        'service_rate': '200.00',
        'workers_needed': 1,
        'hired_count': 0,
        'status': 'cancelled',
        'can_review': false,
        'applications': [],
        'images': [],
      },
      {
        'id': 12,
        'household_username': 'juan',
        'title': 'laundry',
        'job_type': 'Laundry',
        'required_skill': 'Laundry',
        'schedule': 'June 12, 2026 at 10:00 AM',
        'description': '',
        'location_label': 'Route 605',
        'latitude': 13.95,
        'longitude': 121.59,
        'service_rate': '0.00',
        'workers_needed': 1,
        'hired_count': 1,
        'status': 'completed',
        'can_review': false,
        'applications': [
          {'id': 31, 'worker_username': 'israel', 'status': 'completed'},
        ],
        'images': [],
      },
      {
        'id': 11,
        'household_username': 'juan',
        'title': 'cleaner',
        'job_type': 'House Cleaning',
        'required_skill': 'House Cleaning',
        'schedule': '',
        'description': '',
        'location_label': 'Tayabas Bypass Road',
        'latitude': 13.95,
        'longitude': 121.59,
        'service_rate': '300.00',
        'workers_needed': 1,
        'hired_count': 0,
        'status': 'cancelled',
        'can_review': false,
        'applications': [],
        'images': [],
      },
    ]);
  }
  return _json({});
}

http.Response _json(Object body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

String _tokenExpiringTomorrow() {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'exp':
            DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }),
    ),
  );
  return '$header.$payload.signature';
}
