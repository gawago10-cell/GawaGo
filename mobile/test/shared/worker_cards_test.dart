import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/worker_cards.dart';

void main() {
  testWidgets('a match card shows the worker facts and both actions', (
    tester,
  ) async {
    var viewedProfile = false;
    var requested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: WorkerMatchCard(
              name: 'Maria Santos',
              locationLabel: 'Poblacion, Makati',
              photoUrl: '',
              verified: true,
              matchScore: 0.94,
              ratingLabel: '4.90',
              ratingCount: 48,
              distanceLabel: '2.4 km away',
              completedJobs: 72,
              rateLabel: 'PHP 650/day',
              skills: const ['House Cleaning', 'Deep Clean', 'Laundry'],
              bio: 'Experienced house cleaner.',
              onViewProfile: () => viewedProfile = true,
              onSendRequest: () => requested = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Poblacion, Makati'), findsOneWidget);
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('✓ Verified'), findsOneWidget);
    expect(find.text('4.9'), findsOneWidget);
    expect(find.text('(48)'), findsOneWidget);
    expect(find.text('· 2.4 km away'), findsOneWidget);
    expect(find.text('· 72 jobs'), findsOneWidget);
    expect(find.text('PHP 650/day'), findsOneWidget);
    // Two skills plus a "+1" for the rest, matching the design.
    expect(find.text('House Cleaning'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.text('View Profile'));
    await tester.tap(find.text('Send a Request'));
    expect(viewedProfile, isTrue);
    expect(requested, isTrue);
  });

  testWidgets('an unrated worker reads as unrated, not as zero stars', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: WorkerMatchCard(
              name: 'New Worker',
              locationLabel: '',
              photoUrl: '',
              verified: false,
              matchScore: 0.2,
              ratingLabel: 'No ratings yet',
              ratingCount: 0,
              distanceLabel: '1.0 km away',
              completedJobs: 1,
              rateLabel: '',
              skills: const [],
              bio: '',
              onViewProfile: () {},
              onSendRequest: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('Location not set'), findsOneWidget);
    expect(find.text('· 1 job'), findsOneWidget);
    expect(find.text('✓ Verified'), findsNothing);
  });

  testWidgets('an applicant card offers all three responses', (tester) async {
    var declined = false;
    var requested = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplicantCard(
            name: 'Maria Santos',
            locationLabel: 'Poblacion, Makati',
            photoUrl: '',
            verified: true,
            matchScore: 0.94,
            ratingLabel: '4.90',
            ratingCount: 48,
            rateLabel: 'PHP 650/day',
            completedJobs: 72,
            skills: const ['House Cleaning'],
            bio: 'Experienced house cleaner.',
            appliedAgo: '2 hours ago',
            isTopMatch: true,
            statusLabel: null,
            onDecline: () => declined = true,
            onViewProfile: () {},
            onAccept: () => requested = true,
          ),
        ),
      ),
    );

    expect(find.text('94%'), findsOneWidget);
    expect(find.text('match'), findsOneWidget);
    expect(find.text('Applied 2 hours ago'), findsOneWidget);
    expect(find.text('Top AI match'), findsOneWidget);
    expect(find.text('72 jobs'), findsOneWidget);

    await tester.tap(find.text('Decline'));
    await tester.tap(find.text('Accept'));
    expect(declined, isTrue);
    expect(requested, isTrue);
  });

  testWidgets('an answered applicant only keeps the profile link', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplicantCard(
            name: 'Maria Santos',
            locationLabel: 'Poblacion, Makati',
            photoUrl: '',
            verified: true,
            matchScore: null,
            ratingLabel: '4.90',
            ratingCount: 48,
            rateLabel: 'PHP 650/day',
            completedJobs: 72,
            skills: const ['House Cleaning'],
            bio: '',
            appliedAgo: '2 hours ago',
            isTopMatch: false,
            statusLabel: 'Hire Requested',
            onDecline: () {},
            onViewProfile: () {},
            onAccept: () {},
          ),
        ),
      ),
    );

    expect(find.text('Hire Requested'), findsOneWidget);
    expect(find.text('View Profile'), findsOneWidget);
    expect(find.text('Decline'), findsNothing);
    expect(find.text('Accept'), findsNothing);
    // No score means no ring rather than a 0% one.
    expect(find.text('match'), findsNothing);
  });
}
