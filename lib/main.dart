import 'package:flutter/material.dart';

import 'app/bootstrap/app_bootstrap.dart';
import 'core/diagnostics/network_timing.dart';
import 'app/app_links.dart';

void main(List<String> arguments) {
  final watch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  AppLinkDispatcher.initialize(arguments);
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => NetworkTiming.record('first-frame', watch),
  );
  runApp(const AppBootstrap());
}
