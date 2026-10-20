import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/core/errors/api_error.dart';
import 'package:gawago_mobile/src/shared/widgets/async_state.dart';

void main() {
  testWidgets('network error displays an offline state and retries', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppErrorState(
            error: const ApiException(
              'socket failed',
              type: ApiErrorType.network,
            ),
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.textContaining('appear to be offline'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('empty state renders its supplied message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppEmptyState(message: 'No jobs available.')),
      ),
    );

    expect(find.text('No jobs available.'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}
