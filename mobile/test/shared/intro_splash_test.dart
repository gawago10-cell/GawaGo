import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/main.dart';
import 'package:gawago_mobile/src/shared/widgets/intro_splash.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('signed-out launch plays the intro, then reveals the landing', (
    tester,
  ) async {
    await tester.pumpWidget(const GawaGoApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3000));

    expect(find.byType(IntroSplash), findsOneWidget);
    expect(find.text('TAP ANYWHERE TO SKIP'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.byType(IntroSplash), findsNothing);
    expect(find.text('Post a Job'), findsOneWidget);
  });

  testWidgets('tapping the intro skips it', (tester) async {
    await tester.pumpWidget(const GawaGoApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(IntroSplash), findsOneWidget);

    await tester.tap(find.byType(IntroSplash));
    // Only the 550 ms fade is left, not the remaining ~3.4 s. The first pump
    // is the restarted ticker's start frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.byType(IntroSplash), findsNothing);
  });

  testWidgets('reduce-motion skips the intro entirely', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(const GawaGoApp());
    await tester.pump();
    await tester.pump();
    expect(find.byType(IntroSplash), findsNothing);
  });
}
