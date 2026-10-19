import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import '../core/settings/theme_preferences.dart';
import 'theme_controller.dart';

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
    this.initialTheme = const ComposeThemePreferences(),
  });

  final BangumiRepository? repository;
  final AppDependencies? dependencies;
  final AuthService? authService;
  final AppPreferences? preferences;
  final Locale initialLocale;
  final AppIconStyle initialAppIconStyle;
  final bool initialReduceMotion;
  final ComposeThemePreferences initialTheme;

  @override
  State<BangumiApp> createState() => _BangumiAppState();
}

class _BangumiAppState extends State<BangumiApp> with WidgetsBindingObserver {
  final _dynamicKey = GlobalKey<DynamicColorBuilderState>();
  late final ThemeController _theme = ThemeController(
    widget.preferences,
    widget.initialTheme,
  );
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ThemeMode get _themeMode => _theme.settings.mode;
  late Locale _locale = widget.initialLocale;
  late AppIconStyle _appIconStyle = widget.initialAppIconStyle;
  late bool _reduceMotion = widget.initialReduceMotion;
  late final BangumiRepository _repository =
      widget.repository ?? RemoteBangumiRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppIconService.apply(_appIconStyle);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _theme.dispose();
    if (widget.dependencies != null) {
      unawaited(widget.dependencies!.close());
    } else if (widget.repository == null) {
      _repository.close();
    }
    super.dispose();
  }

  Future<void> _toggleTheme() async {
    try {
      await _theme.apply(
        _theme.settings.copyWith(
          mode: switch (_themeMode) {
            ThemeMode.system || ThemeMode.light => ThemeMode.dark,
            ThemeMode.dark => ThemeMode.light,
          },
        ),
      );
    } on Object {
      _showSettingError('operationFailed');
    }
  }

  Future<void> _setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    setState(() => _locale = locale);
    await widget.preferences?.setLocale(locale);
  }

  Future<void> _setAppIconStyle(AppIconStyle style) async {
    if (_appIconStyle == style) return;
    final previous = _appIconStyle;
    if (!await AppIconService.apply(style)) {
      _showSettingError('iconApplyFailed');
      return;
    }
    try {
      await widget.preferences?.setIconStyle(style);
      if (mounted) setState(() => _appIconStyle = style);
    } on Object {
      await AppIconService.apply(previous);
      _showSettingError('operationFailed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_dynamicKey.currentState?.initPlatformState());
    }
  }

  void _showSettingError(String key) {
    final context = _messengerKey.currentContext;
    if (context != null) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).t(key))),
      );
    }
  }

  Future<void> _setReduceMotion(bool value) async {
    setState(() => _reduceMotion = value);
    await widget.preferences?.setReduceMotion(value);
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: _theme,
      child: ListenableBuilder(
        listenable: _theme,
        builder:
            (context, _) => DynamicColorBuilder(
              key: _dynamicKey,
              builder: (lightDynamic, darkDynamic) {
                final config = _theme.settings;
                final system = config.source == ThemeColorSource.system;
                final legacy =
                    config.source == ThemeColorSource.preset &&
                    config.preset == 'sakura';
                return MaterialApp(
                  scaffoldMessengerKey: _messengerKey,
                  debugShowCheckedModeBanner: false,
                  title: 'Bangumi',
                  theme: AppTheme.light(
                    seed: legacy ? null : config.seed,
                    dynamicScheme: system ? lightDynamic : null,
                  ),
                  darkTheme: AppTheme.dark(
                    seed: legacy ? null : config.seed,
                    dynamicScheme: system ? darkDynamic : null,
                  ),
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
                            !_reduceMotion &&
                            !MediaQuery.of(context).disableAnimations,
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
              },
            ),
      ),
    );
  }
}
