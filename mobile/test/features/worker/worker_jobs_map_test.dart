import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';
import 'package:gawago_mobile/src/features/worker/presentation/worker_jobs_map.dart';

WorkerJob _job(
  int id,
  String title,
  String household,
  double? lat,
  double? lng, {
  String blockedReason = '',
}) {
  return WorkerJob.fromJson({
    'id': id,
    'title': title,
    'household_username': household.toLowerCase().replaceAll(' ', '_'),
    'household_name': household,
    'household_verification_status': 'verified',
    'job_type': 'House Cleaning',
    'required_skill': 'House Cleaning',
    'location_label': 'Poblacion, Tayabas City',
    'service_rate': '700.00',
    'rate_type_label': 'Per Day',
    'status': 'open',
    'can_apply': blockedReason.isEmpty,
    'apply_blocked_reason': blockedReason,
    'latitude': null,
    'longitude': null,
    'approximate_latitude': lat,
    'approximate_longitude': lng,
  });
}

void main() {
  test('jobs keep only the approximate map area, not the exact site', () {
    final job = _job(1, 'Aircon Cleaning', 'Mila Reyes', 14.03, 121.59);

    expect(job.latitude, isNull);
    expect(job.approximateLatitude, 14.03);
    expect(job.approximateLongitude, 121.59);
  });

  test('jobs in the same ~1 km cell share one map area', () {
    final grouped = groupJobsByMapArea([
      _job(1, 'Aircon Cleaning', 'Mila Reyes', 14.03, 121.59),
      _job(2, 'Garden Cleanup', 'Mila Reyes', 14.03, 121.59),
      _job(3, 'Repairman', 'Household One', 13.94, 121.59),
      _job(4, 'No pin yet', 'Liza Tan', null, null),
    ]);

    expect(grouped.areas, hasLength(2));
    expect(grouped.areas.first.jobs.map((job) => job.title), [
      'Aircon Cleaning',
      'Garden Cleanup',
    ]);
    expect(grouped.unmapped.single.title, 'No pin yet');
  });

  testWidgets('tapping a far, non-matching pin still opens its jobs', (
    tester,
  ) async {
    WorkerJob? viewed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: WorkerJobsMap(
              jobs: [
                _job(1, 'Aircon Cleaning', 'Mila Reyes', 14.03, 121.59),
                _job(2, 'Garden Cleanup', 'Mila Reyes', 14.03, 121.59),
                _job(3, 'Repairman', 'Household One', 14.0, 121.57),
              ],
              matchesSkills: (job) => job.id != 3,
              distanceLabel: (_) => '5.1 km away',
              onViewDetails: (job) => viewed = job,
              onApply: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('HO'));
    await tester.pumpAndSettle();

    expect(find.text('1 job in this area'), findsOneWidget);
    expect(find.text('Repairman'), findsOneWidget);
    expect(find.text('Other Job'), findsOneWidget);

    await tester.tap(find.text('View Details'));
    expect(viewed?.title, 'Repairman');

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(find.text('2 jobs in this area'), findsOneWidget);
    expect(find.text('Aircon Cleaning'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Garden Cleanup'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Garden Cleanup'), findsOneWidget);
  });

  testWidgets('a worker on a full-time job sees why they cannot apply', (
    tester,
  ) async {
    const reason =
        "You're on a full-time job (Yaya) until Mila Reyes marks it done. "
        'You can apply to other jobs after that.';
    final job = _job(
      5,
      'Garden Cleanup',
      'Liza Tan',
      14.03,
      121.59,
      blockedReason: reason,
    );
    expect(job.canApply, isFalse);
    expect(job.applyBlockedReason, reason);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: WorkerJobsMap(
              jobs: [job],
              matchesSkills: (_) => true,
              distanceLabel: (_) => '1.2 km away',
              onViewDetails: (_) {},
              onApply: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('LT'));
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Apply Now'), findsNothing);
    expect(
      find.text('On a full-time job. $reason', findRichText: true),
      findsOneWidget,
    );
  });
}
