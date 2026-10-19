import 'package:flutter/material.dart';
import '../core/settings/app_preferences.dart';
import '../core/settings/theme_preferences.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this.preferences, this.settings);
  final AppPreferences? preferences;
  ComposeThemePreferences settings;
  bool saving = false;
  Future<void> apply(ComposeThemePreferences next) async {
    if (saving) return;
    saving = true;
    try {
      await preferences?.setTheme(next);
      settings = next;
      notifyListeners();
    } finally {
      saving = false;
    }
  }
}

class AppThemeScope extends InheritedNotifier<ThemeController> {
  const AppThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);
  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>()?.notifier;
}
