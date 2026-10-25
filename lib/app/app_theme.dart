import 'package:flutter/material.dart';
import 'app_motion.dart';
import 'visual_style.dart';
import '../core/settings/theme_preferences.dart';
import '../widgets/liquid_glass.dart';

abstract final class AppTheme {
  static const _brand = Color(0xFFE85D87);

  static ThemeData light({
    Color? seed,
    ColorScheme? dynamicScheme,
    InterfaceStyle style = InterfaceStyle.material,
  }) {
    if (dynamicScheme != null) return _build(dynamicScheme, style);
    if (seed != null) {
      return _build(ColorScheme.fromSeed(seedColor: seed), style);
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.light,
      primary: _brand,
      surface: const Color(0xFFFFF9FB),
      surfaceContainerLowest: Colors.white,
    );
    return _build(scheme, style);
  }

  static ThemeData dark({
    Color? seed,
    ColorScheme? dynamicScheme,
    InterfaceStyle style = InterfaceStyle.material,
  }) {
    if (dynamicScheme != null) return _build(dynamicScheme, style);
    if (seed != null) {
      return _build(
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        style,
      );
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: Brightness.dark,
      primary: const Color(0xFFFF8DAA),
      surface: const Color(0xFF171417),
      surfaceContainerLowest: const Color(0xFF100E10),
    );
    return _build(scheme, style);
  }

  static ThemeData _build(ColorScheme scheme, InterfaceStyle style) {
    final glass = style == InterfaceStyle.liquidGlass;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: glass ? Colors.transparent : scheme.surface,
      extensions: [AppVisualStyle(style)],
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
      ],
      textTheme: Typography.material2021().black
          .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
          .copyWith(
            headlineMedium: TextStyle(
              color: scheme.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            titleLarge: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
            titleMedium: TextStyle(
              color: scheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
            bodyMedium: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.16),
        surfaceTintColor: scheme.primary.withValues(alpha: 0.035),
        margin: EdgeInsets.zero,
        color:
            glass
                ? scheme.surface.withValues(alpha: .86)
                : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(glass ? 24 : 16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: glass ? 0 : 2,
        backgroundColor:
            glass ? Colors.transparent : scheme.surfaceContainerLowest,
        indicatorColor:
            glass
                ? scheme.primaryContainer.withValues(alpha: .68)
                : scheme.primaryContainer,
        surfaceTintColor: glass ? Colors.transparent : null,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor:
            glass ? Colors.transparent : scheme.surfaceContainerLowest,
        indicatorColor:
            glass
                ? scheme.primaryContainer.withValues(alpha: .68)
                : scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            glass
                ? scheme.surface.withValues(alpha: .82)
                : scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.55),
      splashFactory: glass ? InkRipple.splashFactory : InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: glass ? 0 : 1,
        centerTitle: false,
        backgroundColor: scheme.surface.withValues(alpha: glass ? .9 : .94),
        surfaceTintColor:
            glass ? Colors.transparent : scheme.primary.withValues(alpha: 0.06),
      ),
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 8,
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(glass ? 22 : 14),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _MotionPageTransition(),
          TargetPlatform.windows: _MotionPageTransition(),
          TargetPlatform.linux: _MotionPageTransition(),
          TargetPlatform.macOS: _MotionPageTransition(),
          TargetPlatform.iOS: _MotionPageTransition(),
        },
      ),
    );
  }
}

class _MotionPageTransition extends PageTransitionsBuilder {
  const _MotionPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final surface = AppGlassBackground(child: child);
    if (AppMotionPolicy.reduce(context)) return surface;
    final platform = Theme.of(context).platform;
    final PageTransitionsBuilder transition =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
            ? const CupertinoPageTransitionsBuilder()
            : const FadeUpwardsPageTransitionsBuilder();
    return transition.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      surface,
    );
  }
}
