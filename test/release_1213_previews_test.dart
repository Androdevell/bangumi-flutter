import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/widgets/theme_color_palette.dart';
import 'package:bangumi_flutter/widgets/release_markdown.dart';

/// 显式启用时只生成离线视觉样本，不连接运行中的应用或账号。
void main() {
  testWidgets(
    'capture palette and Markdown previews',
    (tester) async {
      await tester.runAsync(() async {
        final font = FontLoader('Preview')..addFont(
          File(
            'C:/Windows/Fonts/segoeui.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
        await font.load();
        final mono = FontLoader('monospace')..addFont(
          File(
            'C:/Windows/Fonts/consola.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
        await mono.load();
      });
      tester.view.physicalSize = const Size(440, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final name in ['palette', 'markdown']) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            theme: ThemeData(
              fontFamily: 'Preview',
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            ),
            home: RepaintBoundary(
              key: const ValueKey('preview'),
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    name == 'palette'
                        ? 'Theme colors'
                        : 'What\'s new in 1.2.13',
                  ),
                ),
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child:
                      name == 'palette'
                          ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ThemeColorPalette(
                                color: Colors.indigo,
                                onChanged: (_) {},
                              ),
                              const SizedBox(height: 20),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      const Text('Material color preview'),
                                      FilledButton(
                                        onPressed: () {},
                                        child: const Text('Apply colors'),
                                      ),
                                      const LinearProgressIndicator(value: .6),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                          : const SingleChildScrollView(
                            child: ReleaseMarkdown(
                              '## Features\n\n- **Color palette** with hue, saturation and value.\n- Read blogs and subject topics in the app.\n\n## Fixes\n\n1. Correct user tag queries and pagination.\n2. Keep image position stable after dragging.\n\n| Platform | Version |\n| --- | --- |\n| Android and Windows | `1.2.13+2033` |\n\n```text\nSafe, selectable Markdown\n```\n\n[View release on GitHub](https://github.com/)',
                            ),
                          ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('preview')),
          matchesGoldenFile('../build/previews/$name-1213.png'),
        );
      }
    },
    skip: !const bool.fromEnvironment('CAPTURE_PREVIEWS'),
  );
}
