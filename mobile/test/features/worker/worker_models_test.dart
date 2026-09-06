import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';

void main() {
  test('parses backend worker profile and weekly availability', () {
    final profile = WorkerProfile.fromJson({
      'user': {
        'username': 'worker1',
        'email': 'worker@example.com',
        'first_name': 'John',
        'last_name': 'Israel',
      },
      'profile': {
        'phone': '09123456789',
        'skills': ['Cooking'],
        'hourly_rate': '120.00',
        'daily_rate': '800.00',
        'years_experience': 2,
        'location_label': 'Wakas, Tayabas City',
        'latitude': '14.0253000',
        'longitude': '121.5929000',
        'verification_status': 'verified',
        'display_rating': 'No ratings yet',
        'weekly_availability': [
          {
            'weekday': 0,
            'weekday_label': 'Monday',
            'start_time': '09:00:00',
            'end_time': '15:00:00',
          },
        ],
      },
    });

    expect(profile.fullName, 'John Israel');
    expect(profile.hourlyRate, 120);
    expect(profile.verificationStatus, 'verified');
    expect(profile.weeklyAvailability.single.label, 'Monday');
  });

  test('parses backend job action flags and application', () {
    final job = WorkerJob.fromJson({
      'id': 9,
      'title': 'Laundry',
      'household_username': 'household1',
      'household_name': 'Household One',
      'required_skill': 'Laundry',
      'service_rate': '500.00',
      'status': 'open',
      'route_distance_km': 2.45,
      'route_points': [
        [14.02, 121.59],
        [14.03, 121.60],
      ],
      'images': [
        {'id': 3, 'image_url': 'http://localhost:8000/media/jobs/laundry.jpg'},
      ],
      'can_apply': false,
      'can_accept_hire_request': true,
      'can_request_completion': false,
      'can_review': false,
      'current_worker_application': {
        'id': 12,
        'job_id': 9,
        'job_title': 'Laundry',
        'status': 'hire_requested',
      },
    });

    expect(job.distanceKm, 2.45);
    expect(job.canAcceptHireRequest, isTrue);
    expect(job.application?.status, 'hire_requested');
    expect(job.routePoints.length, 2);
    expect(job.images.single.url, contains('laundry.jpg'));
  });

  test('parses notification action metadata and resolves its job target', () {
    final notification = WorkerNotification.fromJson({
      'id': 7,
      'title': 'Hire request',
      'message': 'A household wants to hire you.',
      'notification_type': 'hiring',
      'actor_username': 'household1',
      'related_application_id': 12,
      'action_type': 'hire_request',
      'action_url': '/worker/jobs/9',
      'requires_action': true,
      'is_read': false,
      'created_at': '2026-06-10T09:30:00+08:00',
    });

    expect(notification.targetJobId, 9);
    expect(notification.applicationId, 12);
    expect(notification.actorUsername, 'household1');
    expect(notification.actionType, 'hire_request');
    expect(notification.requiresAction, isTrue);
    expect(notification.displayDate, contains('Jun 10, 2026'));
  });

  test('parses masked household feedback without exposing worker identity', () {
    final review = GawaGoReview.fromJson({
      'id': 4,
      'author_username': '',
      'author_name': 'j*** i*****',
      'target_username': 'household1',
      'target_name': 'Household One',
      'job': 9,
      'job_title': 'Laundry',
      'rating': '4.5',
      'feedback': 'Fair household.',
      'created_at': '2026-06-10T09:30:00+08:00',
    });

    expect(review.authorUsername, isEmpty);
    expect(review.authorName, 'j*** i*****');
    expect(review.rating, 4.5);
    expect(review.displayDate, 'Jun 10, 2026');
  });
}
