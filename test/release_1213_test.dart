import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bangumi_flutter/core/navigation/bangumi_link.dart';
import 'package:bangumi_flutter/core/network/api_client.dart';
import 'package:bangumi_flutter/core/paged_controller.dart';
import 'package:bangumi_flutter/data/bangumi_repository.dart';
import 'package:bangumi_flutter/domain/repositories/tag_repository.dart';
import 'package:bangumi_flutter/core/models.dart';
import 'package:bangumi_flutter/widgets/release_markdown.dart';
import 'package:bangumi_flutter/widgets/theme_color_palette.dart';
import 'package:bangumi_flutter/widgets/image_viewer_page.dart';
import 'package:bangumi_flutter/features/blog/blog_detail_page.dart';
import 'package:bangumi_flutter/features/browse/tag_page.dart';
import 'package:bangumi_flutter/app/app_links.dart';
import 'package:bangumi_flutter/app/theme_controller.dart';
import 'package:bangumi_flutter/core/auth/secure_vault.dart';
import 'package:bangumi_flutter/core/settings/app_preferences.dart';
import 'package:bangumi_flutter/core/settings/theme_preferences.dart';
import 'package:bangumi_flutter/features/profile/theme_settings_page.dart';
import 'notification_composer_viewer_test.dart' show UnavailableImageCache;

Widget host(Widget child) => MaterialApp(home: child);

class MemoryVault implements SecureVault {
  final values = <String, String>{};
  int writes = 0;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  testWidgets(
    'second external link opens while first detail remains on stack',
    (tester) async {
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode(
                request.url.path.endsWith('/comments') ||
                        request.url.path.endsWith('/subjects')
                    ? []
                    : {
                      'id': int.parse(request.url.pathSegments.last),
                      'title': 'Linked blog',
                      'content': 'Body',
                      'user': {'username': 'fixture'},
                    },
              ),
              200,
            ),
          ),
        ),
      );
      late BuildContext linkContext;
      await tester.pumpWidget(
        MaterialApp(
          home: AppLinkScope(
            repository: repo,
            child: Builder(
              builder: (context) {
                linkContext = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      var opened = false;
      unawaited(
        AppLinkDispatcher.open(
          linkContext,
          Uri.parse('https://bgm.tv/blog/101'),
        ).then((value) {
          opened = value;
        }),
      );
      await tester.pumpAndSettle();
      expect(opened, true);
      opened = false;
      unawaited(
        AppLinkDispatcher.open(
          linkContext,
          Uri.parse('https://bgm.tv/blog/102'),
        ).then((value) {
          opened = value;
        }),
      );
      await tester.pumpAndSettle();
      expect(opened, true);
      expect(
        find.byType(BlogDetailPage, skipOffstage: false),
        findsNWidgets(2),
      );
      await tester.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  test(
    'optional blog section failures preserve body and explicit errors',
    () async {
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient(
            (request) async =>
                request.url.path == '/p1/blogs/42'
                    ? http.Response(
                      '{"id":42,"title":"Readable","content":"Body","user":{}}',
                      200,
                    )
                    : http.Response('{}', 403),
          ),
        ),
      );
      final detail = await repo.fetchBlog(42);
      expect(detail.blog.content, 'Body');
      expect(detail.errors.keys, containsAll(['subjects', 'comments']));
      repo.close();
    },
  );
  testWidgets('theme draft synchronizes HEX and saves only on Apply', (
    tester,
  ) async {
    final vault = MemoryVault();
    final preferences = AppPreferences(vault);
    final controller = ThemeController(
      preferences,
      const ComposeThemePreferences(),
    );
    await tester.pumpWidget(host(ThemeSettingsPage(controller: controller)));
    await tester.pumpAndSettle();
    final hex = find.byKey(const ValueKey('theme-seed-hex'));
    await tester.scrollUntilVisible(
      hex,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(hex, '#1234AB');
    await tester.pump();
    expect(vault.writes, 0);
    expect(controller.settings.seed, const ComposeThemePreferences().seed);
    expect(
      tester.widget<ThemeColorPalette>(find.byType(ThemeColorPalette)).color,
      const Color(0xff1234ab),
    );
    final apply = find.byKey(const ValueKey('theme-apply'));
    await tester.scrollUntilVisible(
      apply,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(vault.writes, 1);
    expect(controller.settings.seed, const Color(0xff1234ab));
    expect((await preferences.load()).theme.seed, const Color(0xff1234ab));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('palette retains hue at black and fits large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Color color = Colors.black;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: StatefulBuilder(
              builder:
                  (_, update) => ThemeColorPalette(
                    color: color,
                    onChanged: (next) => update(() => color = next),
                  ),
            ),
          ),
        ),
      ),
    );
    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(240);
    await tester.pump();
    expect(tester.widgetList<Slider>(find.byType(Slider)).first.value, 240);
    tester.widgetList<Slider>(find.byType(Slider)).elementAt(1).onChanged!(100);
    await tester.pump();
    tester.widgetList<Slider>(find.byType(Slider)).last.onChanged!(100);
    await tester.pump();
    expect(color, const Color(0xff0000ff));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'image handles wheel zoom and finger-count changes without jumps',
    (tester) async {
      await tester.pumpWidget(
        host(
          ImageViewerPage(
            urls: const ['https://example.test/multitouch.png'],
            cacheManager: UnavailableImageCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final zoom =
          tester
                  .widget<ValueListenableBuilder<Matrix4>>(
                    find.byKey(const ValueKey('viewer-transform')),
                  )
                  .valueListenable
              as ImageZoomController;
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 240),
          scrollDelta: Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(zoom.scale, greaterThan(1));
      final one = await tester.startGesture(const Offset(150, 240), pointer: 1);
      await one.moveBy(const Offset(10, 0));
      await tester.pump();
      final before = Matrix4.copy(zoom.value);
      final two = await tester.startGesture(const Offset(250, 240), pointer: 2);
      await tester.pump();
      expect(zoom.value, before);
      await two.moveBy(const Offset(20, 0));
      await tester.pump();
      final beforeRemove = Matrix4.copy(zoom.value);
      await two.up();
      await tester.pump();
      expect(zoom.value, beforeRemove);
      await one.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('tag page counts, exact Unicode values and repeated pages', () async {
    for (final tag in ['个人向', '2026年10月', '日文 + # /', '日本語']) {
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            expect(request.url.queryParameters['tags'], tag);
            expect(request.url.queryParameters['tagsCat'], 'subject');
            return http.Response(
              jsonEncode({
                'total': 2,
                'data': [
                  {'id': 1, 'name': 'fixture'},
                ],
              }),
              200,
            );
          }),
        ),
      );
      final first = await repo.tagPage(ComposeTagQuery(2, tag), 1);
      expect(first.hasMore, true);
      final last = await repo.tagPage(ComposeTagQuery(2, tag), 2);
      expect(last.hasMore, false);
      final pages = PagedController<Subject>(
        load: (cursor) => repo.tagPage(ComposeTagQuery(2, tag), cursor + 1),
        idOf: (s) => s.id,
        pageBased: true,
      );
      await pages.reset();
      await pages.loadMore();
      expect(pages.items.length, 1);
      expect(pages.hasMore, false);
      pages.dispose();
      repo.close();
    }
  });
  test('extended route canonicalization and unsafe encodings', () {
    expect(
      BangumiLinkParser.parse(
        'https://bangumi.tv/blog/42/?from=browser#post',
      )?.uri.toString(),
      'https://bgm.tv/blog/42',
    );
    expect(
      BangumiLinkParser.parse('https://bgm.tv/anime/tag/100%25')?.key,
      '100%',
    );
    for (final host in BangumiLinkParser.hosts) {
      expect(
        BangumiLinkParser.parse('https://$host/blog/42/?from=browser')?.kind,
        'blog',
      );
      final tag = BangumiLinkParser.parse(
        'https://$host/anime/tag/${Uri.encodeComponent('日文 + /')}/',
      );
      expect(tag?.key, '日文 + /');
      expect(tag?.kind, 'tag');
    }
    for (final path in [
      '/subject/topic/2/extra',
      '/blog/%ZZ',
      '/blog/2%2F',
      '/anime/tag/%00',
      '/blog/%252F',
    ]) {
      expect(BangumiLinkParser.parse('https://bgm.tv$path'), isNull);
    }
  });
  testWidgets(
    'Markdown renders selectable GFM without network images at narrow widths',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const notes =
          '## Version\n\n- **Feature** and `code`\n\n| Long column heading | Value |\n| --- | --- |\n| A very long table value without truncation | B |\n\n```dart\nprint(1);\n```\n\n[release](https://github.com/example/release)\n\n![tracker](https://tracker.invalid/a.png)';
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(child: ReleaseMarkdown(notes)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsWidgets);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(Table), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (final value in [
        'javascript:alert(1)',
        'file:///secret',
        'data:text/html,test',
        'https://user:password@github.com',
      ]) {
        expect(ReleaseMarkdown.safeLink(value), isNull);
      }
      expect(
        ReleaseMarkdown.safeLink('https://github.com/example/release'),
        isNotNull,
      );
    },
  );
  testWidgets(
    'palette dragging updates HSV with keyboard and numeric alternatives',
    (tester) async {
      Color color = Colors.red;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: StatefulBuilder(
              builder:
                  (_, setState) => ThemeColorPalette(
                    color: color,
                    onChanged: (next) => setState(() => color = next),
                  ),
            ),
          ),
        ),
      );
      await tester.dragFrom(const Offset(40, 40), const Offset(180, 70));
      await tester.pump();
      expect(HSVColor.fromColor(color).saturation, inInclusiveRange(0, 1));
      expect(HSVColor.fromColor(color).value, lessThan(1));
      expect(find.byType(Slider), findsNWidgets(3));
      expect(find.byType(TextFormField), findsNWidgets(3));
      final slider = tester.widgetList<Slider>(find.byType(Slider)).first;
      slider.onChanged!(240);
      await tester.pump();
      expect(HSVColor.fromColor(color).hue, closeTo(240, 1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'image release preserves matrix over subsequent frames at fit and zoom',
    (tester) async {
      await tester.pumpWidget(
        host(
          ImageViewerPage(
            urls: const ['https://example.test/release-test.png'],
            cacheManager: UnavailableImageCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final zoom =
          tester
                  .widget<ValueListenableBuilder<Matrix4>>(
                    find.byKey(const ValueKey('viewer-transform')),
                  )
                  .valueListenable
              as ImageZoomController;
      for (final image in [const Size(100, 1500), const Size(2000, 300)]) {
        zoom.natural = image;
        for (final scale in [1.0, 2.5, 8.0]) {
          zoom.reset();
          zoom.zoomAt(scale, zoom.viewport.center(Offset.zero));
          final gesture = await tester.startGesture(const Offset(160, 220));
          await gesture.moveBy(const Offset(0, -50));
          await tester.pump();
          final before = Matrix4.copy(zoom.value);
          await gesture.up();
          for (var frame = 0; frame < 20; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(zoom.value, before);
          }
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'blog route reads body comments and related subjects using GET only',
    (tester) async {
      final paths = <String>[];
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient((request) async {
            expect(request.method, 'GET');
            paths.add(request.url.path);
            final body = switch (request.url.path) {
              '/p1/blogs/42' => {
                'id': 42,
                'title': 'Fixture blog',
                'content': '[b]Body[/b]',
                'user': {'id': 1, 'username': 'fixture', 'nickname': 'Author'},
                'createdAt': 1700000000,
              },
              '/p1/blogs/42/subjects' => [
                {'id': 253, 'name': 'Related subject'},
              ],
              '/p1/blogs/42/comments' => [
                {
                  'id': 2,
                  'content': 'Fixture comment',
                  'user': {'id': 2, 'username': 'reader', 'nickname': 'Reader'},
                  'replies': [],
                },
              ],
              _ => <Object>[],
            };
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );
      await tester.pumpWidget(host(BlogDetailPage(id: 42, repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Fixture blog'), findsOneWidget);
      expect(find.text('Related subject'), findsOneWidget);
      expect(
        paths,
        containsAll([
          '/p1/blogs/42',
          '/p1/blogs/42/comments',
          '/p1/blogs/42/subjects',
        ]),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.close();
    },
  );
  testWidgets('tag zero results are distinct from retriable request failure', (
    tester,
  ) async {
    for (final failure in [false, true]) {
      final repo = RemoteBangumiRepository(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              failure ? '{}' : '{"total":0,"data":[]}',
              failure ? 403 : 200,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          TagPage(query: const ComposeTagQuery(2, 'missing'), repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('没有符合此标签的作品'), failure ? findsNothing : findsOneWidget);
      if (failure) expect(find.text('重试'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      repo.close();
    }
  });
  test('duplicate initial/native links share one pending delivery', () {
    var delivered = 0;
    void listener() => delivered++;
    AppLinkDispatcher.pending.addListener(listener);
    AppLinkDispatcher.receive('https://bangumi.tv/blog/934125?utm=first');
    AppLinkDispatcher.pending.value = null;
    AppLinkDispatcher.receive('https://bgm.tv/blog/934125/');
    expect(delivered, 2);
    AppLinkDispatcher.pending.removeListener(listener);
  });
}
