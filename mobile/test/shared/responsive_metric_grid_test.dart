import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/responsive_metric_grid.dart';

void main() {
  Widget testApp(double width) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const ResponsiveMetricGrid(
              children: [
                SizedBox(key: Key('first'), height: 60),
                SizedBox(key: Key('second'), height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('uses two columns on a normal phone width', (tester) async {
    await tester.pumpWidget(testApp(400));

    final first = tester.getTopLeft(find.byKey(const Key('first')));
    final second = tester.getTopLeft(find.byKey(const Key('second')));

    expect(second.dx, greaterThan(first.dx));
    expect(second.dy, first.dy);
  });

  testWidgets('uses one column on a very narrow screen', (tester) async {
    await tester.pumpWidget(testApp(300));

    final first = tester.getTopLeft(find.byKey(const Key('first')));
    final second = tester.getTopLeft(find.byKey(const Key('second')));

    expect(second.dx, first.dx);
    expect(second.dy, greaterThan(first.dy));
  });
}
