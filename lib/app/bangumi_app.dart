import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../core/diagnostics/refresh_rate_probe.dart';
import '../data/bangumi_repository.dart';
import '../features/shell/app_shell.dart';
import 'app_theme.dart';

class BangumiApp extends StatefulWidget {
  const BangumiApp({super.key, this.repository, this.authService});

  final BangumiRepository? repository;
  final AuthService? authService;

  @override
  State<BangumiApp> createState() => _BangumiAppState();
}

class _BangumiAppState extends State<BangumiApp> {
  ThemeMode _themeMode = ThemeMode.system;
  late final BangumiRepository _repository =
      widget.repository ?? RemoteBangumiRepository();

  @override
  void dispose() {
    if (widget.repository == null) _repository.close();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.system || ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.light,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bangumi',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        if (!RefreshRateProbe.enabled) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const RefreshRateProbe(),
          ],
        );
      },
      home: AppShell(
        repository: _repository,
        authService: widget.authService,
        themeMode: _themeMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}
