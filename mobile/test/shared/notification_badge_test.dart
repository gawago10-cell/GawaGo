import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/notification_badge.dart';

void main() {
  testWidgets('shows unread count and caps large values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              NotificationBadge(
                count: 4,
                child: Icon(Icons.notifications_none),
              ),
              NotificationBadge(
                count: 125,
                child: Icon(Icons.notifications_none),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('4'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('hides the badge when there are no unread items', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationBadge(
          count: 0,
          child: Icon(Icons.notifications_none),
        ),
      ),
    );

    expect(find.byType(Badge), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });
}
