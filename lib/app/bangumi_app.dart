import 'dart:async';
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
import 'app_motion.dart';
import 'bootstrap/app_dependencies.dart';

class BangumiApp extends StatefulWidget {
  const BangumiApp({
    super.key,
    this.repository,
    this.dependencies,
    this.authService,
    this.preferences,
    this.initialLocale = const Locale('zh'),
    this.initialAppIconStyle = AppIconStyle.classic,
    this.initialReduceMotion = false,
  });

  final BangumiRepository? repository;
  final AppDependencies? dependencies;
  final AuthService? authService;
  final AppPreferences? preferences;
  final Locale initialLocale;
  final AppIconStyle initialAppIconStyle;
  final bool initialReduceMotion;

  @override
  State<BangumiApp> createState() => _BangumiAppState();
}

class _BangumiAppState extends State<BangumiApp> {
  ThemeMode _themeMode = ThemeMode.system;
  late Locale _locale = widget.initialLocale;
  late AppIconStyle _appIconStyle = widget.initialAppIconStyle;
  late bool _reduceMotion = widget.initialReduceMotion;
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
    if (widget.dependencies != null) {
      unawaited(widget.dependencies!.close());
    } else if (widget.repository == null) {
      _repository.close();
    }
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

  Future<void> _setReduceMotion(bool value) async {
    setState(() => _reduceMotion = value);
    await widget.preferences?.setReduceMotion(value);
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
      themeAnimationDuration:
          _reduceMotion || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        final content =
            RefreshRateProbe.enabled
                ? Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const RefreshRateProbe(),
                  ],
                )
                : child ?? const SizedBox.shrink();
        return AppMotionPolicy(
          reduced: _reduceMotion,
          child: HeroMode(
            enabled:
                !_reduceMotion && !MediaQuery.of(context).disableAnimations,
            child: content,
          ),
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
        reduceMotion: _reduceMotion,
        onReduceMotionChanged: _setReduceMotion,
      ),
    );
  }
}
