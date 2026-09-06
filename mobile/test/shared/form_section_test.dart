import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/form_section.dart';

void main() {
  testWidgets('presents long-form content as a numbered section', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FormSection(
            number: 2,
            title: 'Schedule and budget',
            subtitle: 'Set when the work happens and what you will pay.',
            child: Text('Form fields'),
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text('Schedule and budget'), findsOneWidget);
    expect(
      find.text('Set when the work happens and what you will pay.'),
      findsOneWidget,
    );
    expect(find.text('Form fields'), findsOneWidget);
  });
}
