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
      'worker_latitude': 14.01,
      'worker_longitude': 121.58,
      'route_points': [
        [14.01, 121.58],
        [14.0253, 121.5929],
      ],
    });

    expect(worker.verificationStatus, 'verified');
    expect(worker.matchScore, 94.5);
    expect(worker.workerLatitude, 14.01);
    expect(worker.workerLongitude, 121.58);
    expect(worker.routePoints.length, 2);
  });
}
