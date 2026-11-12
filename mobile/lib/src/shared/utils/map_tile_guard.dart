import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

bool get shouldLoadMapTiles =>
    !WidgetsBinding.instance.runtimeType.toString().contains('Test');

TileLayer osmTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.gawago.gawago_mobile',
);

/// The credit OpenStreetMap requires wherever its tiles show. Last in a
/// map's children so no pin covers it, inset from the rounded corners, and
/// bottom-left like the web's.
Widget osmAttribution() => const Align(
  alignment: Alignment.bottomLeft,
  child: Padding(
    padding: EdgeInsets.all(8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xD9FFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(fontSize: 10, color: Color(0xFF3A3A3A)),
        ),
      ),
    ),
  ),
);
