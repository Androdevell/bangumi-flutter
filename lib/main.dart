import 'package:flutter/material.dart';

import 'app/bootstrap/app_bootstrap.dart';
import 'core/diagnostics/network_timing.dart';

void main() {
  final watch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => NetworkTiming.record('first-frame', watch),
  );
  runApp(const AppBootstrap());
}
