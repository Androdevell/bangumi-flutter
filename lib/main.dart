import 'package:flutter/material.dart';

import 'app/bootstrap/app_bootstrap.dart';
import 'core/diagnostics/network_timing.dart';
import 'app/app_links.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'core/diagnostics/image_diagnostics.dart';

void main(List<String> arguments) {
  final watch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows && ImageDiagnostics.instance.enabled) {
    unawaited(_openImageDiagnostics());
  }
  AppLinkDispatcher.initialize(arguments);
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => NetworkTiming.record('first-frame', watch),
  );
  runApp(const AppBootstrap());
}

Future<void> _openImageDiagnostics() async {
  try {
    final root = await getApplicationSupportDirectory();
    await ImageDiagnostics.instance.open(
      File('${root.path}/diagnostics/images.jsonl'),
    );
  } catch (_) {
    // 显式诊断构建的日志不可用不阻断启动。
  }
}
