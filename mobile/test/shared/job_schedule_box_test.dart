import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';
import 'package:gawago_mobile/src/shared/widgets/job_schedule_box.dart';

Future<void> _pump(WidgetTester tester, Widget box) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: box)));

void main() {
  final today = DateTime(2026, 10, 31);

  test('formatJobDay adds the day of the week', () {
    expect(formatJobDay('2026-10-30'), 'Fri, Oct 30, 2026');
    expect(formatJobDay(''), 'Not set');
  });

  testWidgets('words a job that has not started yet', (tester) async {
    await _pump(
      tester,
      JobScheduleBox(
        startDate: '2026-11-03',
        endDate: '2026-11-05',
        workingDays: 3,
        today: today,
      ),
    );
    expect(find.text('STARTS'), findsOneWidget);
    expect(find.text('Tue, Nov 3, 2026'), findsOneWidget);
    expect(find.text('ENDS'), findsOneWidget);
    expect(find.text('Thu, Nov 5, 2026'), findsOneWidget);
    expect(find.text('3 working days'), findsOneWidget);
  });

  testWidgets('words a job under way and a finished one', (tester) async {
    await _pump(
      tester,
      JobScheduleBox(
        startDate: '2026-10-30',
        endDate: '2026-11-01',
        today: today,
      ),
    );
    expect(find.text('STARTED'), findsOneWidget);
    expect(find.text('ENDS'), findsOneWidget);

    await _pump(
      tester,
      JobScheduleBox(
        startDate: '2026-10-30',
        endDate: '2026-11-01',
        finished: true,
        today: today,
      ),
    );
    expect(find.text('ENDED'), findsOneWidget);
  });

  testWidgets('a one-day job with no end date ends on its start day', (
    tester,
  ) async {
    await _pump(
      tester,
      JobScheduleBox(
        startDate: '2026-10-22',
        endDate: '',
        workingDays: 1,
        today: today,
      ),
    );
    expect(find.text('Thu, Oct 22, 2026'), findsNWidgets(2));
    expect(find.text('1 working day'), findsOneWidget);
  });

  testWidgets('shows nothing without dates', (tester) async {
    await _pump(
      tester,
      JobScheduleBox(startDate: null, endDate: '', today: today),
    );
    expect(find.text('STARTED'), findsNothing);
    expect(find.text('START'), findsNothing);
  });

  testWidgets('lists the schedule as lines for My Applications', (
    tester,
  ) async {
    await _pump(
      tester,
      JobScheduleLines(
        startDate: '2026-11-08',
        endDate: '2026-11-10',
        workingDays: 3,
        scheduleLabel: 'One-Time',
        today: today,
      ),
    );
    expect(
      find.text('Starts  Sun, Nov 8, 2026', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Ends  Tue, Nov 10, 2026', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('One-Time · 3 working days'), findsOneWidget);
  });

  testWidgets('lines show the schedule wording alone without dates', (
    tester,
  ) async {
    await _pump(
      tester,
      JobScheduleLines(
        startDate: '',
        endDate: '',
        scheduleLabel: 'Part-Time',
        today: today,
      ),
    );
    expect(find.text('Part-Time'), findsOneWidget);
    expect(find.text('Not set'), findsNothing);
  });

  testWidgets('lines say Started and Ended for a finished job', (tester) async {
    await _pump(
      tester,
      JobScheduleLines(
        startDate: '2026-10-20',
        endDate: '2026-11-02',
        finished: true,
        today: today,
      ),
    );
    expect(
      find.text('Started  Tue, Oct 20, 2026', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Ended  Mon, Nov 2, 2026', findRichText: true),
      findsOneWidget,
    );
  });
}
