import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/errors/api_error.dart';
import 'package:gawago_mobile/src/features/worker/data/worker_models.dart';
import 'package:gawago_mobile/src/shared/widgets/ai_match_breakdown.dart';
import 'package:gawago_mobile/src/shared/widgets/profile_section.dart';
import 'package:gawago_mobile/src/shared/widgets/rate_review_dialog.dart';
import 'package:gawago_mobile/src/shared/widgets/report_issue_dialog.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('report evidence', () {
    const fiveMb = 5 * 1024 * 1024;

    test('refuses a photo over the backend limit and says which one', () {
      final result = mergeEvidence(
        existing: const [],
        picked: const [
          PickedEvidence(path: '/a.jpg', name: 'a.jpg', bytes: 1000),
          PickedEvidence(path: '/big.jpg', name: 'big.jpg', bytes: fiveMb + 1),
        ],
        maxCount: 5,
        maxBytes: fiveMb,
      );

      expect(result.paths, ['/a.jpg']);
      expect(result.message, 'big.jpg: exceeds 5 MB and was not added.');
    });

    test('keeps at most five photos and says the rest were left out', () {
      final result = mergeEvidence(
        existing: const ['/1.jpg', '/2.jpg', '/3.jpg', '/4.jpg'],
        picked: const [
          PickedEvidence(path: '/5.jpg', name: '5.jpg', bytes: 10),
          PickedEvidence(path: '/6.jpg', name: '6.jpg', bytes: 10),
        ],
        maxCount: 5,
        maxBytes: fiveMb,
      );

      expect(result.paths, ['/1.jpg', '/2.jpg', '/3.jpg', '/4.jpg', '/5.jpg']);
      expect(result.message, contains('only the first 5 were kept'));
    });

    test('picking the same photo twice does not count it twice', () {
      final result = mergeEvidence(
        existing: const ['/a.jpg'],
        picked: const [
          PickedEvidence(path: '/a.jpg', name: 'a.jpg', bytes: 10),
        ],
        maxCount: 5,
        maxBytes: fiveMb,
      );

      expect(result.paths, ['/a.jpg']);
      expect(result.message, isNull);
    });
  });

  group('portfolio skills', () {
    test('a skill the worker never gave a level reads as no level', () {
      final unset = PortfolioSkill.fromJson({
        'id': 1,
        'skill_name': 'Laundry',
        'proficiency': '',
      });
      final missing = PortfolioSkill.fromJson({
        'id': 2,
        'skill_name': 'Cooking',
      });

      expect(unset.proficiencyLabel, '');
      // An older payload without the field keeps the model default.
      expect(missing.proficiencyLabel, 'Beginner');
    });

    testWidgets('the skill tile shows no level pill when none is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ProfileSkillTile(
            skillName: 'Laundry',
            proficiencyLabel: '',
            averageRating: null,
            ratingCount: 0,
          ),
        ),
      );

      expect(find.text('Laundry'), findsOneWidget);
      expect(find.text('Beginner'), findsNothing);
      expect(find.byType(SoftGreenPill), findsNothing);
    });
  });

  group('certificate files', () {
    test('the file type comes from the backend, not the URL', () {
      final image = WorkerCertificate.fromJson({
        'id': 1,
        'certificate_file_url':
            'http://host/api/accounts/portfolio/certifications/1/file/',
        'certificate_file_type': 'image',
      });
      final pdf = WorkerCertificate.fromJson({
        'id': 2,
        'certificate_file_url':
            'http://host/api/accounts/portfolio/certifications/2/file/',
        'certificate_file_type': 'pdf',
      });

      expect(image.isImage, isTrue);
      expect(image.isPdf, isFalse);
      expect(pdf.isImage, isFalse);
      expect(pdf.isPdf, isTrue);
    });
  });

  group('AI match breakdown edges', () {
    testWidgets('a partial fit far away, points adding up to the match', (
      tester,
    ) async {
      // 0.7 x 0.62 = 0.434 and 0.3 x 1/(1+2.4) = 0.088: a 52% match whose
      // parts round to 43 and 9.
      await tester.pumpWidget(
        _host(
          const AiMatchBreakdown(
            skillContribution: 0.434,
            proximityContribution: 0.0882,
            skillSimilarity: 0.62,
            distanceKm: 2.4,
            exactSkillMatch: false,
          ),
        ),
      );
      expect(
        find.text('Why this match: 62% skill fit, 2.4 km away'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '52% match: 43 points from skill fit, 9 from distance',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no distance leaves the distance out', (tester) async {
      await tester.pumpWidget(
        _host(
          const AiMatchBreakdown(
            skillContribution: 0.7,
            proximityContribution: 0,
            skillSimilarity: 1,
            distanceKm: null,
            exactSkillMatch: false,
          ),
        ),
      );
      expect(find.text('Why this match: 100% skill fit'), findsOneWidget);
    });
  });

  group('rate & review dialog', () {
    Future<void> open(WidgetTester tester, RateReviewSubmit onSubmit) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showRateReviewDialog(
                  context: context,
                  workerName: 'Maria',
                  workerInitial: 'M',
                  workerVerified: true,
                  onSubmit: onSubmit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a refused review shows the backend reason', (tester) async {
      await open(tester, ({
        required rating,
        required feedback,
        qualityOfWork,
        punctuality,
        communication,
        professionalism,
      }) async {
        throw const ApiException(
          'This user has already been reviewed for this completed job.',
          statusCode: 400,
          type: ApiErrorType.validation,
        );
      });

      // A review needs a star first; none is preset any more.
      await tester.tap(find.byIcon(Icons.star_border_rounded).first);
      await tester.pump();
      await tester.ensureVisible(find.text('Submit Rating'));
      await tester.tap(find.text('Submit Rating'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This user has already been reviewed for this completed job.',
        ),
        findsOneWidget,
      );
    });
  });
}
