import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/reports/data/report_models.dart';

void main() {
  test('parses a report envelope with its sections', () {
    final report = ActivityReport.fromJson({
      'scope': 'household',
      'title': 'Household activity report',
      'period': {'start': '2026-03-17', 'end': '2026-09-13'},
      'summary': {'jobsPosted': 9, 'averageRatingGiven': null},
      'sections': [
        {
          'title': 'Jobs by service type',
          'description': 'Which services you post most often.',
          'columns': ['Service', 'Jobs posted'],
          'rows': [
            ['House Cleaning', 5],
            ['Laundry', 4],
          ],
        },
      ],
    });

    expect(report.scope, 'household');
    expect(report.periodStart, '2026-03-17');
    expect(report.periodEnd, '2026-09-13');
    expect(report.summary['jobsPosted'], 9);
    expect(report.summary['averageRatingGiven'], isNull);
    expect(report.sections.single.columns, ['Service', 'Jobs posted']);
    expect(report.sections.single.rows.first, ['House Cleaning', '5']);
  });

  test('tolerates a report with no sections or summary', () {
    final report = ActivityReport.fromJson({'scope': 'worker'});

    expect(report.title, 'Activity report');
    expect(report.summary, isEmpty);
    expect(report.sections, isEmpty);
  });
}
