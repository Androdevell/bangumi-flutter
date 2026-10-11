import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/diagnostics/network_timing.dart';
import '../app_theme.dart';
import '../bangumi_app.dart';
import 'app_dependencies.dart';

/// 先显示启动壳；依赖与会话恢复成功后才挂载业务页面。
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<AppDependencies> _future = _initialize();
  bool _closed = false;
  Future<AppDependencies> _initialize() async {
    final watch = Stopwatch()..start();
    final result = await AppDependencies.initialize();
    NetworkTiming.record('bootstrap', watch);
    if (_closed) unawaited(result.close());
    return result;
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDependencies>(
    future: _future,
    builder: (context, snapshot) {
      final dependencies = snapshot.data;
      if (dependencies != null) {
        return BangumiApp(
          dependencies: dependencies,
          authService: dependencies.auth,
          preferences: dependencies.preferences,
          initialLocale: dependencies.settings.locale,
          initialAppIconStyle: dependencies.settings.iconStyle,
          initialReduceMotion: dependencies.settings.reduceMotion,
          repository: dependencies.repository,
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bangumi',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 24),
                      if (snapshot.hasError) ...[
                        Text(
                          AppLocalizations.of(
                            context,
                          ).t('initializationFailed'),
                        ),
                        TextButton(
                          onPressed:
                              () => setState(() => _future = _initialize()),
                          child: Text(AppLocalizations.of(context).t('retry')),
                        ),
                      ] else
                        const CircularProgressIndicator(),
                    ],
                  ),
                ),
              ),
        ),
      );
    },
  );
}
