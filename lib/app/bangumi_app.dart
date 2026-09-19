import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/auth/auth_service.dart';
import '../core/diagnostics/refresh_rate_probe.dart';
import '../core/localization/app_localizations.dart';
import '../core/settings/app_icon_service.dart';
import '../core/settings/app_preferences.dart';
import '../data/bangumi_repository.dart';
import '../features/shell/app_shell.dart';
import 'app_theme.dart';

class BangumiApp extends StatefulWidget {
  const BangumiApp({
    super.key,
    this.repository,
    this.authService,
    this.preferences,
    this.initialLocale = const Locale('zh'),
    this.initialAppIconStyle = AppIconStyle.classic,
  });

  final BangumiRepository? repository;
  final AuthService? authService;
  final AppPreferences? preferences;
  final Locale initialLocale;
  final AppIconStyle initialAppIconStyle;

  @override
  State<BangumiApp> createState() => _BangumiAppState();
}

class _BangumiAppState extends State<BangumiApp> {
  ThemeMode _themeMode = ThemeMode.system;
  late Locale _locale = widget.initialLocale;
  late AppIconStyle _appIconStyle = widget.initialAppIconStyle;
  late final BangumiRepository _repository =
      widget.repository ?? RemoteBangumiRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppIconService.apply(_appIconStyle);
    });
  }

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

  Future<void> _setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    setState(() => _locale = locale);
    await widget.preferences?.setLocale(locale);
  }

  Future<void> _setAppIconStyle(AppIconStyle style) async {
    if (_appIconStyle == style) return;
    setState(() => _appIconStyle = style);
    await widget.preferences?.setIconStyle(style);
    await AppIconService.apply(style);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bangumi',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
        locale: _locale,
        onLocaleChanged: _setLocale,
        appIconStyle: _appIconStyle,
        onAppIconStyleChanged: _setAppIconStyle,
      ),
    );
  }
}
