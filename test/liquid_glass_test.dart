import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bangumi_flutter/app/app_motion.dart';
import 'package:bangumi_flutter/app/app_theme.dart';
import 'package:bangumi_flutter/app/bangumi_app.dart';
import 'package:bangumi_flutter/app/theme_controller.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/localization/app_localizations.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/core/settings/app_preferences.dart';
import 'package:bangumi_flutter/core/settings/theme_preferences.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/features/discover/discover_page.dart';
import 'package:bangumi_flutter/features/profile/theme_settings_page.dart';
import 'package:bangumi_flutter/widgets/common.dart';
import 'package:bangumi_flutter/widgets/liquid_glass.dart';
import 'package:bangumi_flutter/widgets/subject_card.dart';

class _Vault extends MemorySecureVault {
  bool fail = false;
  int writes = 0;
  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (fail) throw StateError('fixture failure');
    await super.write(key, value);
  }
}

class _Calendar extends Fake implements BangumiRepository {
  int reads = 0;
  @override
  bool get isLoggedIn => false;
  @override
  Future<Map<String, List<Subject>>> fetchCalendar() async {
    reads++;
    final items = List.generate(
      35,
      (i) => Subject(id: i + 1, title: 'Work $i'),
    );
    return {
      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
        day: items,
    };
  }
}

Widget host(
  Widget child, {
  bool dark = false,
  MediaQueryData? media,
  bool reduced = false,
}) => MaterialApp(
  theme:
      dark
          ? AppTheme.dark(style: InterfaceStyle.liquidGlass)
          : AppTheme.light(style: InterfaceStyle.liquidGlass),
  builder:
      (context, child) => AppMotionPolicy(
        reduced: reduced,
        child: MediaQuery(data: media ?? MediaQuery.of(context), child: child!),
      ),
  home: child,
);

void main() {
  test('old and unknown style values keep existing color and mode', () {
    const old = ComposeThemePreferences(
      source: ThemeColorSource.custom,
      seed: Color(0xff123456),
      mode: ThemeMode.dark,
    );
    final json = jsonDecode(old.encode()) as Map<String, dynamic>;
    for (final value in [null, 'future-style']) {
      json['style'] = value;
      final restored = ComposeThemePreferences.decode(jsonEncode(json));
      expect(restored.style, InterfaceStyle.material);
      expect(restored.seed, old.seed);
      expect(restored.mode, old.mode);
      expect(restored.source, old.source);
    }
  });
  test('style, system color and dark mode persist together', () async {
    final preferences = AppPreferences(_Vault());
    final controller = ThemeController(
      preferences,
      const ComposeThemePreferences(),
    );
    addTearDown(controller.dispose);
    await controller.apply(
      controller.settings.copyWith(
        style: InterfaceStyle.liquidGlass,
        source: ThemeColorSource.system,
        mode: ThemeMode.dark,
      ),
    );
    final restored = (await preferences.load()).theme;
    expect(restored.style, InterfaceStyle.liquidGlass);
    expect(restored.mode, ThemeMode.dark);
    expect(restored.source, ThemeColorSource.system);
  });
  testWidgets('preview stays a draft; sticky Apply persists it', (
    tester,
  ) async {
    final vault = _Vault();
    final preferences = AppPreferences(vault);
    final controller = ThemeController(
      preferences,
      const ComposeThemePreferences(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(ThemeSettingsPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-style-liquidGlass')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-style-liquidGlass')));
    await tester.pumpAndSettle();
    expect(vault.writes, 0);
    expect(controller.settings.style, InterfaceStyle.material);
    await tester.tap(find.byKey(const ValueKey('theme-apply')));
    await tester.pumpAndSettle();
    expect((await preferences.load()).theme.style, InterfaceStyle.liquidGlass);
    expect(vault.writes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed save keeps applied style and allows retry', (
    tester,
  ) async {
    final vault = _Vault()..fail = true;
    final controller = ThemeController(
      AppPreferences(vault),
      const ComposeThemePreferences(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(ThemeSettingsPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-style-liquidGlass')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-style-liquidGlass')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-apply')));
    await tester.pumpAndSettle();
    expect(controller.settings.style, InterfaceStyle.material);
    expect(find.byType(SnackBar), findsOneWidget);
    vault.fail = false;
    await tester.tap(find.byKey(const ValueKey('theme-apply')));
    await tester.pumpAndSettle();
    expect(controller.settings.style, InterfaceStyle.liquidGlass);
    await tester.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    testWidgets('narrow large text style picker and sticky save: dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ThemeController(
        null,
        const ComposeThemePreferences(style: InterfaceStyle.liquidGlass),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          ThemeSettingsPage(controller: controller),
          dark: dark,
          media: const MediaQueryData(
            size: Size(360, 900),
            textScaler: TextScaler.linear(1.6),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('theme-style-liquidGlass')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('theme-apply'))).dy,
        lessThan(900),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('theme-apply'))).width,
        greaterThan(250),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final (reduced, contrast, expected) in [
    (false, false, 1),
    (true, false, 0),
    (false, true, 0),
  ]) {
    testWidgets(
      'navigation blur respects reduced=$reduced contrast=$contrast',
      (tester) async {
        await tester.pumpWidget(
          host(
            const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: LiquidGlassSurface(blur: true, child: Text('Surface')),
                ),
              ),
            ),
            reduced: reduced,
            media: MediaQueryData(
              size: const Size(800, 600),
              highContrast: contrast,
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNWidgets(expected));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('scrolling cards have no per-item blur and retain taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: ListView(
            children: [
              SurfaceBlock(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Action'),
                ),
              ),
              for (var i = 0; i < 12; i++)
                SizedBox(
                  height: 280,
                  child: SubjectCard(
                    subject: Subject(id: i, title: 'Card $i'),
                    heroTag: 'fixture-$i',
                    onTap: () => taps++,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('Action'));
    expect(taps, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'switching styles retains scroll and calendar request: width=$width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = _Calendar();
        await tester.pumpWidget(BangumiApp(repository: repo));
        await tester.pumpAndSettle();
        expect(repo.reads, 1);
        final scroll =
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first;
        await tester.drag(scroll, const Offset(0, -300));
        await tester.pumpAndSettle();
        final position = tester.state<ScrollableState>(scroll).position;
        final offset = position.pixels;
        expect(offset, greaterThan(0));
        final controller =
            AppThemeScope.maybeOf(tester.element(find.byType(DiscoverPage)))!;
        await controller.apply(
          controller.settings.copyWith(style: InterfaceStyle.liquidGlass),
        );
        await tester.pumpAndSettle();
        expect(repo.reads, 1);
        expect(position.pixels, closeTo(offset, 1));
        expect(find.byType(BackdropFilter), findsOneWidget);
        await controller.apply(
          controller.settings.copyWith(style: InterfaceStyle.material),
        );
        await tester.pumpAndSettle();
        expect(repo.reads, 1);
        expect(position.pixels, closeTo(offset, 1));
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('style labels are localized in all supported languages', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final strings = AppLocalizations(locale);
      for (final key in [
        'interfaceStyle',
        'styleMaterial',
        'styleLiquidGlassHint',
        'styleApplyHint',
        'glassAccessibilityHint',
      ]) {
        expect(strings.t(key), isNot(key));
      }
    }
  });
}
