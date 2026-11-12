import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/api/gawago_api.dart';
import 'package:gawago_mobile/src/core/storage/session_storage.dart';
import 'package:gawago_mobile/src/features/household/presentation/household_home_screen.dart';
import 'package:gawago_mobile/src/features/worker/presentation/worker_home_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fourth scan of 2026-11-01, driven through the real screens: a worker
/// backs out of a hire or withdraws an application, and a household cancels
/// a job it already hired for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await SessionStorage.clear();
  });

  tearDown(GawaGoApi.resetClient);

  Future<void> openPage(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a hired worker backs out of a job before it starts', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    final posts = <http.Request>[];
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'POST') posts.add(request);
        return _workerResponses(request, hired: posts.isEmpty);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();
    await openPage(tester, 'My Jobs');

    final backOut = find.text('Back out of this job');
    await tester.ensureVisible(backOut);
    await tester.pumpAndSettle();
    await tester.tap(backOut);
    await tester.pumpAndSettle();

    expect(find.text('Back out of Garden Trimming?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'I got sick.');
    await tester.pump();
    await tester.tap(find.text('Back Out'));
    await tester.pumpAndSettle();

    expect(posts, hasLength(1));
    expect(posts.single.url.path, endsWith('/jobs/applications/21/withdraw/'));
    expect(jsonDecode(posts.single.body), {'reason': 'I got sick.'});
    expect(
      find.textContaining('You backed out of Garden Trimming'),
      findsOneWidget,
    );
  });

  testWidgets('a worker withdraws a pending application after confirming', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'worker-token', role: 'worker'),
    );
    final posts = <http.Request>[];
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'POST') posts.add(request);
        return _workerResponses(request, hired: false, pending: posts.isEmpty);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: WorkerHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();
    await openPage(tester, 'My Applications');

    final withdraw = find.text('Withdraw');
    await tester.ensureVisible(withdraw);
    await tester.pumpAndSettle();
    await tester.tap(withdraw);
    await tester.pumpAndSettle();

    expect(
      find.text('Withdraw your application for House Cleaning Help?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
    await tester.pumpAndSettle();

    expect(posts, hasLength(1));
    expect(posts.single.url.path, endsWith('/jobs/applications/22/withdraw/'));
    expect(jsonDecode(posts.single.body), {'reason': ''});
  });

  testWidgets('a household cancels a hired job and gives the reason', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    final patches = <http.Request>[];
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'PATCH') patches.add(request);
        return _householdResponses(request);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fence Painting'), findsOneWidget);
    final cancel = find.text('Cancel Job');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(find.text('Why are you cancelling?'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).last,
      'The worker did not show up.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Job'));
    await tester.pumpAndSettle();

    expect(patches, hasLength(1));
    expect(patches.single.url.path, endsWith('/jobs/31/'));
    expect(jsonDecode(patches.single.body), {
      'status': 'cancelled',
      'cancel_reason': 'The worker did not show up.',
    });
  });

  testWidgets('a household that has not rated its worker cannot post', (
    tester,
  ) async {
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    final posts = <http.Request>[];
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'POST') posts.add(request);
        if (request.url.path.endsWith('/jobs/posting-status/')) {
          return _json({
            'can_post': false,
            'kind': 'rate',
            'job_id': 31,
            'job_title': 'Fence Painting',
            'message':
                'Rate Juan Worker for Fence Painting before you post another job.',
          });
        }
        return _householdResponses(request);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();
    // The page's map keeps animating, so pumpAndSettle would never settle.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post a Job').last);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Rate your worker first.'), findsOneWidget);
    expect(
      find.text(
        'Rate Juan Worker for Fence Painting before you post another job.',
      ),
      findsOneWidget,
    );
    final postButton = find.widgetWithText(FilledButton, 'Post Job');
    expect(tester.widget<FilledButton>(postButton).onPressed, isNull);

    await tester.ensureVisible(find.text('Go to My Jobs'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Go to My Jobs'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Rate your worker first.'), findsNothing);
    expect(posts, isEmpty);
  });

  testWidgets('Post Job names each missing field under it, not in a snackbar', (
    tester,
  ) async {
    // Post a Job audit (2026-11-13).
    await SessionStorage.save(
      const AuthSession(accessToken: 'household-token', role: 'household'),
    );
    final posts = <http.Request>[];
    GawaGoApi.setClient(
      MockClient((request) async {
        if (request.method == 'POST') posts.add(request);
        if (request.url.path.endsWith('/jobs/posting-status/')) {
          return _json({'can_post': true});
        }
        return _householdResponses(request);
      }),
    );
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: HouseholdHomeScreen(onLogout: () {})),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post a Job').last);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Fields marked * are required.'), findsOneWidget);
    // Nothing is flagged until Post Job is pressed.
    expect(find.text('Choose a service type.'), findsNothing);

    final postButton = find.widgetWithText(FilledButton, 'Post Job');
    await tester.ensureVisible(postButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(postButton);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Choose a service type.'), findsOneWidget);
    expect(find.text("Enter the rate you'll pay."), findsOneWidget);
    expect(find.text('Choose the day the job starts.'), findsOneWidget);
    expect(
      find.text('Fix the fields marked in red, then press Post Job again.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(posts, isEmpty);

    // The rate's message changes as it's typed, and clears once it's fine.
    final rateField = find.widgetWithText(TextField, 'e.g. 600');
    await tester.enterText(rateField, '0.11');
    await tester.pump();
    expect(find.text('Enter a rate of at least PHP 1.00.'), findsOneWidget);
    await tester.enterText(rateField, '650');
    await tester.pump();
    expect(find.text('Enter a rate of at least PHP 1.00.'), findsNothing);
    expect(find.text("Enter the rate you'll pay."), findsNothing);
  });
}

Future<http.Response> _workerResponses(
  http.Request request, {
  bool hired = true,
  bool pending = false,
}) async {
  final path = request.url.path;
  if (request.method == 'POST' && path.contains('/withdraw/')) {
    return _json({'id': 21, 'status': 'withdrawn'});
  }
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
        'skills': ['Gardening'],
        'daily_rate': '800.00',
        'location_label': 'Tayabas City',
        'verification_status': 'verified',
        'display_rating': 'No ratings yet',
      },
    });
  }
  if (path.endsWith('/jobs/applications/')) {
    return _json([
      if (hired)
        {
          'id': 21,
          'job_id': 8,
          'job_title': 'Garden Trimming',
          'job_type': 'Gardening',
          'job_status': 'assigned',
          'job_start_date': '2026-11-20',
          'household_username': 'maria',
          'household_name': 'Maria Household',
          'location_label': 'Alitao, Tayabas City',
          'service_rate': '700.00',
          'status': 'hired',
          'status_stage': 'in_progress',
          'status_label': 'In progress',
          'can_back_out': true,
          'note': '',
          'applied_at': '2026-11-01T10:00:00+08:00',
        },
      if (pending)
        {
          'id': 22,
          'job_id': 9,
          'job_title': 'House Cleaning Help',
          'job_type': 'House Cleaning',
          'job_status': 'open',
          'household_username': 'maria',
          'household_name': 'Maria Household',
          'location_label': 'Alitao, Tayabas City',
          'service_rate': '500.00',
          'status': 'pending',
          'status_stage': 'pending',
          'status_label': 'Pending',
          'can_withdraw': true,
          'note': '',
          'applied_at': '2026-11-01T09:00:00+08:00',
        },
    ]);
  }
  if (path.endsWith('/jobs/') ||
      path.endsWith('/notifications/') ||
      path.endsWith('/reviews/')) {
    return _json([]);
  }
  return _json({});
}

Future<http.Response> _householdResponses(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/notifications/') || path.endsWith('/reviews/')) {
    return _json([]);
  }
  if (path.endsWith('/accounts/me/')) {
    return _json({
      'user': {
        'username': 'maria',
        'email': '',
        'first_name': 'Maria',
        'last_name': 'Household',
      },
      'profile': {
        'phone': '',
        'location_label': 'Alitao',
        'verification_status': 'verified',
      },
    });
  }
  if (request.method == 'PATCH' && path.endsWith('/jobs/31/')) {
    return _json({'id': 31, 'status': 'cancelled'});
  }
  if (path.endsWith('/jobs/')) {
    return _json([
      {
        'id': 31,
        'household_username': 'maria',
        'title': 'Fence Painting',
        'job_type': 'Painting',
        'required_skill': 'Painting',
        'schedule': '',
        'description': '',
        'location_label': 'Alitao, Tayabas City',
        'latitude': 14.02,
        'longitude': 121.59,
        'service_rate': '800.00',
        'workers_needed': 1,
        'hired_count': 1,
        'status': 'assigned',
        'can_review': false,
        'can_mark_done': false,
        'can_cancel': true,
        'cancel_needs_reason': true,
        'job_start_date': '2026-11-20',
        'applications': [
          {
            'id': 41,
            'worker_username': 'juan',
            'worker_name': 'Juan Worker',
            'status': 'hired',
          },
        ],
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
