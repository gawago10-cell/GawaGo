import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

bool get shouldLoadMapTiles =>
    !WidgetsBinding.instance.runtimeType.toString().contains('Test');

TileLayer osmTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.gawago.gawago_mobile',
);
