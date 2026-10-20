import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/household/data/household_models.dart';
import 'package:gawago_mobile/src/features/household/presentation/household_workers_map.dart';

RecommendedWorker _worker(
  int id,
  String name,
  double? lat,
  double? lng, {
  bool matches = true,
  List<String> skills = const ['House Cleaning'],
}) {
  return RecommendedWorker.fromJson({
    'worker_id': id,
    'worker_username': name.toLowerCase().replaceAll(' ', '_'),
    'worker_name': name,
    'worker_location_label': 'Poblacion, Tayabas City',
    'worker_approximate_latitude': lat,
    'worker_approximate_longitude': lng,
    'worker_bio': '',
    'worker_profile_photo_url': '',
    'worker_rating_count': 4,
    'worker_completed_jobs': 2,
    'skills': skills,
    'matches_skill': matches,
    'verification_status': 'verified',
    'distance_label': '2.3 km away',
    'distance_km': 2.3,
    'match_score': 0.8,
    'rating_label': '4.5',
    'worker_rate': '500.00',
    'ai_score': 0.8,
    'skill_contribution': 0.6,
    'proximity_contribution': 0.2,
    'exact_skill_match': matches,
  });
}

void main() {
  test('candidates keep only the approximate map area, not their home', () {
    final worker = _worker(1, 'Ava Lopez', 14.03, 121.59);

    expect(worker.approximateLatitude, 14.03);
    expect(worker.approximateLongitude, 121.59);
    // The exact point is only released once the worker is hired, so the
    // recommendation payload has no field carrying it at all.
    expect(worker.distanceLabel, '2.3 km away');
  });

  test('workers in the same ~1 km cell share one map area', () {
    final grouped = groupWorkersByMapArea([
      _worker(1, 'Ava Lopez', 14.03, 121.59),
      _worker(2, 'Ben Cruz', 14.03, 121.59),
      _worker(3, 'Cara Diaz', 13.94, 121.59),
      _worker(4, 'No Pin Yet', null, null),
    ]);

    expect(grouped.areas, hasLength(2));
    expect(grouped.areas.first.workers.map((worker) => worker.name), [
      'Ava Lopez',
      'Ben Cruz',
    ]);
    expect(grouped.unmapped.single.name, 'No Pin Yet');
  });

  testWidgets('tapping a pin opens the workers available in that area', (
    tester,
  ) async {
    RecommendedWorker? viewed;
    RecommendedWorker? hired;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: HouseholdWorkersMap(
              workers: [
                _worker(1, 'Ava Lopez', 14.03, 121.59),
                _worker(2, 'Ben Cruz', 14.03, 121.59),
                _worker(
                  3,
                  'Cara Diaz',
                  14.0,
                  121.57,
                  matches: false,
                  skills: const ['Plumbing'],
                ),
              ],
              jobLatitude: 14.02,
              jobLongitude: 121.59,
              onViewProfile: (worker) => viewed = worker,
              onHire: (worker) => hired = worker,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The lone non-matching candidate is pinned by their initials.
    await tester.tap(find.text('CD'));
    await tester.pumpAndSettle();

    expect(find.text('1 worker in this area'), findsOneWidget);
    expect(find.text('Cara Diaz'), findsOneWidget);
    expect(find.text('Other Worker'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);

    await tester.tap(find.text('View Profile'));
    expect(viewed?.name, 'Cara Diaz');
    await tester.tap(find.text('Send Request'));
    expect(hired?.name, 'Cara Diaz');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // The two candidates sharing a cell collapse into one counted pin.
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(find.text('2 workers in this area'), findsOneWidget);
    expect(find.text('Ava Lopez'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ben Cruz'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Ben Cruz'), findsOneWidget);
  });

  testWidgets('the legend says pins are approximate and where exact goes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: HouseholdWorkersMap(
              workers: [_worker(1, 'Ava Lopez', 14.03, 121.59)],
              jobLatitude: 14.02,
              jobLongitude: 121.59,
              onViewProfile: (_) {},
              onHire: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('about 1 km'), findsOneWidget);
    // The legend must point at where the exact location actually is now --
    // the applicant card -- not tell the household to hire first.
    expect(find.textContaining('exact location and route'), findsOneWidget);
    expect(find.textContaining('hire'), findsNothing);
    expect(find.text('Your job site'), findsOneWidget);
  });
}
