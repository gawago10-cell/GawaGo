// Mobile admin audit (2026-11-22): the report's date pickers allow no future
// days and keep From on or before To, and dates read "Nov 23, 2026".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/reports/data/report_models.dart';
import 'package:gawago_mobile/src/features/reports/data/report_repository.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';
import 'package:gawago_mobile/src/shared/widgets/report_view.dart';

class _FakeReports extends ReportRepository {
  _FakeReports();

  final requests = <(String?, String?)>[];

  @override
  Future<ActivityReport> getPlatformReport({String? start, String? end}) async {
    requests.add((start, end));
    return ActivityReport.fromJson({
      'scope': 'platform',
      'title': 'Platform activity report',
      'period': {'start': start ?? '2026-05-26', 'end': end ?? '2026-11-22'},
      'summary': <String, dynamic>{},
      'sections': <dynamic>[],
    });
  }
}

String _iso(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

void main() {
  testWidgets('the period and picked dates read as dates', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportView(repository: _FakeReports())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('May 26, 2026 to Nov 22, 2026'), findsOneWidget);
  });

  testWidgets('no future days, and To starts at From', (tester) async {
    final reports = _FakeReports();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportView(repository: reports)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('From'));
    await tester.pumpAndSettle();
    final fromPicker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(fromPicker.lastDate, today);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text(formatJobDate(_iso(today))), findsWidgets);
    expect(reports.requests.last.$1, _iso(today));

    await tester.tap(find.text('To'));
    await tester.pumpAndSettle();
    final toPicker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(toPicker.firstDate, today);
    expect(toPicker.lastDate, today);
  });
}
