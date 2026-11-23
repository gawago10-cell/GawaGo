// Mobile worker audit (2026-11-23): the shared pieces behind the fixes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/utils/display_formatters.dart';
import 'package:gawago_mobile/src/shared/utils/signup_validation.dart';
import 'package:gawago_mobile/src/shared/widgets/rate_review_dialog.dart';

void main() {
  test('an average rounds half up like the backend', () {
    // 4.35 is 4.3499... as a double; the backend's Decimal gives 4.4.
    expect(averageRating([4.3, 4.4]), 4.4);
    expect(averageRating([4.3, 4.5]), 4.4);
    expect(averageRating([4.2, 4.5]), 4.4);
    expect(averageRating([3.0]), 3.0);
    expect(averageRating(const <double>[]), isNull);
    expect(formatRating(4.35), '4.4');
    expect(formatRating(4.25), '4.3');
    expect(formatRating(4.5), '4.5');
  });

  test('a rate reads the same everywhere', () {
    expect(formatJobRate(650, 'Per Day'), 'PHP 650.00 / day');
    expect(formatJobRate(120, 'Per Hour'), 'PHP 120.00 / hour');
    expect(formatJobRate(1500, 'Fixed Rate'), 'PHP 1500.00 / job');
    expect(rateUnit('per_hour'), 'hour');
    expect(rateUnit(''), 'day');
  });

  test('a rate follows the server limits', () {
    expect(rateProblem('', max: maxDailyRate), isNull);
    expect(rateProblem('0', max: maxDailyRate), isNull);
    expect(rateProblem('650', max: maxDailyRate), isNull);
    expect(
      rateProblem('abc', max: maxDailyRate),
      'Enter the rate as a number.',
    );
    expect(rateProblem('-50', max: maxHourlyRate), "A rate can't be negative.");
    expect(
      rateProblem('0.5', max: maxHourlyRate),
      'Enter at least PHP 1, or leave it blank.',
    );
    expect(
      rateProblem('99999999', max: maxDailyRate),
      'Enter PHP 100,000 or less.',
    );
    expect(
      rateProblem('10001', max: maxHourlyRate),
      'Enter PHP 10,000 or less.',
    );
  });

  testWidgets('rating a household shows the metric average it will save', (
    tester,
  ) async {
    double? sentRating;
    int? sentQuality;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRateReviewDialog(
                context: context,
                workerName: 'Gina Ramos',
                workerInitial: 'G',
                workerVerified: false,
                feedbackHint:
                    'Share details about working with this household...',
                onSubmit:
                    ({
                      required double rating,
                      required String feedback,
                      int? qualityOfWork,
                      int? punctuality,
                      int? communication,
                      int? professionalism,
                    }) async {
                      sentRating = rating;
                      sentQuality = qualityOfWork;
                    },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Share details about working with this household...'),
      findsOneWidget,
    );
    // Stars first, then one metric: the overall follows the metric, as the
    // server stores it (the worker's old dialog said 5/5 and saved 3.0).
    await tester.tap(find.byIcon(Icons.star_border_rounded).at(4));
    await tester.pump();
    expect(find.text('5/5'), findsOneWidget);
    final metricStars = find.byIcon(Icons.star_border_rounded);
    // The first metric row's third star.
    await tester.tap(metricStars.at(2));
    await tester.pump();
    expect(find.text('3.0/5 · average of the metrics below'), findsOneWidget);

    await tester.ensureVisible(find.text('Submit Rating'));
    await tester.tap(find.text('Submit Rating'));
    await tester.pumpAndSettle();
    expect(sentRating, 3.0);
    expect(sentQuality, 3);
  });
}
