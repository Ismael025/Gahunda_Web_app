import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/cloud_configuration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GahundaCloudBootstrap.initialize();
  runApp(const ProviderScope(child: GahundaApp()));
}
