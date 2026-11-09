import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/app/app_theme.dart';
import 'package:bangumi_flutter/core/settings/theme_preferences.dart';
import 'package:bangumi_flutter/widgets/liquid_glass.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('frosted preview keeps actions usable dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(440, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('EXPORT_FROSTED_PREVIEW')) {
        await tester.runAsync(() async {
          final text = FontLoader('Preview');
          text.addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          );
          await text.load();
          final icons = FontLoader('MaterialIcons');
          icons.addFont(
            File(
              'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
          );
          await icons.load();
        });
      }
      final key = GlobalKey();
      var taps = 0;
      final base =
          dark
              ? AppTheme.dark(style: InterfaceStyle.liquidGlass)
              : AppTheme.light(style: InterfaceStyle.liquidGlass);
      await tester.pumpWidget(
        MaterialApp(
          theme:
              const bool.fromEnvironment('EXPORT_FROSTED_PREVIEW')
                  ? base.copyWith(
                    textTheme: base.textTheme.apply(fontFamily: 'Preview'),
                  )
                  : base,
          home: RepaintBoundary(
            key: key,
            child: AppGlassBackground(
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                      Text(
                        'Bangumi',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('每日放送 · 作品与记录'),
                      const SizedBox(height: 28),
                      const TextField(
                        decoration: InputDecoration(
                          hintText: '搜索作品',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 24),
                      LiquidGlassSurface(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_awesome, size: 36),
                              const SizedBox(height: 20),
                              const Text(
                                '发现下一部喜欢的作品',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text('轻盈柔和的毛玻璃 · 保留清晰阅读'),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: () => taps++,
                                child: const Text('浏览作品'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      LiquidGlassSurface(
                        blur: true,
                        radius: 32,
                        child: NavigationBar(
                          destinations: [
                            NavigationDestination(
                              icon: Icon(Icons.home_outlined),
                              label: '首页',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.explore_outlined),
                              label: '探索',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.person_outline),
                              label: '我的',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('浏览作品'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('EXPORT_FROSTED_PREVIEW')) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/verification').create(recursive: true);
          await File(
            'build/verification/frosted-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
