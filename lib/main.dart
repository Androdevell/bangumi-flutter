import 'package:flutter/material.dart';

import 'app/bangumi_app.dart';
import 'app/bootstrap/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.initialize();
  runApp(
    BangumiApp(
      dependencies: dependencies,
      authService: dependencies.auth,
      preferences: dependencies.preferences,
      initialLocale: dependencies.settings.locale,
      initialAppIconStyle: dependencies.settings.iconStyle,
      repository: dependencies.repository,
    ),
  );
}
