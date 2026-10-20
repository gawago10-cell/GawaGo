import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/ai_match_breakdown.dart';
import 'package:gawago_mobile/src/shared/widgets/profile_section.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('explains the match as skill fit versus proximity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AiMatchBreakdown(skillSharePercent: 70, exactSkillMatch: true),
      ),
    );

    expect(
      find.text(
        'Why this match: 70% skill fit, 30% proximity — exact skill match',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders nothing when there is no score to explain', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AiMatchBreakdown(skillSharePercent: null, exactSkillMatch: false),
      ),
    );

    expect(find.textContaining('Why this match'), findsNothing);
  });

  testWidgets('employment history chips show each skill rating', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const JobSkillRatingChips(
          ratings: [MapEntry('House Cleaning', 4.5), MapEntry('Laundry', 4.0)],
        ),
      ),
    );

    expect(find.text('House Cleaning ★ 4.5'), findsOneWidget);
    expect(find.text('Laundry ★ 4.0'), findsOneWidget);
  });

  testWidgets('no chips when the job has no skill ratings', (tester) async {
    await tester.pumpWidget(_host(const JobSkillRatingChips(ratings: [])));

    expect(find.textContaining('★'), findsNothing);
  });
}
