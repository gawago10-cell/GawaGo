import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/household/data/household_models.dart';

void main() {
  // The API sends an applicant's location whatever their status now, so null
  // coordinates mean the worker never pinned a location on their profile --
  // the model still has to fall back to distance-only for that case.
  test('an applicant with no pinned location parses to distance only', () {
    final application = HouseholdApplication.fromJson({
      'id': 1,
      'worker': 2,
      'worker_username': 'maria',
      'status': 'pending',
      'route_distance_km': 2.3,
      'distance_label': '2.3 km away',
      'worker_latitude': null,
      'worker_longitude': null,
      'route_points': [],
    });

    expect(application.workerLatitude, isNull);
    expect(application.workerLongitude, isNull);
    expect(application.routePoints, isEmpty);
    expect(application.distanceKm, 2.3);
    expect(application.distanceLabel, '2.3 km away');
  });

  test('a pending applicant keeps its coordinates and route', () {
    final application = HouseholdApplication.fromJson({
      'id': 1,
      'worker': 2,
      'status': 'pending',
      'worker_latitude': 13.98,
      'worker_longitude': 121.58,
      'route_points': [
        [13.96, 121.56],
        [13.98, 121.58],
      ],
    });

    expect(application.workerLatitude, 13.98);
    expect(application.routePoints, hasLength(2));
  });

  test('recommended worker parses with no coordinate fields at all', () {
    final worker = RecommendedWorker.fromJson({
      'worker_id': 2,
      'worker_username': 'maria',
      'distance_km': 0.4,
      'distance_label': 'Within 1 km',
      'ai_score': 0.87,
    });

    expect(worker.distanceLabel, 'Within 1 km');
    expect(worker.distanceKm, 0.4);
  });
}
