import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/otp_code_field.dart';

void main() {
  testWidgets('renders one box per digit of the requested length', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OtpCodeField(length: 6, onChanged: (_) {})),
      ),
    );

    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('typing into a box advances focus to the next one', (
    tester,
  ) async {
    String latest = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpCodeField(length: 4, onChanged: (value) => latest = value),
        ),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1');
    await tester.pump();
    await tester.enterText(fields.at(1), '2');
    await tester.pump();

    expect(latest, '12');
  });

  testWidgets('reports the complete code once every box is filled', (
    tester,
  ) async {
    String? completed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpCodeField(
            length: 3,
            onChanged: (_) {},
            onCompleted: (value) => completed = value,
          ),
        ),
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '7');
    await tester.pump();
    await tester.enterText(fields.at(1), '8');
    await tester.pump();
    expect(completed, isNull);
    await tester.enterText(fields.at(2), '9');
    await tester.pump();

    expect(completed, '789');
  });

  testWidgets('a pasted multi-digit value fills the following boxes', (
    tester,
  ) async {
    String latest = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpCodeField(length: 4, onChanged: (value) => latest = value),
        ),
      ),
    );

    // Simulates an autofill/paste landing several digits in the first box.
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pump();

    expect(latest, '1234');
  });
}
