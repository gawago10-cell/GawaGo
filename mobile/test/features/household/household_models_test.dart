import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/household/data/household_models.dart';

void main() {
  test('parses household job applications and backend road route', () {
    final job = HouseholdJob.fromJson({
      'id': 4,
      'household_username': 'home1',
      'title': 'Cooking',
      'job_type': 'Cooking',
      'required_skill': 'Cooking',
      'schedule': 'One-Time on 2026-06-15 at 10:00',
      'location_label': 'Wakas, Tayabas City',
      'latitude': '14.0253000',
      'longitude': '121.5929000',
      'service_rate': '700.00',
      'workers_needed': 1,
      'hired_count': 0,
      'status': 'open',
      'applications': [
        {
          'id': 8,
          'worker_username': 'worker1',
          'worker_name': 'Worker One',
          'worker_location_label': 'Alitao, Tayabas City',
          'worker_latitude': 14.01,
          'worker_longitude': 121.58,
          'status': 'pending',
          'route_distance_km': 3.2,
          'route_points': [
            [14.01, 121.58],
            [14.0253, 121.5929],
          ],
        },
      ],
    });

    expect(job.title, 'Cooking');
    expect(job.applications.single.distanceKm, 3.2);
    expect(job.applications.single.workerLatitude, 14.01);
    expect(job.applications.single.workerLongitude, 121.58);
    expect(job.applications.single.routePoints.length, 2);
    // Fields omitted from the payload should fall back gracefully.
    expect(job.jobStartDate, isNull);
    expect(job.jobEndDate, isNull);
    expect(job.estimatedWorkingDays, isNull);
    expect(job.geographicBoundary, '1km');
  });

  test('parses job scheduling and distance-boundary fields', () {
    final job = HouseholdJob.fromJson({
      'id': 5,
      'household_username': 'home1',
      'title': 'Garden Maintenance',
      'job_type': 'Gardening',
      'required_skill': 'Gardening',
      'schedule': 'One-Time on 2026-06-20 at 09:00',
      'location_label': 'Isabang, Tayabas City',
      'latitude': '13.9622745',
      'longitude': '121.5632841',
      'service_rate': '600.00',
      'workers_needed': 1,
      'hired_count': 0,
      'status': 'open',
      'applications': [],
      'job_start_date': '2026-06-20',
      'job_end_date': '2026-06-22',
      'estimated_working_days': 3,
      'geographic_boundary': '5km',
    });

    expect(job.jobStartDate, '2026-06-20');
    expect(job.jobEndDate, '2026-06-22');
    expect(job.estimatedWorkingDays, 3);
    expect(job.geographicBoundary, '5km');
  });

  test('parses recommended worker matching result', () {
    final worker = RecommendedWorker.fromJson({
      'worker_id': 11,
      'worker_username': 'worker1',
      'skills': ['Cooking', 'Cleaning'],
      'verification_status': 'verified',
      'distance_km': 2.1,
      'distance_label': '2.1 km away',
      'match_score': 94.5,
      'rating_label': '4.8',
      'worker_rate': '500.00',
    });

    // Candidates carry distance only -- the API never sends a
    // not-yet-hired worker's coordinates or route.
    expect(worker.verificationStatus, 'verified');
    expect(worker.matchScore, 94.5);
    expect(worker.distanceKm, 2.1);
    expect(worker.distanceLabel, '2.1 km away');
  });

  test('applicant cards carry the ranking facts the list sorts on', () {
    final application = HouseholdApplication.fromJson({
      'id': 11,
      'worker': 7,
      'worker_username': 'worker1',
      'worker_name': 'Maria Santos',
      'worker_rating_count': 4,
      'worker_completed_jobs': 6,
      'worker_match_score': 0.82,
      'applied_at': '2026-09-15T01:19:00+08:00',
      'status': 'pending',
    });

    expect(application.workerId, 7);
    expect(application.workerRatingCount, 4);
    expect(application.workerCompletedJobs, 6);
    expect(application.workerMatchScore, 0.82);
    expect(application.appliedAt, '2026-09-15T01:19:00+08:00');
  });

  test('an unscored applicant reports a null match score', () {
    final application = HouseholdApplication.fromJson({
      'id': 12,
      'worker': 8,
      'worker_username': 'worker2',
      'status': 'pending',
    });

    expect(application.workerMatchScore, isNull);
    expect(application.workerCompletedJobs, 0);
  });

  test('recommended workers parse the AI score and its breakdown', () {
    final worker = RecommendedWorker.fromJson({
      'worker_id': 7,
      'worker_username': 'worker1',
      'worker_name': 'Maria Santos',
      'worker_location_label': 'Poblacion',
      'worker_bio': 'Reliable cleaner.',
      'worker_profile_photo_url': 'http://example.test/photo.png',
      'worker_rating_count': 3,
      'worker_completed_jobs': 5,
      'ai_score': 0.76,
      'skill_contribution': 0.6,
      'proximity_contribution': 0.2,
      'exact_skill_match': true,
    });

    expect(worker.displayName, 'Maria Santos');
    expect(worker.aiScore, 0.76);
    expect(worker.completedJobs, 5);
    expect(worker.exactSkillMatch, isTrue);
    // 0.6 of a 0.8 total, rounded to a whole percent.
    expect(worker.skillSharePercent, 75);
  });

  test('displayName falls back to the username and an unexplained '
      'match reports no skill share', () {
    final worker = RecommendedWorker.fromJson({
      'worker_id': 9,
      'worker_username': 'worker9',
      'worker_name': '',
    });

    expect(worker.displayName, 'worker9');
    expect(worker.skillSharePercent, isNull);
  });

  test('job history prefers the confirmed completion date', () {
    final entry = WorkerJobHistoryEntry.fromJson({
      'id': 7,
      'title': 'Kitchen Deep Clean',
      'job_type': 'House Cleaning',
      'household_name': 'household1',
      'completed_at': '2026-09-14T14:19:51+08:00',
      'job_start_date': '2026-09-20',
      'job_end_date': '2026-09-21',
    });

    expect(entry.title, 'Kitchen Deep Clean');
    expect(entry.householdName, 'household1');
    expect(entry.periodLabel, 'Completed 2026-09-14');
  });

  test('job history falls back to the scheduled period, then to nothing', () {
    final scheduled = WorkerJobHistoryEntry.fromJson({
      'id': 8,
      'title': 'Garden Maintenance',
      'job_start_date': '2026-08-01',
      'job_end_date': '2026-08-03',
    });
    expect(scheduled.periodLabel, '2026-08-01 to 2026-08-03');

    final undated = WorkerJobHistoryEntry.fromJson({
      'id': 9,
      'title': 'Grocery Errand Run',
    });
    expect(undated.periodLabel, '');
  });

  test('employment history entries carry the skill ratings received', () {
    final entry = WorkerJobHistoryEntry.fromJson({
      'id': 3,
      'title': 'Laundry',
      'skill_ratings': [
        {'skill_name': 'Laundry', 'rating': 4.5},
        {'skill_name': '', 'rating': 3},
      ],
    });
    final unrated = WorkerJobHistoryEntry.fromJson({
      'id': 4,
      'title': 'Cooking',
    });

    expect(entry.skillRatings, hasLength(1));
    expect(entry.skillRatings.single.skillName, 'Laundry');
    expect(entry.skillRatings.single.rating, 4.5);
    expect(unrated.skillRatings, isEmpty);
  });
}
