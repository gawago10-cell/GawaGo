import 'package:flutter/material.dart';

import 'src/app/gawago_app.dart';
import 'src/core/config/api_config.dart';

export 'src/app/gawago_app.dart' show GawaGoApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.restoreBaseUrl();
  runApp(const GawaGoApp());
}
