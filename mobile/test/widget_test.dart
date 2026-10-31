import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/main.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('GawaGo landing page renders primary content', (tester) async {
    await tester.pumpWidget(const GawaGoApp());
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Post a Job'), findsOneWidget);
    expect(find.text('Find Work'), findsOneWidget);
    expect(find.text('OPEN JOBS LIVE'), findsOneWidget);

    await tester.tap(find.text('Login').first);
    await tester.pumpAndSettle();

    expect(find.text('Login to GawaGo'), findsOneWidget);
    expect(find.text('Email or Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Server settings'), findsNothing);
  });

  testWidgets('Sign up opens role choices and registration forms', (
    tester,
  ) async {
    await tester.pumpWidget(const GawaGoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Worker'), findsOneWidget);
    expect(find.text('Create Account'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Create Account').first);
    await tester.tap(find.text('Create Account').first);
    await tester.pumpAndSettle();

    expect(find.text('Register as Household'), findsOneWidget);
    expect(find.text('Create Household Account'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create Account').last);
    await tester.tap(find.text('Create Account').last);
    await tester.pumpAndSettle();

    expect(find.text('Register as Worker'), findsOneWidget);
    // No pin yet, so the label still carries its asterisk.
    expect(find.text('Exact Worker Location\u00A0*'), findsOneWidget);
    expect(find.text('Create Worker Account'), findsOneWidget);
  });

  testWidgets(
    'sign-up asterisks leave answered fields and missing ones turn red',
    (tester) async {
      await tester.pumpWidget(const GawaGoApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find Work'));
      await tester.pumpAndSettle();

      // Every required label starts with an asterisk.
      expect(find.text('First Name\u00A0*'), findsOneWidget);
      expect(find.text('Email\u00A0*'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('signup-First Name')),
        'Louise',
      );
      await tester.pump();
      expect(find.text('First Name\u00A0*'), findsNothing);
      expect(find.text('First Name'), findsOneWidget);

      await tester.ensureVisible(find.text('Create Worker Account'));
      await tester.tap(find.text('Create Worker Account'));
      await tester.pump();

      // Each missing field says so under itself; the answered one doesn't.
      expect(find.text('Email is required.'), findsOneWidget);
      expect(find.text('Last name is required.'), findsOneWidget);
      expect(find.text('First name is required.'), findsNothing);
      expect(find.text('Choose at least one skill.'), findsWidgets);

      // Fixing a field drops its message straight away.
      await tester.enterText(
        find.byKey(const ValueKey('signup-Email')),
        'louise@gmail',
      );
      await tester.pump();
      expect(find.text('Email is required.'), findsNothing);
      expect(find.text('Email\u00A0*'), findsNothing);
    },
  );

  testWidgets('hero actions open the matching registration form', (
    tester,
  ) async {
    await tester.pumpWidget(const GawaGoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Post a Job'));
    await tester.pumpAndSettle();
    expect(find.text('Register as Household'), findsOneWidget);

    await tester.pumpWidget(const GawaGoApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find Work'));
    await tester.pumpAndSettle();
    expect(find.text('Register as Worker'), findsOneWidget);
  });
}
