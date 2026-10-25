import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../app/app_motion.dart';
import '../app/visual_style.dart';

/// 每个路由自带不透明底色，透明 Scaffold 不会透出上一页的文字。
class AppGlassBackground extends StatelessWidget {
  const AppGlassBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AmbientPainter(
                Theme.of(context).colorScheme,
                AppVisualStyle.glass(context) &&
                    !(MediaQuery.maybeOf(context)?.highContrast ?? false),
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// 只为固定导航启用模糊，列表、表单和正文仅绘制半透明渐变。
class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.blur = false,
    this.radius = 24,
  });
  final Widget child;
  final bool blur;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final contrast = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final shape = BorderRadius.circular(radius);
    Widget surface = Material(
      color:
          contrast
              ? scheme.surfaceContainerLowest
              : scheme.surface.withValues(
                alpha: blur ? (dark ? .68 : .52) : (dark ? .82 : .74),
              ),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient:
              contrast
                  ? null
                  : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: dark ? .09 : .55),
                      scheme.primary.withValues(alpha: dark ? .025 : .018),
                      Colors.white.withValues(alpha: dark ? .025 : .24),
                    ],
                    stops: const [0, .55, 1],
                  ),
        ),
        child: child,
      ),
    );
    if (blur && !contrast && !AppMotionPolicy.reduce(context)) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: surface,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: dark ? .14 : .065),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(
              color:
                  contrast
                      ? scheme.outline
                      : Color.lerp(
                        Colors.white,
                        scheme.primary,
                        dark ? .55 : .14,
                      )!.withValues(alpha: dark ? .3 : .85),
            ),
          ),
          child: surface,
        ),
      ),
    );
  }
}

class AdaptiveCard extends StatelessWidget {
  const AdaptiveCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      AppVisualStyle.glass(context)
          ? LiquidGlassSurface(child: child)
          : Card(clipBehavior: Clip.antiAlias, child: child);
}

class AdaptiveActionSurface extends StatelessWidget {
  const AdaptiveActionSurface({
    super.key,
    required this.child,
    this.classicColor,
  });
  final Widget child;
  final Color? classicColor;
  @override
  Widget build(BuildContext context) =>
      AppVisualStyle.glass(context)
          ? LiquidGlassSurface(child: child)
          : Material(
            color:
                classicColor ??
                Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            child: child,
          );
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.scheme, this.glass);
  final ColorScheme scheme;
  final bool glass;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = scheme.surface);
    if (!glass) return;
    final dark = scheme.brightness == Brightness.dark;
    for (final (center, color, radius) in [
      (const Alignment(-1, -.8), scheme.primary, .95),
      (const Alignment(1.1, .45), scheme.tertiary, .85),
      (const Alignment(-.4, 1.2), scheme.secondary, .75),
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: center,
            radius: radius,
            colors: [
              color.withValues(alpha: dark ? .16 : .13),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.scheme != scheme || oldDelegate.glass != glass;
}
