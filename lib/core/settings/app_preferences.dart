import 'package:flutter/material.dart';

import '../auth/secure_vault.dart';
import 'theme_preferences.dart';
import '../network/platform_http_client.dart';

enum AppIconStyle { classic, anime }

@immutable
class AppPreferenceSnapshot {
  const AppPreferenceSnapshot({
    required this.locale,
    required this.iconStyle,
    this.thirdPartyPreviews = false,
    this.reduceMotion = false,
    this.theme = const ComposeThemePreferences(),
    this.networkMode = WindowsNetworkMode.system,
  });

  final Locale locale;
  final AppIconStyle iconStyle;
  final bool thirdPartyPreviews;
  final bool reduceMotion;
  final ComposeThemePreferences theme;
  final WindowsNetworkMode networkMode;
}

class AppPreferences {
  AppPreferences(this._vault);

  static const _localeKey = 'app.preference.locale';
  static const _iconKey = 'app.preference.icon';
  static const _previewsKey = 'app.preference.thirdPartyPreviews.v1';
  static const _motionKey = 'app.preference.reduceMotion';

  final SecureVault _vault;

  Future<AppPreferenceSnapshot> load() async {
    final values = await Future.wait([
      _vault.read(_localeKey),
      _vault.read(_iconKey),
      _vault.read(_previewsKey),
      _vault.read(_motionKey),
      _vault.read('app.preference.theme.v1'),
      _vault.read('app.preference.windowsNetwork.v1'),
    ]);
    final localeCode = switch (values[0]) {
      'en' => 'en',
      'ja' => 'ja',
      _ => 'zh',
    };
    final iconStyle =
        values[1] == AppIconStyle.anime.name
            ? AppIconStyle.anime
            : AppIconStyle.classic;
    return AppPreferenceSnapshot(
      locale: Locale(localeCode),
      iconStyle: iconStyle,
      thirdPartyPreviews: values[2] == 'true',
      reduceMotion: values[3] == 'true',
      theme: ComposeThemePreferences.decode(values[4]),
      networkMode:
          values[5] == 'direct'
              ? WindowsNetworkMode.direct
              : WindowsNetworkMode.system,
    );
  }

  Future<void> setLocale(Locale locale) =>
      _vault.write(_localeKey, locale.languageCode);

  Future<void> setIconStyle(AppIconStyle style) =>
      _vault.write(_iconKey, style.name);

  Future<void> setThirdPartyPreviews(bool enabled) =>
      _vault.write(_previewsKey, '$enabled');
  Future<void> setReduceMotion(bool enabled) =>
      _vault.write(_motionKey, '$enabled');
  Future<void> setTheme(ComposeThemePreferences value) =>
      _vault.write('app.preference.theme.v1', value.encode());
  Future<void> setNetworkMode(WindowsNetworkMode value) =>
      _vault.write('app.preference.windowsNetwork.v1', value.name);
}
