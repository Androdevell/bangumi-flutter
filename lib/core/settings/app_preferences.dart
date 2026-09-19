import 'package:flutter/material.dart';

import '../auth/secure_vault.dart';

enum AppIconStyle { classic, anime }

@immutable
class AppPreferenceSnapshot {
  const AppPreferenceSnapshot({required this.locale, required this.iconStyle});

  final Locale locale;
  final AppIconStyle iconStyle;
}

class AppPreferences {
  AppPreferences(this._vault);

  static const _localeKey = 'app.preference.locale';
  static const _iconKey = 'app.preference.icon';

  final SecureVault _vault;

  Future<AppPreferenceSnapshot> load() async {
    final values = await Future.wait([
      _vault.read(_localeKey),
      _vault.read(_iconKey),
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
    );
  }

  Future<void> setLocale(Locale locale) =>
      _vault.write(_localeKey, locale.languageCode);

  Future<void> setIconStyle(AppIconStyle style) =>
      _vault.write(_iconKey, style.name);
}
