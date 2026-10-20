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
    expect(find.text('Exact Worker Location'), findsOneWidget);
    expect(find.text('Create Worker Account'), findsOneWidget);
  });

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
