// Mobile household audit (2026-11-23): the shared pieces behind the fixes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/utils/signup_validation.dart';
import 'package:gawago_mobile/src/shared/widgets/job_schedule_box.dart';
import 'package:gawago_mobile/src/shared/widgets/worker_cards.dart';

void main() {
  test('a Philippine mobile number is checked like the backend does', () {
    expect(isValidMobileNumber('9171234567'), isTrue);
    expect(isValidMobileNumber('0917 123 4567'), isTrue);
    expect(isValidMobileNumber('+63 917 123 4567'), isTrue);
    expect(isValidMobileNumber(''), isTrue);
    expect(isValidMobileNumber('12345'), isFalse);
    expect(isValidMobileNumber('8171234567'), isFalse);
  });

  test('server field errors land under their own fields', () {
    final errors = serverFieldErrors(
      {
        'detail': 'Username already exists.',
        'username': ['That username is already taken.'],
        'password': ['This password is too common.'],
      },
      const {
        'username': SignupField.username,
        'password': SignupField.password,
        'email': SignupField.email,
      },
    );

    expect(errors, {
      SignupField.username: 'That username is already taken.',
      SignupField.password: 'This password is too common.',
    });
  });

  test('a cancelled job reads its dates as planned', () {
    final words = JobScheduleWords.of(
      startDate: '2026-11-20',
      endDate: '2026-11-21',
      cancelled: true,
      today: DateTime(2026, 11, 23),
    )!;

    expect(words.startWord, 'Planned start');
    expect(words.endWord, 'Planned end');
  });

  testWidgets('an invited worker can have the invitation withdrawn', (
    tester,
  ) async {
    var withdrawn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplicantCard(
            name: 'Ben Cruz',
            locationLabel: 'Isabang',
            photoUrl: '',
            verified: true,
            matchScore: 0.85,
            ratingLabel: 'No ratings yet',
            ratingCount: 0,
            rateLabel: 'PHP 500/day',
            completedJobs: 0,
            skills: const ['Gardening'],
            bio: '',
            appliedAgo: '1 minute ago',
            isTopMatch: false,
            statusLabel: 'Awaiting worker response',
            onDecline: () {},
            onViewProfile: () {},
            onAccept: () {},
            invited: true,
            onWithdrawInvite: () => withdrawn = true,
          ),
        ),
      ),
    );

    expect(find.text('Invited 1 minute ago'), findsOneWidget);
    expect(find.text('Applied 1 minute ago'), findsNothing);
    await tester.tap(find.text('Withdraw invite'));
    expect(withdrawn, isTrue);
  });
}
