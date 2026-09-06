import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gawago_mobile/src/shared/widgets/location_route_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('shows both registered coordinates when road route is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationRouteMap(
              start: LatLng(14.010000, 121.580000),
              end: LatLng(14.025300, 121.592900),
              startLabel: 'Worker',
              endLabel: 'Job',
              showMapTiles: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Road distance unavailable'), findsOneWidget);
    expect(find.text('Location details'), findsOneWidget);
    expect(
      find.text(
        'Both registered locations are shown. No road route line is available.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Location details'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Both registered locations are shown. No road route line is available.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Worker coordinates: 14.010000, 121.580000'),
      findsOneWidget,
    );
    expect(find.text('Job coordinates: 14.025300, 121.592900'), findsOneWidget);
  });
}
