import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/gawago_colors.dart';
import '../utils/map_tile_guard.dart';

class LocationRouteMap extends StatelessWidget {
  const LocationRouteMap({
    super.key,
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
    this.routePoints = const [],
    this.roadDistanceKm,
    this.showMapTiles = true,
    this.embedded = false,
    this.startLocationLabel = '',
    this.endLocationLabel = '',
  });

  final LatLng? start;
  final LatLng? end;
  final String startLabel;
  final String endLabel;
  final List<LatLng> routePoints;
  final double? roadDistanceKm;
  final bool showMapTiles;

  /// Drops the Card wrapper and the "km away" header line so the map can sit
  /// inside a section that already shows the distance in its own header.
  final bool embedded;

  /// Place names used when there is no drivable route to draw, so the notice
  /// can say which two places could not be connected.
  final String startLocationLabel;
  final String endLocationLabel;

  @override
  Widget build(BuildContext context) {
    final endpoints = [start, end].whereType<LatLng>().toList();
    final routeAvailable = routePoints.length >= 2;
    final mapCoordinates = routeAvailable ? routePoints : endpoints;

    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mapCoordinates.isEmpty)
            const _CoordinatesUnavailablePanel()
          else
            SizedBox(
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildMap(mapCoordinates, routeAvailable),
              ),
            ),
          if (!routeAvailable) ...[
            const SizedBox(height: 12),
            _RouteUnavailableNotice(
              startLocationLabel: startLocationLabel,
              endLocationLabel: endLocationLabel,
            ),
          ],
        ],
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  routeAvailable ? Icons.route : Icons.info_outline,
                  color: routeAvailable ? GawaGoColors.primary : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    routeAvailable && roadDistanceKm != null
                        ? '${roadDistanceKm!.toStringAsFixed(2)} km away by road'
                        : 'Road distance unavailable',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (mapCoordinates.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 175,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildMap(mapCoordinates, routeAvailable),
                ),
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text('Location details'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    routeAvailable
                        ? 'The line follows the available road route.'
                        : endpoints.length == 2
                        ? 'Both registered locations are shown. No road route line is available.'
                        : 'Both registered coordinates are required to display the location comparison.',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _coordinateRow(startLabel, start),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _coordinateRow(endLabel, end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(List<LatLng> mapCoordinates, bool routeAvailable) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: mapCoordinates.first,
        initialZoom: 13,
        initialCameraFit: mapCoordinates.length >= 2
            ? CameraFit.coordinates(
                coordinates: mapCoordinates,
                padding: const EdgeInsets.all(32),
              )
            : null,
      ),
      children: [
        if (showMapTiles && shouldLoadMapTiles) osmTileLayer(),
        if (routeAvailable)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: GawaGoColors.primary,
                strokeWidth: 5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (start != null)
              _marker(
                point: start!,
                label: startLabel,
                color: Colors.blue,
                icon: Icons.person_pin_circle,
              ),
            if (end != null)
              _marker(
                point: end!,
                label: endLabel,
                color: Colors.deepOrange,
                icon: Icons.location_on,
              ),
          ],
        ),
      ],
    );
  }

  static Marker _marker({
    required LatLng point,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Marker(
      width: 90,
      height: 58,
      point: point,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3),
              ],
            ),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          Icon(icon, color: color, size: 34),
        ],
      ),
    );
  }

  static Widget _coordinateRow(String label, LatLng? point) {
    return Text(
      point == null
          ? '$label coordinates: Not registered'
          : '$label coordinates: '
                '${point.latitude.toStringAsFixed(6)}, '
                '${point.longitude.toStringAsFixed(6)}',
      style: const TextStyle(fontSize: 12),
    );
  }
}

/// Shown instead of the map when neither side has registered coordinates --
/// a flat panel keeps the card's shape rather than collapsing it.
class _CoordinatesUnavailablePanel extends StatelessWidget {
  const _CoordinatesUnavailablePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF1F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_pin,
            size: 30,
            color: Colors.black.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 8),
          Text(
            'Location coordinates unavailable.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.45),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// The routing provider could not connect the two points. Distinct from
/// missing coordinates: both places are known, there is just no road line.
class _RouteUnavailableNotice extends StatelessWidget {
  const _RouteUnavailableNotice({
    required this.startLocationLabel,
    required this.endLocationLabel,
  });

  final String startLocationLabel;
  final String endLocationLabel;

  @override
  Widget build(BuildContext context) {
    final from = startLocationLabel.trim();
    final to = endLocationLabel.trim();
    final detail = from.isEmpty || to.isEmpty
        ? 'No road route could be calculated between the two locations.'
        : 'No road route available: $from to $to';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EEE6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Driving route unavailable',
            style: TextStyle(
              color: GawaGoColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: const TextStyle(
              color: GawaGoColors.textMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
