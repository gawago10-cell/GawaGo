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

  testWidgets('Retry on Find Jobs actually reloads after a failed load', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    // The job list fails until the "network" comes back.
    var jobsAvailable = false;
    GawaGoApi.setClient(
      MockClient((request) async {
        final path = request.url.path;
        final isJobList =
            path.endsWith('/jobs/') && !path.endsWith('/applications/');
        if (isJobList && !jobsAvailable) {
          return http.Response('{"detail":"Server error."}', 500);
        }
        return _workerResponses(request);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();
    await _openWorkerPage(tester, 'Find Jobs');
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsWidgets);

    jobsAvailable = true;
    await tester.tap(find.text('Retry').last);
    await tester.pumpAndSettle();

    // Retry used to only rebuild around the same failed future, so the error
    // stayed on screen until the app was restarted.
    expect(find.text('Retry'), findsNothing);
    final jobsList = find
        .ancestor(
          of: find.widgetWithText(FilledButton, 'Filter'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('House cleaning'),
      320,
      scrollable: jobsList,
    );
    expect(find.text('House cleaning'), findsWidgets);
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

  testWidgets('find jobs cards identify the household and the skill fit', (
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
    await _openWorkerPage(tester, 'Find Jobs');
    await tester.pumpAndSettle();

    final jobsList = find
        .ancestor(
          of: find.widgetWithText(FilledButton, 'Filter'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('House cleaning'),
      320,
      scrollable: jobsList,
    );
    await tester.pumpAndSettle();

    // The household panel: monogram, name, and verified standing.
    expect(find.text('MH'), findsOneWidget);
    expect(find.text('Maria Household'), findsOneWidget);
    expect(find.text('Verified'), findsWidgets);

    // The worker's skills include Cleaning, so this job is a match.
    expect(find.text('Matches Skills'), findsOneWidget);
    expect(find.text('Other Job'), findsNothing);

    // Rate, schedule and distance as the card lays them out.
    expect(find.text('Cleaning'), findsWidgets);
    expect(find.text('One-Time'), findsOneWidget);
    expect(
      find.text('2026-06-12 to 2026-06-12 (1 working day)'),
      findsOneWidget,
    );
  });

  testWidgets('worker job detail matches the website card order and rows', (
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
    await _openWorkerPage(tester, 'Find Jobs');
    await tester.pumpAndSettle();

    // The job card sits below the AI hero and the filter card, so it is not
    // built until the list scrolls down to it. The scrollable is pinned to
    // the Find Jobs list: the drawer's IndexedStack keeps the dashboard and
    // its horizontal metric strip alive, so several Scrollables are live.
    final jobsList = find
        .ancestor(
          of: find.widgetWithText(FilledButton, 'Filter'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('View Details'),
      320,
      scrollable: jobsList,
    );
    await tester.ensureVisible(find.text('View Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'View Details'));
    await tester.pumpAndSettle();

    // The detail route's own list; the pushed route sits above the Find Jobs
    // list, which is still in the tree.
    final detailList = find.byType(Scrollable).last;
    Future<void> scrollTo(String text) async {
      await tester.scrollUntilVisible(
        find.text(text),
        300,
        scrollable: detailList,
      );
      await tester.pumpAndSettle();
    }

    // The four cards the website renders, in the website's order.
    expect(find.text('Household Profile'), findsOneWidget);
    expect(find.text('House cleaning'), findsWidgets);

    // Contact details stay withheld until the worker is actually hired.
    expect(
      find.text('Contact details become available after you are hired.'),
      findsOneWidget,
    );

    // Rows that only exist once the scheduling fields are read back.
    expect(find.text('FULL-TIME'), findsOneWidget);
    expect(find.text('Job Period'), findsOneWidget);
    expect(
      find.text('2026-06-12 TO 2026-06-15 (3 WORKING DAYS)'),
      findsOneWidget,
    );
    expect(find.text('Working Days'), findsOneWidget);
    expect(find.text('3 DAYS'), findsOneWidget);
    expect(find.text('0/2 HIRED'), findsOneWidget);

    // A hire request routes the worker back where they came from.
    await scrollTo('Back to Notifications');
    expect(find.text('Back to Notifications'), findsOneWidget);

    await scrollTo('Distance & Locations');
    expect(find.text('Distance & Locations'), findsOneWidget);
    // A distance must not be title-cased the way a status label is.
    expect(find.text('Distance unavailable'), findsOneWidget);
    // No coordinates in the fixture, so the map falls back to its panel.
    expect(find.text('Location coordinates unavailable.'), findsOneWidget);

    await scrollTo('Photos of Work Area');
    expect(find.text('Photos of Work Area'), findsOneWidget);
    expect(find.text('No photos uploaded yet.'), findsOneWidget);
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

    // The drawer's item list grew (Reports, My Complaints), so the Account
    // section can sit below the initially-built viewport/cache extent --
    // scroll the sidebar's own ListView to bring it into the element tree.
    // The mocked profile is verified, so the item reads "Verified" like the
    // website's menu instead of inviting the worker to verify again.
    final drawer = find.byType(AnimatedPositioned);
    await tester.scrollUntilVisible(
      find.descendant(of: drawer, matching: find.text('My Profile')),
      200,
      scrollable: find.descendant(
        of: drawer,
        matching: find.byType(Scrollable),
      ),
    );

    expect(find.text('My Profile'), findsOneWidget);
    expect(
      find.descendant(of: drawer, matching: find.text('Verified')),
      findsOneWidget,
    );
    expect(find.text('Get Verified'), findsNothing);
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

  testWidgets(
    'household dashboard has no in-process jobs once everything is finished',
    (tester) async {
      // Every job in this fixture is completed or cancelled, so the
      // Dashboard's "IN PROCESS" section -- which now only shows jobs still
      // in motion, mirroring web's inProcessHouseholdJobs split -- should be
      // empty; the finished jobs live on My Jobs instead.
      await SessionStorage.save(
        const AuthSession(accessToken: 'household-token', role: 'household'),
      );
      GawaGoApi.setClient(MockClient(_householdDashboardResponses));

      await tester.pumpWidget(
        MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome, juan dela cruz'), findsOneWidget);
      expect(find.textContaining('IN PROCESS'), findsOneWidget);
      expect(find.text('No posted jobs yet.'), findsOneWidget);
      expect(find.text('Driver'), findsNothing);
      expect(find.text('laundry'), findsNothing);
    },
  );

  testWidgets('household My Jobs shows the finished job history', (
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

    await _openDashboardPage(tester, 'My Jobs');
    await tester.pumpAndSettle();

    expect(find.text('Jobs Completed'), findsOneWidget);
    expect(find.text('Total Spent'), findsOneWidget);
    expect(find.text('Avg Rating Given'), findsOneWidget);
    expect(find.textContaining('All Jobs'), findsOneWidget);
    expect(find.textContaining('Completed'), findsWidgets);
    expect(find.textContaining('Cancelled'), findsWidgets);

    expect(find.text('Driver'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('laundry'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('laundry'), findsOneWidget);
    expect(find.text('Israel Cruz'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('cleaner'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('cleaner'), findsOneWidget);
    expect(find.text('No worker was hired'), findsWidgets);
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
    expect(find.text('FILTER BY JOB TYPE'), findsOneWidget);
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

  testWidgets(
    'a completed job reads Completed, not Hired, on My Applications',
    (tester) async {
      // Regression test for the mobile/web status-label mismatch: mobile
      // used to hardcode job_status == 'completed' -> 'Hired' regardless of
      // the application's real status. The backend now sends status_label
      // (apps/jobs/statuses.py) and the widget must prefer it.
      await SessionStorage.save(
        const AuthSession(accessToken: 'worker-token', role: 'worker'),
      );
      GawaGoApi.setClient(MockClient(_completedApplicationResponses));

      await tester.pumpWidget(
        MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
      );
      await tester.pumpAndSettle();

      await _openWorkerPage(tester, 'My Applications');
      await tester.pumpAndSettle();

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Hired'), findsNothing);
    },
  );

  testWidgets(
    'worker My Jobs splits active work from finished history, matching web',
    (tester) async {
      // The dedicated My Jobs tab (In Progress / Completed) exists on mobile
      // too. The household marks a job done, so an active job tells the
      // worker that instead of offering a button.
      await SessionStorage.save(
        const AuthSession(accessToken: 'worker-token', role: 'worker'),
      );
      GawaGoApi.setClient(MockClient(_myJobsResponses));

      await tester.pumpWidget(
        MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
      );
      await tester.pumpAndSettle();

      await _openWorkerPage(tester, 'My Jobs');
      await tester.pumpAndSettle();

      expect(find.text('In Progress · 1'), findsOneWidget);
      expect(find.text('Completed · 1'), findsOneWidget);
      expect(find.text('Active House Cleaning'), findsOneWidget);
      expect(
        find.text(
          'Maria Household will mark this job as done when the work is finished.',
        ),
        findsOneWidget,
      );
      expect(find.text('Mark job as complete'), findsNothing);
      expect(find.text('Finished House Cleaning'), findsOneWidget);
      expect(find.text('Rating received: 4.5 / 5'), findsOneWidget);
    },
  );
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
        'household_verification_status': 'verified',
        'job_type': 'Cleaning',
        'required_skill': 'Cleaning',
        'schedule': 'June 12, 2026 at 9:00 AM',
        'schedule_type': 'One-Time',
        'job_start_date': '2026-06-12',
        'job_end_date': '2026-06-12',
        'estimated_working_days': 1,
        'description': 'Clean the living room.',
        'location_label': 'Tayabas City',
        'service_rate': '500.00',
        'status': 'open',
        'route_distance_km': 2.4,
        'route_points': [],
        'can_apply': true,
        'can_accept_hire_request': false,
        'can_request_completion': false,
        'can_review': false,
      },
    ]);
  }
  if (path.endsWith('/notifications/unread-count/')) {
    return _json({'unread': 1});
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
      'schedule_type': 'Full-Time',
      'job_start_date': '2026-06-12',
      'job_end_date': '2026-06-15',
      'estimated_working_days': 3,
      'hired_count': 0,
      'workers_needed': 2,
      'description': 'Clean the living room.',
      'location_label': 'Tayabas City',
      'service_rate': '500.00',
      'status': 'open',
      'route_points': [],
      'images': [],
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
  if (path.endsWith('/reviews/')) {
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
          {
            'id': 31,
            'worker_username': 'israel',
            'worker_name': 'Israel Cruz',
            'status': 'completed',
          },
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

Future<http.Response> _completedApplicationResponses(
  http.Request request,
) async {
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
      },
    });
  }
  if (path.endsWith('/jobs/applications/')) {
    // Mirrors what apps/jobs/serializers.py actually returns for a hired
    // application whose job has been confirmed complete: status_stage/
    // status_label are the single source of truth the client must render.
    return _json([
      {
        'id': 1,
        'job_id': 8,
        'job_title': 'House cleaning',
        'job_type': 'Cleaning',
        'job_status': 'completed',
        'status': 'completed',
        'status_stage': 'completed',
        'status_label': 'Completed',
        'note': '',
        'applied_at': '2026-06-09T10:00:00+08:00',
      },
    ]);
  }
  if (path.endsWith('/jobs/') || path.endsWith('/notifications/')) {
    return _json([]);
  }
  return _json({});
}

Future<http.Response> _myJobsResponses(http.Request request) async {
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
      },
    });
  }
  if (path.endsWith('/jobs/applications/')) {
    return _json([
      {
        'id': 1,
        'job_id': 8,
        'job_title': 'Active House Cleaning',
        'job_type': 'Cleaning',
        'job_status': 'assigned',
        'household_username': 'maria',
        'household_name': 'Maria Household',
        'location_label': 'Tayabas City',
        'service_rate': '700.00',
        'status': 'hired',
        'status_stage': 'in_progress',
        'status_label': 'In progress',
        'can_request_completion': true,
        'note': '',
        'applied_at': '2026-06-09T10:00:00+08:00',
      },
      {
        'id': 2,
        'job_id': 9,
        'job_title': 'Finished House Cleaning',
        'job_type': 'Cleaning',
        'job_status': 'completed',
        'household_username': 'maria',
        'household_name': 'Maria Household',
        'location_label': 'Tayabas City',
        'service_rate': '650.00',
        'status': 'completed',
        'status_stage': 'completed',
        'status_label': 'Completed',
        'can_request_completion': false,
        'note': '',
        'applied_at': '2026-05-01T10:00:00+08:00',
      },
    ]);
  }
  if (path.endsWith('/reviews/')) {
    return _json([
      {
        'id': 5,
        'author_username': 'maria',
        'author_name': 'Maria Household',
        'target_username': 'juan',
        'target_name': 'Juan Worker',
        'job': 9,
        'job_title': 'Finished House Cleaning',
        'rating': '4.5',
        'feedback': 'Great work.',
        'created_at': '2026-06-10T09:30:00+08:00',
      },
    ]);
  }
  if (path.endsWith('/jobs/') || path.endsWith('/notifications/')) {
    return _json([]);
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
