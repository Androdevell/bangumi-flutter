import 'package:flutter/material.dart';
import '../core/settings/theme_preferences.dart';

@immutable
class AppVisualStyle extends ThemeExtension<AppVisualStyle> {
  const AppVisualStyle(this.style);
  final InterfaceStyle style;
  static bool glass(BuildContext context) =>
      Theme.of(context).extension<AppVisualStyle>()?.style ==
      InterfaceStyle.liquidGlass;

  @override
  AppVisualStyle copyWith({InterfaceStyle? style}) =>
      AppVisualStyle(style ?? this.style);
  @override
  AppVisualStyle lerp(covariant AppVisualStyle? other, double t) =>
      other == null || t < .5 ? this : other;
}
