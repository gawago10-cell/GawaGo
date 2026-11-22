import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/rate_review_dialog.dart';

void main() {
  testWidgets('a review starts with no stars and needs one to submit', (
    tester,
  ) async {
    double? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRateReviewDialog(
              context: context,
              workerName: 'Worker One',
              workerInitial: 'W',
              workerVerified: true,
              onSubmit:
                  ({
                    required double rating,
                    required String feedback,
                    int? qualityOfWork,
                    int? punctuality,
                    int? communication,
                    int? professionalism,
                  }) async {
                    submitted = rating;
                  },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Tap a star'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Submit Rating');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.byIcon(Icons.star_border_rounded).at(3));
    await tester.pump();
    expect(find.text('4/5'), findsOneWidget);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(submitted, 4);
  });

  // 4, 5, 4 and 4 average 4.25; the API keeps one decimal and refused it,
  // so the review could not be sent (mobile household audit, 2026-11-23).
  testWidgets('the metric average is rounded, shown and sent', (tester) async {
    double? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRateReviewDialog(
              context: context,
              workerName: 'Worker One',
              workerInitial: 'W',
              workerVerified: true,
              onSubmit:
                  ({
                    required double rating,
                    required String feedback,
                    int? qualityOfWork,
                    int? punctuality,
                    int? communication,
                    int? professionalism,
                  }) async {
                    submitted = rating;
                  },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final tip in [
      'Quality of Work: 4',
      'Punctuality: 5',
      'Communication: 4',
      'Professionalism: 4',
    ]) {
      final star = find.byTooltip(tip);
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();
    }

    expect(find.text('4.3/5 · average of the metrics below'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Submit Rating');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(submitted, 4.3);
  });
}
