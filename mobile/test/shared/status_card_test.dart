import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/status_card.dart';

void main() {
  testWidgets('status badge formats the label and applies a status color', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: 'hire_requested', prefix: 'Application'),
        ),
      ),
    );

    expect(find.text('Application: Hire Requested'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Application: Hire Requested'));
    expect(label.style?.color, Colors.orange);
  });

  testWidgets('shows a readable status and distinct card metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusCard(
            title: 'House cleaning',
            subtitle: 'June 15 at 10:00 AM',
            icon: Icons.work_outline,
            status: 'hire_requested',
          ),
        ),
      ),
    );

    expect(find.text('House cleaning'), findsOneWidget);
    expect(find.text('Hire Requested'), findsOneWidget);
    expect(find.byIcon(Icons.work_outline), findsOneWidget);
    expect(find.text('June 15 at 10:00 AM'), findsOneWidget);
  });
}
