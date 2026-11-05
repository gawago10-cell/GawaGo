import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';
import 'package:gawago_mobile/src/shared/widgets/portfolio_pieces.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('household rating parses from the history payload', () {
    final rating = JobHouseholdRating.fromJson({
      'rating': 4.5,
      'is_default': false,
      'metrics': [
        {'label': 'Punctuality', 'value': 4},
      ],
    });
    expect(rating!.rating, 4.5);
    expect(rating.isDefault, isFalse);
    expect(rating.metrics.single.key, 'Punctuality');
    expect(JobHouseholdRating.fromJson(null), isNull);
  });

  testWidgets(
    'the household rating is the overall, never "not rated" when rated',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const EmploymentHistoryCard(
            title: 'Laundry and Ironing',
            householdName: 'Household One',
            locationLabel: 'Alitao',
            completedAt: '2026-11-04T13:00:00Z',
            skillRatings: [],
            householdRating: JobHouseholdRating(
              rating: 5,
              isDefault: false,
              metrics: [MapEntry('Punctuality', 5)],
            ),
          ),
        ),
      );
      expect(find.text('5.0'), findsOneWidget);
      expect(find.text('Punctuality'), findsOneWidget);
      expect(find.textContaining('Not rated'), findsNothing);
    },
  );

  testWidgets('skill ratings become the bars', (tester) async {
    await tester.pumpWidget(
      _host(
        const EmploymentHistoryCard(
          title: 'asasd',
          householdName: 'Elsalyn Barlan',
          locationLabel: 'Anos',
          completedAt: '',
          skillRatings: [
            JobSkillRating(skillName: 'Cooking', rating: 5),
            JobSkillRating(skillName: 'Laundry', rating: 4),
          ],
          householdRating: JobHouseholdRating(
            rating: 4.3,
            isDefault: false,
            metrics: [],
          ),
        ),
      ),
    );
    expect(find.text('4.3'), findsOneWidget);
    expect(find.text('Cooking'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
  });

  testWidgets('an unrated job waits for the household', (tester) async {
    await tester.pumpWidget(
      _host(
        const EmploymentHistoryCard(
          title: 'Garden Cleanup',
          householdName: '',
          locationLabel: '',
          completedAt: '',
          skillRatings: [],
          householdRating: null,
        ),
      ),
    );
    expect(find.text("Waiting for the household's rating."), findsOneWidget);
  });
}
