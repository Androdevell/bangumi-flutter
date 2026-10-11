import 'package:flutter/material.dart';

/// 所有自定义动效读取同一策略，同时尊重平台无障碍设置。
class AppMotionPolicy extends InheritedWidget {
  const AppMotionPolicy({
    super.key,
    required this.reduced,
    required super.child,
  });
  final bool reduced;
  static bool reduce(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<AppMotionPolicy>()?.reduced ??
          false) ||
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  static Duration duration(BuildContext context, int milliseconds) =>
      reduce(context) ? Duration.zero : Duration(milliseconds: milliseconds);
  @override
  bool updateShouldNotify(AppMotionPolicy oldWidget) =>
      reduced != oldWidget.reduced;
}
