import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/errors/api_error.dart';
import 'package:gawago_mobile/src/shared/widgets/rate_skills_dialog.dart';

const _skills = [
  RatableSkill(id: 11, name: 'House Cleaning'),
  RatableSkill(id: 12, name: 'Laundry'),
];

Future<bool?> _open(WidgetTester tester, RateSkillsSubmit onSubmit) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showRateSkillsDialog(
                context: context,
                workerName: 'Maria',
                skills: _skills,
                onSubmit: onSubmit,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('sends only the skills that were actually rated', (tester) async {
    Map<int, int>? sent;
    await _open(tester, (ratings) async => sent = ratings);

    await tester.tap(find.byKey(const ValueKey('skill-11-star-4')));
    await tester.pump();
    await tester.tap(find.text('Save ratings'));
    await tester.pumpAndSettle();

    expect(sent, {11: 4});
  });

  testWidgets('saving is disabled until something is rated', (tester) async {
    var called = false;
    await _open(tester, (_) async => called = true);

    await tester.tap(find.text('Save ratings'));
    await tester.pump();

    expect(called, isFalse);
    expect(find.text('RATE THEIR SKILLS'), findsOneWidget);
  });

  testWidgets('tapping the same score again clears it', (tester) async {
    Map<int, int>? sent;
    await _open(tester, (ratings) async => sent = ratings);

    await tester.tap(find.byKey(const ValueKey('skill-11-star-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('skill-11-star-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('skill-12-star-2')));
    await tester.pump();
    await tester.tap(find.text('Save ratings'));
    await tester.pumpAndSettle();

    expect(sent, {12: 2});
  });

  testWidgets('Skip closes without sending anything', (tester) async {
    var called = false;
    await _open(tester, (_) async => called = true);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('RATE THEIR SKILLS'), findsNothing);
  });

  testWidgets('a failed save stays open with a message instead of closing', (
    tester,
  ) async {
    await _open(tester, (_) async => throw Exception('boom'));

    await tester.tap(find.byKey(const ValueKey('skill-11-star-3')));
    await tester.pump();
    await tester.tap(find.text('Save ratings'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unable to save'), findsOneWidget);
    expect(find.text('RATE THEIR SKILLS'), findsOneWidget);
  });

  testWidgets('a worker with no skills is not shown an empty dialog', (
    tester,
  ) async {
    bool? shown;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              shown = await showRateSkillsDialog(
                context: context,
                workerName: 'Maria',
                skills: const [],
                onSubmit: (_) async {},
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(shown, isFalse);
    expect(find.text('RATE THEIR SKILLS'), findsNothing);
  });

  testWidgets('a refused save shows the backend reason, not a generic error', (
    tester,
  ) async {
    await _open(
      tester,
      (_) async => throw const ApiException(
        'Skills can only be rated once the job is completed.',
        statusCode: 400,
        type: ApiErrorType.validation,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('skill-11-star-4')));
    await tester.pump();
    await tester.tap(find.text('Save ratings'));
    await tester.pumpAndSettle();

    expect(
      find.text('Skills can only be rated once the job is completed.'),
      findsOneWidget,
    );
  });

  testWidgets('an unexpected failure still gets the generic message', (
    tester,
  ) async {
    await _open(tester, (_) async => throw StateError('boom'));

    await tester.tap(find.byKey(const ValueKey('skill-11-star-4')));
    await tester.pump();
    await tester.tap(find.text('Save ratings'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to save these ratings. Please try again.'),
      findsOneWidget,
    );
  });
}
